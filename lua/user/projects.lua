-- Project switcher + auto-session. A "project" is a directory with a .git
-- (or any of the configured markers). Switching to one cds, restores its
-- workspace snapshot (via user.workspace), retitles the current tab, and
-- pushes onto the recent list.
--
-- Discovery sources (deduped, in priority order):
--   1. recent       - explicitly switched-to, persisted
--   2. pinned       - user added via :ProjectPin
--   3. discovered   - one-level scan of M.roots for ./*/.git
local M = {}

local brand = require("user.brand")

-- ─── config ──────────────────────────────────────────────────────────────
M.roots   = {
  vim.fn.expand("~/code"),
  vim.fn.expand("~/work"),
  vim.fn.expand("~/projects"),
  vim.fn.expand("~/.config"),
}
M.markers = { ".git", ".jj", "package.json", "Cargo.toml", "pyproject.toml", "go.mod" }

local STATE_FILE = vim.fn.stdpath("state") .. "/projects.json"
local _state = { pinned = {}, recent = {} }   -- recent: [{ path, ts }]
local RECENT_CAP = 30

local function load_state()
  local f = io.open(STATE_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a"), { luanil = { object = true, array = true } })
  f:close()
  if ok and type(parsed) == "table" then _state = vim.tbl_deep_extend("force", _state, parsed) end
end

local function save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  local f = io.open(STATE_FILE, "w")
  if f then f:write(vim.json.encode(_state)); f:close() end
end

-- ─── helpers ─────────────────────────────────────────────────────────────
local function is_project(dir)
  for _, mk in ipairs(M.markers) do
    if vim.uv.fs_stat(dir .. "/" .. mk) then return true end
  end
  return false
end

local function discover()
  local out = {}
  for _, root in ipairs(M.roots) do
    if vim.uv.fs_stat(root) then
      local handle = vim.uv.fs_scandir(root)
      if handle then
        while true do
          local name, ftype = vim.uv.fs_scandir_next(handle)
          if not name then break end
          if ftype == "directory" and not name:match("^%.") then
            local p = root .. "/" .. name
            if is_project(p) then table.insert(out, p) end
          end
        end
      end
    end
  end
  return out
end

local function push_recent(path)
  if not path or path == "" then return end
  local out = { { path = path, ts = os.time() } }
  for _, r in ipairs(_state.recent) do
    if r.path ~= path and #out < RECENT_CAP then table.insert(out, r) end
  end
  _state.recent = out; save_state()
end

-- Public list of {path, label, source} for the picker.
function M.list()
  local seen, out = {}, {}
  local function add(path, source)
    path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
    if seen[path] then return end
    seen[path] = true
    table.insert(out, {
      path = path,
      label = vim.fn.fnamemodify(path, ":t"),
      source = source,
    })
  end
  for _, r in ipairs(_state.recent) do add(r.path, "recent") end
  for _, p in ipairs(_state.pinned) do add(p, "pinned") end
  for _, p in ipairs(discover())   do add(p, "discovered") end
  return out
end

-- ─── switching ───────────────────────────────────────────────────────────
-- cd into the project, attempt to restore its user.workspace snapshot, and
-- name the current tab after it. Doesn't open a new tab — switches the
-- current one. (Use :tabnew first if you want a fresh tab.)
function M.switch(path)
  if not path or path == "" then return end
  path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
  if not vim.uv.fs_stat(path) then
    brand.notify("not a directory: " .. path, vim.log.levels.WARN, { title = "projects" })
    return
  end
  push_recent(path)
  vim.cmd("tcd " .. vim.fn.fnameescape(path))
  -- restore workspace (silent — many projects won't have one)
  local ok, ws = pcall(require, "user.workspace")
  if ok then pcall(ws.load) end
  -- name the tab
  local ok2, tabs = pcall(require, "user.tabs")
  if ok2 then tabs.set_name(nil, vim.fn.fnamemodify(path, ":t")) end
  brand.notify("→ " .. vim.fn.fnamemodify(path, ":~"), nil, { title = "projects" })
end

function M.show()
  local items = M.list()
  if #items == 0 then
    brand.notify("no projects found · add roots in user.projects.roots or :ProjectPin",
      vim.log.levels.WARN, { title = "projects" })
    return
  end
  local labels = {}
  for _, it in ipairs(items) do
    table.insert(labels, ("%-10s  %-22s  %s"):format(
      "[" .. it.source .. "]", it.label,
      vim.fn.fnamemodify(it.path, ":~"):sub(1, 60)))
  end
  vim.ui.select(labels, { prompt = "project: " }, function(_, idx)
    if not idx then return end
    M.switch(items[idx].path)
  end)
end

-- ─── pinning ─────────────────────────────────────────────────────────────
function M.pin(path)
  path = vim.fn.fnamemodify(path or vim.fn.getcwd(), ":p"):gsub("/$", "")
  if vim.tbl_contains(_state.pinned, path) then
    brand.notify("already pinned", nil, { title = "projects" }); return
  end
  table.insert(_state.pinned, path); save_state()
  brand.notify("pinned · " .. vim.fn.fnamemodify(path, ":~"), nil, { title = "projects" })
end

function M.unpin(path)
  path = vim.fn.fnamemodify(path or vim.fn.getcwd(), ":p"):gsub("/$", "")
  for i, p in ipairs(_state.pinned) do
    if p == path then
      table.remove(_state.pinned, i); save_state()
      brand.notify("unpinned · " .. vim.fn.fnamemodify(path, ":~"), nil, { title = "projects" })
      return
    end
  end
end

-- ─── auto-session ────────────────────────────────────────────────────────
-- On VimEnter into a project (cwd matches a marker), if there's a workspace
-- snapshot we silently load it. On VimLeavePre, save the snapshot. Both are
-- opt-out via global flag so users who want a clean nvim can disable.
M.auto_session = true

local function _maybe_auto_load()
  if not M.auto_session then return end
  if vim.fn.argc() ~= 0 then return end   -- user opened files explicitly
  local cwd = vim.fn.getcwd()
  if not is_project(cwd) then return end
  local ok, ws = pcall(require, "user.workspace")
  if not ok then return end
  -- check that a snapshot exists before calling load (which prints "no snap")
  local snap = vim.fn.stdpath("state") .. "/workspaces/" .. cwd:gsub("/", "%%") .. ".json"
  if vim.uv.fs_stat(snap) then pcall(ws.load) end
end

local function _maybe_auto_save()
  if not M.auto_session then return end
  if not is_project(vim.fn.getcwd()) then return end
  local ok, ws = pcall(require, "user.workspace")
  if ok then pcall(ws.save) end
end

-- ─── setup ───────────────────────────────────────────────────────────────
function M.setup()
  load_state()

  local grp = vim.api.nvim_create_augroup("user_projects", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter",     { group = grp, callback = _maybe_auto_load,
    desc = "auto-restore workspace on entering a project" })
  vim.api.nvim_create_autocmd("VimLeavePre",  { group = grp, callback = _maybe_auto_save,
    desc = "auto-save workspace on leaving a project" })

  vim.api.nvim_create_user_command("Projects",    M.show,
    { desc = "Pick a project (recent / pinned / discovered)" })
  vim.api.nvim_create_user_command("ProjectPin",
    function(a) M.pin(a.args ~= "" and vim.fn.expand(a.args) or nil) end,
    { nargs = "?", complete = "dir", desc = "Pin a directory as a project" })
  vim.api.nvim_create_user_command("ProjectUnpin",
    function(a) M.unpin(a.args ~= "" and vim.fn.expand(a.args) or nil) end,
    { nargs = "?", complete = "dir", desc = "Unpin a project" })
  vim.api.nvim_create_user_command("ProjectAutoSession",
    function(a)
      if a.args == "off" then M.auto_session = false
      elseif a.args == "on" then M.auto_session = true
      else M.auto_session = not M.auto_session end
      brand.notify("auto-session " .. (M.auto_session and "on" or "off"),
        nil, { title = "projects" })
    end,
    { nargs = "?", complete = function() return { "on", "off" } end,
      desc = "Toggle auto-session per project" })
end

return M
