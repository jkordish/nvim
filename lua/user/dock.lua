-- Bottom dock — a persistent panel area with named tabs hosting terminals,
-- output streams, notification history, and a tasks list. One key toggles
-- it. Tabs are click-switchable. Buffers persist across hide/show so a
-- running shell or log keeps streaming when the dock is collapsed.
--
-- Design constraints (the dock is real estate; it has to earn its space):
--   • opens only when you ask for it (no autopilot)
--   • one key toggles visible/hidden
--   • when visible-but-unfocused, the toggle key focuses instead of closing
--   • buffers backing each tab are kept alive (bufhidden = "hide") so
--     state survives invisibly between toggles
local M = {}

local brand = require("user.brand")

-- ─── tab registry ────────────────────────────────────────────────────────
-- Each tab is { id, label, kind, buf?, cmd? }. `kind` decides how the
-- backing buffer is created on demand: terminal=termopen, scratch=plain
-- nofile, notif=scratch populated from snacks history, tasks=overseer view.
local TABS = {
  { id = "term1",  label = " term 1",        kind = "terminal" },
  { id = "term2",  label = " term 2",        kind = "terminal" },
  { id = "term3",  label = " term 3",        kind = "terminal" },
  { id = "output", label = " output",        kind = "scratch" },
  { id = "tasks",  label = " tasks",         kind = "tasks" },
  { id = "notif",  label = "󰂞 notifications", kind = "notif" },
}
M._tabs    = TABS
M._current = 1
M._win     = nil
M._height  = 15

-- ─── helpers ─────────────────────────────────────────────────────────────
local function _is_open()
  return M._win and vim.api.nvim_win_is_valid(M._win)
end

local function _find_tab(id_or_idx)
  if type(id_or_idx) == "number" then return M._tabs[id_or_idx], id_or_idx end
  for i, t in ipairs(M._tabs) do
    if t.id == id_or_idx then return t, i end
  end
end

-- ─── click dispatcher ────────────────────────────────────────────────────
M._click_handlers = {}
local _next_click_id = 0
function M._on_click(id) local fn = M._click_handlers[id]; if fn then pcall(fn) end end
_G._user_dock_on_click = M._on_click

local function register_click(fn)
  _next_click_id = _next_click_id + 1
  M._click_handlers[_next_click_id] = fn
  return _next_click_id
end

-- ─── highlights + tab strip render (winbar) ──────────────────────────────
local function apply_hl()
  local c = brand.c
  local set = vim.api.nvim_set_hl
  set(0, "UserDockActive",   { fg = c.bg,    bg = c.accent,  bold = true })
  set(0, "UserDockInactive", { fg = c.text,  bg = c.surface })
  set(0, "UserDockFill",     { fg = c.muted, bg = "NONE" })
end

function M.render_winbar()
  apply_hl()
  M._click_handlers = {}; _next_click_id = 0
  local out = { " " }
  for i, tab in ipairs(M._tabs) do
    local hl = (i == M._current) and "UserDockActive" or "UserDockInactive"
    local cid = register_click(function() M.switch(i) end)
    table.insert(out, ("%%%d@v:lua._user_dock_on_click@%%#%s# %d · %s %%X")
      :format(cid, hl, i, tab.label))
    table.insert(out, "%#UserDockFill# ")
  end
  table.insert(out, "%#UserDockFill#%X")
  return table.concat(out)
end

-- ─── buffer construction (lazy, kind-specific) ──────────────────────────
local function _populate_notif(buf)
  local lines = {}
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.notifier and snacks.notifier.get_history then
    for _, n in ipairs(snacks.notifier.get_history() or {}) do
      local stamp = os.date("%H:%M:%S", n.added or os.time())
      table.insert(lines, ("[%s] %-5s %s"):format(stamp, n.level or "info", (n.msg or ""):gsub("\n", " ")))
    end
  end
  if #lines == 0 then
    lines = { "", "  (no notifications yet)" }
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function _populate_tasks(buf)
  local lines = { "" }
  local ok, overseer = pcall(require, "overseer")
  if ok then
    local tasks = overseer.list_tasks({})
    if #tasks == 0 then
      table.insert(lines, "  (no tasks · :Task <name> to run, :OverseerRun to pick a template)")
    else
      for _, t in ipairs(tasks) do
        table.insert(lines, ("  %-10s  %s"):format(t.status, t.name))
      end
    end
  else
    table.insert(lines, "  (overseer not loaded — install/restart, then :OverseerLoadBundle)")
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function _ensure_buf(tab)
  if tab.buf and vim.api.nvim_buf_is_valid(tab.buf) then
    -- refresh dynamic tabs every show
    if tab.kind == "notif"  then _populate_notif(tab.buf) end
    if tab.kind == "tasks"  then _populate_tasks(tab.buf) end
    return tab.buf
  end
  if tab.kind == "terminal" then
    -- termopen requires the buffer be the active buffer in some window.
    local buf = vim.api.nvim_create_buf(false, false)
    vim.bo[buf].bufhidden = "hide"
    local saved = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M._win, buf)
    vim.api.nvim_set_current_win(M._win)
    pcall(vim.fn.termopen, tab.cmd or vim.o.shell or "/bin/sh")
    vim.api.nvim_set_current_win(saved)
    tab.buf = buf
    return buf
  end
  -- scratch / notif / tasks
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile  = false
  if tab.kind == "scratch" then
    vim.bo[buf].filetype = "log"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  (output appears here as `M.output_append(line)` is called)" })
    vim.bo[buf].modifiable = false
  elseif tab.kind == "notif" then
    vim.bo[buf].filetype = "log"
    _populate_notif(buf)
  elseif tab.kind == "tasks" then
    vim.bo[buf].filetype = "log"
    _populate_tasks(buf)
  end
  tab.buf = buf
  return buf
