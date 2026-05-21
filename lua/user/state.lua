-- UserState: a single inspector for every state file our user modules have
-- accumulated. Lists size + age + description. Inspect, clear, or export to
-- a tarball you can carry to another machine.
local M = {}

local STATE_DIR = vim.fn.stdpath("state")
local NS = vim.api.nvim_create_namespace("user_state")

-- ─── registry of known state files ────────────────────────────────────────
local function registry()
  return {
    { id = "suggest",    path = STATE_DIR .. "/suggest_state.json",
      desc = "Suggest learning · usage / ctx-picks / sequences", json = true },
    { id = "playbooks",  path = STATE_DIR .. "/playbooks.json",
      desc = "Playbook names · pins · hidden chains",            json = true },
    { id = "commandeer", path = STATE_DIR .. "/commandeer_state.json",
      desc = "Commandeer · learned filter loosenings per ft",    json = true },
    { id = "yankring",   path = STATE_DIR .. "/yankring.json",
      desc = "Persistent yank-ring history (50 entries)",        json = true },
    { id = "macros",     path = STATE_DIR .. "/macros.json",
      desc = "Named macro library",                              json = true },
    { id = "tiny_world", path = STATE_DIR .. "/tiny_world.json",
      desc = ":Play tiny_world · ASCII garden state",            json = true },
    { id = "jira",       path = STATE_DIR .. "/jira_cache.json",
      desc = "Jira · branch pins · recent issues · saved filters", json = true },
    { id = "confluence", path = STATE_DIR .. "/confluence_cache.json",
      desc = "Confluence · recently viewed pages (yours)",       json = true },
    { id = "tabs",       path = STATE_DIR .. "/tab_names.json",
      desc = "Custom tab names (tabid-keyed, serialized by tabnr)", json = true },
    { id = "tab_undo",   path = STATE_DIR .. "/tab_undo_stack.json",
      desc = "Tab undo-close stack · cross-session recovery (10 deep)", json = true },
    { id = "layouts",    path = STATE_DIR .. "/window_layouts",
      desc = "Saved window/tab layouts (mksession files)",       dir = true },
    { id = "projects",   path = STATE_DIR .. "/projects.json",
      desc = "Project switcher · pinned + recent paths",         json = true },
    { id = "hints",      path = STATE_DIR .. "/hints_seen.json",
      desc = "Hint chip · shown-count per hint id",              json = true },
    { id = "profiles",   path = STATE_DIR .. "/profiles.json",
      desc = "Filetype auto-layout profiles · enabled set",      json = true },
    { id = "welcome",    path = STATE_DIR .. "/.welcomed",
      desc = "First-launch welcome marker",                      marker = true },
    { id = "tour",       path = STATE_DIR .. "/.toured",
      desc = "Tour-seen marker",                                 marker = true },
    { id = "workspaces", path = STATE_DIR .. "/workspaces",
      desc = "Per-project workspace snapshots",                  dir = true },
    { id = "quill",      path = STATE_DIR .. "/quill",
      desc = "Keystroke steno recordings",                       dir = true },
    { id = "cipher",     path = STATE_DIR .. "/cipher.enc",
      desc = "Encrypted scratchpad (opaque · not exportable)",   sensitive = true },
    { id = "lsp_log",    path = STATE_DIR .. "/lsp.log",
      desc = "LSP log (system · not exported)",                  system = true },
  }
end

-- ─── helpers ───────────────────────────────────────────────────────────────
local function fmt_size(b)
  if not b or b == 0 then return "—" end
  if b < 1024 then return b .. "B" end
  if b < 1024 * 1024 then return string.format("%.1fK", b / 1024) end
  if b < 1024 * 1024 * 1024 then return string.format("%.1fM", b / 1024 / 1024) end
  return string.format("%.1fG", b / 1024 / 1024 / 1024)
end

local function fmt_age(ts)
  if not ts or ts == 0 then return "—" end
  local age = os.time() - ts
  if age < 60 then return age .. "s ago" end
  if age < 3600 then return math.floor(age / 60) .. "m ago" end
  if age < 86400 then return math.floor(age / 3600) .. "h ago" end
  return math.floor(age / 86400) .. "d ago"
end

local function dir_aggregate(path)
  local total, count, newest = 0, 0, 0
  local handle = vim.uv.fs_scandir(path)
  if not handle then return 0, 0, 0 end
  while true do
    local name, ftype = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if ftype == "file" then
      local st = vim.uv.fs_stat(path .. "/" .. name)
      if st then
        total = total + st.size
        count = count + 1
        if st.mtime.sec > newest then newest = st.mtime.sec end
      end
    end
  end
  return total, count, newest
end

