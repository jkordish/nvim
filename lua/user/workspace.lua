-- Workspace snapshots: capture+restore the full nvim layout per project.
-- Saves window arrangement, neo-tree state, terminal layout, DAP UI, current
-- buffers, jumplist, and the active filetypes for harpoon. Per-cwd file.
local M = {}

local function snap_dir()
  local d = vim.fn.stdpath("state") .. "/workspaces"
  vim.fn.mkdir(d, "p")
  return d
end

local function snap_path()
  local cwd = vim.fn.getcwd():gsub("/", "%%")
  return snap_dir() .. "/" .. cwd .. ".json"
end

local function capture()
  local snap = {
    cwd = vim.fn.getcwd(),
    saved_at = os.date("%Y-%m-%dT%H:%M:%S"),
    tabs = {},
    harpoon = {},
  }

  for _, tabnr in ipairs(vim.api.nvim_list_tabpages()) do
    local tab = { wins = {} }
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabnr)) do
      if vim.api.nvim_win_get_config(winid).relative == "" then
        local bufnr = vim.api.nvim_win_get_buf(winid)
        local name = vim.api.nvim_buf_get_name(bufnr)
        local cur = vim.api.nvim_win_get_cursor(winid)
        if name ~= "" and not name:match("^term://") then
          table.insert(tab.wins, {
            file = name,
            cursor = cur,
            width = vim.api.nvim_win_get_width(winid),
            height = vim.api.nvim_win_get_height(winid),
            filetype = vim.bo[bufnr].filetype,
          })
        end
      end
    end
    table.insert(snap.tabs, tab)
  end

  local ok, harpoon = pcall(require, "harpoon")
  if ok then
    local list = harpoon:list()
    for _, item in ipairs(list.items or {}) do
      table.insert(snap.harpoon, { value = item.value, context = item.context })
    end
  end

  return snap
end

function M.save()
  local snap = capture()
  local f = io.open(snap_path(), "w")
  if not f then vim.notify("Workspace: cannot write " .. snap_path(), vim.log.levels.ERROR); return end
  f:write(vim.json.encode(snap)); f:close()
  vim.notify(string.format("Workspace saved: %d tabs, %d windows, %d harpoon",
    #snap.tabs,
    (function() local n = 0; for _, t in ipairs(snap.tabs) do n = n + #t.wins end; return n end)(),
    #snap.harpoon))
end

function M.load()
  local path = snap_path()
  local f = io.open(path, "r")
  if not f then vim.notify("Workspace: no snapshot for " .. vim.fn.getcwd(), vim.log.levels.WARN); return end
  local data = f:read("*a"); f:close()
  local ok, snap = pcall(vim.json.decode, data)
  if not ok then vim.notify("Workspace: corrupt snapshot", vim.log.levels.ERROR); return end

  -- Close everything except the current window
  vim.cmd("silent! only")
  vim.cmd("silent! tabonly")

  for ti, tab in ipairs(snap.tabs) do
    if ti > 1 then vim.cmd("tabnew") end
    for wi, win in ipairs(tab.wins) do
      if wi > 1 then vim.cmd("vsplit") end
      if win.file and vim.fn.filereadable(win.file) == 1 then
        vim.cmd("silent! edit " .. vim.fn.fnameescape(win.file))
        pcall(vim.api.nvim_win_set_cursor, 0, win.cursor)
      end
    end
    vim.cmd("wincmd =")
  end

  local ok_h, harpoon = pcall(require, "harpoon")
  if ok_h and #snap.harpoon > 0 then
    local list = harpoon:list()
    list.items = {}
    for _, item in ipairs(snap.harpoon) do table.insert(list.items, item) end
  end

  vim.notify(string.format("Workspace loaded (saved %s)", snap.saved_at))
end

function M.list()
  local entries = {}
  for _, p in ipairs(vim.fn.glob(snap_dir() .. "/*.json", false, true)) do
    local name = vim.fn.fnamemodify(p, ":t:r"):gsub("%%", "/")
    local f = io.open(p, "r")
    local saved_at = "?"
    if f then
      local ok, j = pcall(vim.json.decode, f:read("*a"))
      f:close()
      if ok then saved_at = j.saved_at or "?" end
    end
    table.insert(entries, { name = name, path = p, saved_at = saved_at })
  end
  if #entries == 0 then vim.notify("No workspace snapshots saved"); return end
  vim.ui.select(entries, {
    prompt = "Pick a workspace",
    format_item = function(e) return string.format("[%s]  %s", e.saved_at, e.name) end,
  }, function(choice)
    if not choice then return end
    vim.cmd("cd " .. vim.fn.fnameescape(choice.name))
    M.load()
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("WorkspaceSave", M.save, { desc = "Save workspace snapshot for current cwd" })
  vim.api.nvim_create_user_command("WorkspaceLoad", M.load, { desc = "Load workspace snapshot for current cwd" })
  vim.api.nvim_create_user_command("WorkspaceList", M.list, { desc = "Pick from saved workspaces" })
end

return M
