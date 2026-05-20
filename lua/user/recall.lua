-- Recall: <leader>z reverses the most recent context shift. Like Ctrl-Z
-- for *navigation* — buffer switches, tab switches, window splits, cwd
-- changes. Stack-based, capped, lossy on overflow (oldest dropped).
--
-- A "context shift" gets recorded when:
--   • the active buffer changes              (BufEnter, different buf)
--   • the active tab changes                 (TabEnter, different tab)
--   • the active window changes              (WinEnter, different win)
--   • the cwd changes                        (DirChanged)
--
-- Each entry stores enough state to restore the previous situation. We
-- coalesce entries that fire in the same tick (so :tabnew doesn't push
-- three frames at once).
local M = {}

local brand = require("user.brand")

local MAX = 50
local _stack    = {}    -- { { kind, ts, from = ..., to = ... }, ... }
local _last_buf = nil
local _last_tab = nil
local _last_win = nil
local _last_cwd = nil
local _restoring = false   -- suppress recording while we restore

local function _push(entry)
  if _restoring then return end
  entry.ts = vim.uv.now()
  -- coalesce: drop the previous entry if it fired within 50ms (same logical action)
  local prev = _stack[#_stack]
  if prev and entry.ts - prev.ts < 50 and prev.kind == entry.kind then
    _stack[#_stack] = entry
    return
  end
  table.insert(_stack, entry)
  while #_stack > MAX do table.remove(_stack, 1) end
end

-- ─── recording hooks ─────────────────────────────────────────────────────
local function _on_buf_enter()
  local buf = vim.api.nvim_get_current_buf()
  if _last_buf and _last_buf ~= buf and vim.api.nvim_buf_is_valid(_last_buf) then
    _push({ kind = "buf", from = _last_buf, to = buf })
  end
  _last_buf = buf
end

local function _on_tab_enter()
  local tab = vim.api.nvim_get_current_tabpage()
  if _last_tab and _last_tab ~= tab and vim.api.nvim_tabpage_is_valid(_last_tab) then
    _push({ kind = "tab", from = _last_tab, to = tab })
  end
  _last_tab = tab
end

local function _on_win_enter()
  local win = vim.api.nvim_get_current_win()
  if _last_win and _last_win ~= win and vim.api.nvim_win_is_valid(_last_win) then
    _push({ kind = "win", from = _last_win, to = win })
  end
  _last_win = win
end

local function _on_dir_changed()
  local cwd = vim.fn.getcwd()
  if _last_cwd and _last_cwd ~= cwd then
    _push({ kind = "cd", from = _last_cwd, to = cwd })
  end
  _last_cwd = cwd
end

-- ─── pop / restore ───────────────────────────────────────────────────────
function M.pop()
  local entry = table.remove(_stack)
  if not entry then
    brand.notify("nothing to recall", nil, { title = "recall" }); return
  end
  _restoring = true
  local ok = pcall(function()
    if entry.kind == "buf" and vim.api.nvim_buf_is_valid(entry.from) then
      vim.api.nvim_set_current_buf(entry.from)
      _last_buf = entry.from
    elseif entry.kind == "tab" and vim.api.nvim_tabpage_is_valid(entry.from) then
      vim.api.nvim_set_current_tabpage(entry.from)
      _last_tab = entry.from
    elseif entry.kind == "win" and vim.api.nvim_win_is_valid(entry.from) then
      vim.api.nvim_set_current_win(entry.from)
      _last_win = entry.from
    elseif entry.kind == "cd" and vim.uv.fs_stat(entry.from) then
      vim.cmd("tcd " .. vim.fn.fnameescape(entry.from))
      _last_cwd = entry.from
    end
  end)
  vim.schedule(function() _restoring = false end)
  if ok then
    brand.notify("↶ " .. entry.kind, nil, { title = "recall" })
  end
end

-- A short string describing what M.pop() would restore — useful in the
-- statusbar so the user can see the affordance before pressing the key.
function M.peek()
  local e = _stack[#_stack]; if not e then return nil end
  if e.kind == "buf" and vim.api.nvim_buf_is_valid(e.from) then
    local n = vim.api.nvim_buf_get_name(e.from)
    return ("↶ " .. (vim.fn.fnamemodify(n, ":t") ~= "" and vim.fn.fnamemodify(n, ":t") or "[no name]"))
  elseif e.kind == "tab" and vim.api.nvim_tabpage_is_valid(e.from) then
    return ("↶ tab " .. vim.api.nvim_tabpage_get_number(e.from))
  elseif e.kind == "win" and vim.api.nvim_win_is_valid(e.from) then
    return "↶ win"
  elseif e.kind == "cd" then
    return "↶ cd " .. vim.fn.fnamemodify(e.from, ":t")
  end
end

function M.clear()
  _stack = {}
  brand.notify("recall stack cleared", nil, { title = "recall" })
end

-- ─── setup ───────────────────────────────────────────────────────────────
function M.setup()
  _last_buf = vim.api.nvim_get_current_buf()
  _last_tab = vim.api.nvim_get_current_tabpage()
  _last_win = vim.api.nvim_get_current_win()
  _last_cwd = vim.fn.getcwd()

  local grp = vim.api.nvim_create_augroup("user_recall", { clear = true })
  vim.api.nvim_create_autocmd("BufEnter",    { group = grp, callback = _on_buf_enter })
  vim.api.nvim_create_autocmd("TabEnter",    { group = grp, callback = _on_tab_enter })
  vim.api.nvim_create_autocmd("WinEnter",    { group = grp, callback = _on_win_enter })
  vim.api.nvim_create_autocmd("DirChanged",  { group = grp, callback = _on_dir_changed })

  vim.api.nvim_create_user_command("Recall",      M.pop,   { desc = "Undo the last context shift" })
  vim.api.nvim_create_user_command("RecallClear", M.clear, { desc = "Forget the recall stack" })
end

return M