local function enrich(entry)
  if entry.dir then
    local total, count, mtime = dir_aggregate(entry.path)
    entry.size, entry.mtime, entry.count, entry.present = total, mtime, count, count > 0
  else
    local st = vim.uv.fs_stat(entry.path)
    if st then
      entry.size, entry.mtime, entry.present = st.size, st.mtime.sec, true
    else
      entry.size, entry.mtime, entry.present = 0, 0, false
    end
  end
  return entry
end

function M.list()
  local r = registry()
  for _, e in ipairs(r) do enrich(e) end
  return r
end

-- ─── operations ───────────────────────────────────────────────────────────
local function clear_one(entry)
  if entry.dir then
    local handle = vim.uv.fs_scandir(entry.path)
    if handle then
      while true do
        local name = vim.uv.fs_scandir_next(handle)
        if not name then break end
        pcall(vim.uv.fs_unlink, entry.path .. "/" .. name)
      end
    end
  else
    pcall(vim.uv.fs_unlink, entry.path)
  end
end

function M.clear(id)
  for _, e in ipairs(registry()) do
    if e.id == id then
      enrich(e)
      if not e.present then return false, "nothing to clear" end
      local prompt = ("clear  %s  ?\n\n%s  ·  %s"):format(e.id, fmt_size(e.size), e.desc)
      local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)
      if choice ~= 1 then return false, "cancelled" end
      clear_one(e)
      pcall(require("user.brand").notify, ("cleared  %s"):format(id), nil, { title = "userstate" })
      return true
    end
  end
  return false, "unknown id: " .. tostring(id)
end

function M.inspect(id)
  for _, e in ipairs(registry()) do
    if e.id == id then
      if e.sensitive then
        pcall(require("user.brand").notify, "cannot inspect encrypted state", vim.log.levels.WARN, { title = "userstate" })
        return
      end
      if not vim.uv.fs_stat(e.path) then
        pcall(require("user.brand").notify, "no state for " .. id, nil, { title = "userstate" })
        return
      end
      if e.dir then
        pcall(vim.cmd, "tabnew | terminal ls -la " .. vim.fn.fnameescape(e.path))
        return
      end
      vim.cmd("tabnew " .. vim.fn.fnameescape(e.path))
      -- Pretty-print JSON files via jq if available
      if e.json and vim.fn.executable("jq") == 1 then
        local raw = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
        if raw ~= "" then
          local pretty = vim.fn.system({ "jq", "." }, raw)
          if vim.v.shell_error == 0 then
            vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(pretty, "\n"))
            vim.bo.modified = false
            vim.bo.filetype = "json"
          end
        end
      end
      return
    end
  end
end