end

-- ─── window management ───────────────────────────────────────────────────
local function _open_window()
  if _is_open() then return end
  vim.cmd(("silent! botright %d split"):format(M._height))
  M._win = vim.api.nvim_get_current_win()
  vim.wo[M._win].winbar = "%!v:lua.require'user.dock'.render_winbar()"
  vim.wo[M._win].number          = false
  vim.wo[M._win].relativenumber  = false
  vim.wo[M._win].signcolumn      = "no"
  vim.wo[M._win].cursorline      = false
  vim.wo[M._win].winfixheight    = true
end

local function _show(tab_idx)
  if not _is_open() then _open_window() end
  M._current = tab_idx
  local tab = M._tabs[tab_idx]
  local buf = _ensure_buf(tab)
  vim.api.nvim_win_set_buf(M._win, buf)
  vim.api.nvim_set_current_win(M._win)
  if tab.kind == "terminal" then
    vim.cmd("startinsert")
  end
  -- attach buffer-local keymaps once per buf
  if not vim.b[buf]._dock_mapped then
    local opts = { buffer = buf, silent = true, nowait = true }
    for i = 1, #M._tabs do
      vim.keymap.set("n", tostring(i), function() M.switch(i) end, opts)
    end
    vim.keymap.set("n", "]t", function() M.next() end, opts)
    vim.keymap.set("n", "[t", function() M.prev() end, opts)
    vim.keymap.set("n", "q",  function() M.close() end, opts)
    vim.b[buf]._dock_mapped = true
  end
end

function M.open(tab_id)
  local _, idx = _find_tab(tab_id or M._current)
  _show(idx or 1)
end

function M.close()
  if not _is_open() then return end
  pcall(vim.api.nvim_win_close, M._win, true)
  M._win = nil
end

function M.toggle()
  if _is_open() then
    if vim.api.nvim_get_current_win() == M._win then
      M.close()
    else
      vim.api.nvim_set_current_win(M._win)
      if M._tabs[M._current].kind == "terminal" then vim.cmd("startinsert") end
    end
  else
    M.open()
  end
end

function M.switch(idx)
  if idx < 1 or idx > #M._tabs then return end
  _show(idx)
end

function M.next() M.switch((M._current % #M._tabs) + 1) end
function M.prev() M.switch((M._current - 2) % #M._tabs + 1) end

-- ─── output append (called from jobs / overseer hooks) ───────────────────
function M.output_append(line)
  local tab = _find_tab("output"); if not tab then return end
  local buf = _ensure_buf(tab)
  vim.bo[buf].modifiable = true
  local n = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, n, n, false, vim.split(tostring(line), "\n"))
  vim.bo[buf].modifiable = false
end

-- ─── setup ───────────────────────────────────────────────────────────────
function M.setup()
  vim.api.nvim_create_user_command("Dock", function(a)
    local x = a.args
    if x == "" or x == "toggle" then M.toggle()
    elseif x == "open"  then M.open()
    elseif x == "close" then M.close()
    elseif x == "next"  then M.next()
    elseif x == "prev"  then M.prev()
    else M.open(x) end
  end, {
    nargs = "?",
    complete = function()
      local out = { "open", "close", "toggle", "next", "prev" }
      for _, t in ipairs(TABS) do table.insert(out, t.id) end
      return out
    end,
    desc = "Bottom dock control · :Dock [open|close|toggle|next|prev|<tab-id>]",
  })
end

return M
