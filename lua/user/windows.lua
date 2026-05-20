-- Window utilities: jump-pick overlay, maximize/zen toggle, named layouts.
-- The pick overlay wraps nvim-window-picker (already installed). Layouts
-- are scoped :mksession files, registered with user.state so they show up
-- in :UserState alongside everything else.
local M = {}

local brand = require("user.brand")

-- ─── window picker ───────────────────────────────────────────────────────
-- Press <leader>ww. nvim-window-picker overlays a big letter in the middle
-- of each window; type the letter to jump there. Falls back to a numbered
-- vim.ui.select if the plugin isn't loaded.
function M.pick()
  local ok, picker = pcall(require, "window-picker")
  if ok then
    local win = picker.pick_window()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
    return
  end
  -- fallback
  local wins = vim.api.nvim_tabpage_list_wins(0)
  if #wins <= 1 then return end
  local items = {}
  for i, w in ipairs(wins) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
    table.insert(items, ("[%d] %s"):format(i, vim.fn.fnamemodify(name, ":t") ~= "" and vim.fn.fnamemodify(name, ":t") or "[no name]"))
  end
  vim.ui.select(items, { prompt = "pick window: " }, function(_, idx)
    if idx and wins[idx] then vim.api.nvim_set_current_win(wins[idx]) end
  end)
end

-- ─── maximize / zen toggle ───────────────────────────────────────────────
-- Uses `:tab split` so vim does the layout preservation for us — toggle off
-- by closing the maximize tab, original split arrangement intact. Tracks
-- the source tab so we can return to it directly instead of `:tabclose`'s
-- default-rightward jump.
M._max = nil   -- { tab = <maximize tab>, source_tab = <where we came from> }

function M.toggle_maximize()
  local cur = vim.api.nvim_get_current_tabpage()
  if M._max and cur == M._max.tab then
    local src = M._max.source_tab
    M._max = nil
    pcall(vim.cmd, "tabclose")
    if src and vim.api.nvim_tabpage_is_valid(src) then
      pcall(vim.api.nvim_set_current_tabpage, src)
    end
    return
  end
  -- enter maximize: open current buffer in a new tab
  local source = cur
  vim.cmd("tab split")
  M._max = { tab = vim.api.nvim_get_current_tabpage(), source_tab = source }
  pcall(vim.cmd, "TabName max")
end

-- ─── named layouts (per-name :mksession files) ───────────────────────────
-- Each layout is a vim session restricted to window/split/cwd state. Stored
-- under stdpath('state')/window_layouts/<name>.vim. Listed via :LayoutList,
-- restored via :LayoutLoad, removed via :LayoutDelete.
local LAYOUT_DIR = vim.fn.stdpath("state") .. "/window_layouts"
local LAYOUT_SO  = "winsize,resize,winpos,blank,buffers,curdir,folds,help,tabpages,terminal"

local function layout_path(name) return LAYOUT_DIR .. "/" .. name .. ".vim" end

function M.list_layouts()
  vim.fn.mkdir(LAYOUT_DIR, "p")
  local files = vim.fn.glob(LAYOUT_DIR .. "/*.vim", false, true)
  local out = {}
  for _, f in ipairs(files) do
    table.insert(out, vim.fn.fnamemodify(f, ":t:r"))
  end
  table.sort(out)
  return out
end

function M.save_layout(name)
  if not name or name == "" then
    vim.ui.input({ prompt = "save layout as: " }, function(v)
      if v and v ~= "" then M.save_layout(v) end
    end)
    return
  end
  vim.fn.mkdir(LAYOUT_DIR, "p")
  local saved = vim.o.sessionoptions
  vim.o.sessionoptions = LAYOUT_SO
  local ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(layout_path(name)))
  vim.o.sessionoptions = saved
  if ok then
    brand.notify(("saved layout · %s"):format(name), nil, { title = "windows" })
  else
    brand.notify(("save failed: %s"):format(err), vim.log.levels.ERROR, { title = "windows" })
  end
end

function M.load_layout(name)
  if not name or name == "" then
    local items = M.list_layouts()
    if #items == 0 then
      brand.notify("no saved layouts yet", nil, { title = "windows" }); return
    end
    vim.ui.select(items, { prompt = "load layout: " }, function(choice)
      if choice then M.load_layout(choice) end
    end)
    return
  end
  local p = layout_path(name)
  if vim.fn.filereadable(p) ~= 1 then
    brand.notify(("no layout: %s"):format(name), vim.log.levels.WARN, { title = "windows" })
    return
  end
  local ok, err = pcall(vim.cmd, "source " .. vim.fn.fnameescape(p))
  if ok then
    brand.notify(("loaded layout · %s"):format(name), nil, { title = "windows" })
  else
    brand.notify(("load failed: %s"):format(err), vim.log.levels.ERROR, { title = "windows" })
  end
end

function M.delete_layout(name)
  if not name or name == "" then
    local items = M.list_layouts()
    if #items == 0 then return end
    vim.ui.select(items, { prompt = "delete layout: " }, function(choice)
      if choice then M.delete_layout(choice) end
    end)
    return
  end
  local p = layout_path(name)
  if vim.uv.fs_unlink(p) then
    brand.notify(("deleted · %s"):format(name), nil, { title = "windows" })
  end
end

function M.show_layouts()
  local items = M.list_layouts()
  if #items == 0 then
    brand.notify("no saved layouts · :LayoutSave <name> first", nil, { title = "windows" })
    return
  end
  vim.ui.select(items, { prompt = "layouts: " }, function(choice)
    if choice then M.load_layout(choice) end
  end)
end

-- ─── setup ───────────────────────────────────────────────────────────────
function M.setup()
  vim.fn.mkdir(LAYOUT_DIR, "p")

  vim.api.nvim_create_user_command("WinPick", M.pick,
    { desc = "Jump to a window via picker overlay" })
  vim.api.nvim_create_user_command("WinMax", M.toggle_maximize,
    { desc = "Toggle maximize: open current buffer in a fresh tab + back" })

  vim.api.nvim_create_user_command("LayoutSave",
    function(a) M.save_layout(a.args) end,
    { nargs = "?", desc = "Save the current window/tab layout under a name" })
  vim.api.nvim_create_user_command("LayoutLoad",
    function(a) M.load_layout(a.args) end,
    { nargs = "?", complete = function() return M.list_layouts() end,
      desc = "Load a saved layout (no arg = pick)" })
  vim.api.nvim_create_user_command("LayoutDelete",
    function(a) M.delete_layout(a.args) end,
    { nargs = "?", complete = function() return M.list_layouts() end,
      desc = "Delete a saved layout" })
  vim.api.nvim_create_user_command("LayoutList", M.show_layouts,
    { desc = "Pick from saved layouts" })
end

return M