function M.export(out_path)
  out_path = out_path or vim.fn.expand("~") .. "/nvim-state-" .. os.date("%Y%m%d-%H%M%S") .. ".tar.gz"
  -- Build the include list: everything present that isn't sensitive or system
  local includes = {}
  for _, e in ipairs(registry()) do
    enrich(e)
    if e.present and not e.sensitive and not e.system then
      table.insert(includes, vim.fn.fnamemodify(e.path, ":t"))
    end
  end
  if #includes == 0 then
    pcall(require("user.brand").notify, "no state to export", vim.log.levels.WARN, { title = "userstate" })
    return
  end
  local cmd = { "tar", "-czf", out_path, "-C", STATE_DIR }
  for _, name in ipairs(includes) do table.insert(cmd, name) end
  local res = vim.system(cmd):wait()
  if res.code == 0 then
    pcall(require("user.brand").notify,
      ("exported  %d items  →  %s"):format(#includes, out_path), nil, { title = "userstate" })
  else
    pcall(require("user.brand").notify,
      "export failed: " .. (res.stderr or ""), vim.log.levels.ERROR, { title = "userstate" })
  end
end

function M.import(in_path)
  if not in_path or not vim.uv.fs_stat(in_path) then
    pcall(require("user.brand").notify, "file not found: " .. tostring(in_path), vim.log.levels.ERROR, { title = "userstate" })
    return
  end
  local choice = vim.fn.confirm(
    ("import  %s ?\n\nThis OVERWRITES existing state files in %s"):format(
      vim.fn.fnamemodify(in_path, ":~"), STATE_DIR),
    "&Yes\n&No", 2)
  if choice ~= 1 then return end
  vim.fn.mkdir(STATE_DIR, "p")
  local res = vim.system({ "tar", "-xzf", in_path, "-C", STATE_DIR }):wait()
  if res.code == 0 then
    pcall(require("user.brand").notify, "imported · restart nvim to reload everything", nil, { title = "userstate" })
  else
    pcall(require("user.brand").notify, "import failed", vim.log.levels.ERROR, { title = "userstate" })
  end
end

-- ─── panel ────────────────────────────────────────────────────────────────
local panel = { win = nil, buf = nil, items = {} }

local function close()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_win_close(panel.win, true)
  end
  panel.win, panel.buf, panel.items = nil, nil, {}
end

local function render()
  if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then return end
  panel.items = M.list()
  vim.api.nvim_buf_clear_namespace(panel.buf, NS, 0, -1)

  local lines = { "" }
  local total = 0
  for i, e in ipairs(panel.items) do
    total = total + (e.size or 0)
    local presence
    if e.dir then presence = e.count > 0 and (e.count .. " files") or "—"
    elseif e.marker then presence = e.present and "set" or "unset"
    elseif e.sensitive then presence = e.present and "encrypted" or "—"
    elseif e.system then presence = e.present and "system" or "—"
    else presence = e.present and "ok" or "—"
    end
    table.insert(lines, string.format("    %2d   %-11s  %8s  %-9s   %-9s  %s",
      i, e.id, fmt_size(e.size), fmt_age(e.mtime), presence, e.desc))
  end
  table.insert(lines, "")
  table.insert(lines, "    " .. string.rep("─", 92))
  table.insert(lines, string.format("    total  %s  across  %d items",
    fmt_size(total), #panel.items))
  table.insert(lines, "")
  table.insert(lines, "    [i] inspect    [c] clear    [e] export    [I] import    [r] refresh    [q] close")

  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false

  -- highlights
  for r, line in ipairs(lines) do
    local row = r - 1
    -- digit prefix → accent
    local digit = line:match("^%s+(%d+)%s")
    if digit then
      local col = #line:match("^(%s+)")
      pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, col,
        { end_col = col + #digit, hl_group = "BrandAccent" })
    end
    -- "—" empty markers in muted
    if line:find("—") then
      local s, e = line:find("—")
      while s do
        pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, s - 1,
          { end_col = e, hl_group = "BrandMuted" })
        s, e = line:find("—", e + 1)
      end
    end
    -- present + ok markers in ok-green; encrypted/system in subtext
    for _, tok in ipairs({ "ok", "set" }) do
      local s = line:find("%s" .. tok .. "%s")
      if s then
        pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, s,
          { end_col = s + #tok, hl_group = "BrandOk" })
      end
    end
    for _, tok in ipairs({ "encrypted", "system", "unset" }) do
      local s = line:find("%s" .. tok)
      if s then
        pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, s,
          { end_col = s + #tok, hl_group = "BrandSubtext" })
      end
    end
    -- divider + footer
    if line:find("^%s+─") or line:find("^%s+%[i%]") then
      pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandMuted" })
    end
    -- total line
    if line:find("^%s+total%s+") then
      pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandSubtext" })
    end
  end
end

local function selected()
  local row = vim.api.nvim_win_get_cursor(panel.win)[1]
  -- items start at lines[2] (line index 2 in buf), so idx = row - 1
  return panel.items[row - 1]
end

function M.show()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then close(); return end
  local items_count = #registry()
  local W, H = 96, items_count + 6
  local r = require("user.brand").win({
    title = "user state",
    width = W, height = H,
    anchor = "center",
    close_keys = { "q", "<Esc>" },
    animate = true,
  })
  panel.win, panel.buf = r.win, r.buf
  render()

  local opts = { buffer = panel.buf, silent = true, nowait = true }
  vim.keymap.set("n", "i", function()
    local e = selected(); if e then close(); vim.schedule(function() M.inspect(e.id) end) end
  end, opts)
  vim.keymap.set("n", "c", function()
    local e = selected(); if e then M.clear(e.id); render() end
  end, opts)
  vim.keymap.set("n", "e", function()
    close(); vim.schedule(function() M.export() end)
  end, opts)
  vim.keymap.set("n", "I", function()
    vim.ui.input({ prompt = "import from tarball: ", completion = "file" }, function(p)
      if p and p ~= "" then close(); vim.schedule(function() M.import(vim.fn.expand(p)) end) end
    end)
  end, opts)
  vim.keymap.set("n", "r", render, opts)
end

function M.setup()
  vim.api.nvim_create_user_command("UserState",       M.show,
    { desc = "Inspect all user state files" })
  vim.api.nvim_create_user_command("UserStateClear",  function(a) M.clear(a.args) end,
    { nargs = 1, desc = "Clear a single state file by id",
      complete = function() return vim.tbl_map(function(e) return e.id end, registry()) end })
  vim.api.nvim_create_user_command("UserStateExport", function(a) M.export(a.args ~= "" and a.args or nil) end,
    { nargs = "?", complete = "file", desc = "Export non-sensitive state to a tarball" })
  vim.api.nvim_create_user_command("UserStateImport", function(a) M.import(a.args) end,
    { nargs = 1, complete = "file", desc = "Import state from a tarball (overwrites)" })
end

return M
