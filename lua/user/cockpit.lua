-- Cockpit: toggle Mission Control HUD. Lays out:
--   ┌──────────┬──────────────────────────┬──────────┐
--   │ symtree  │       main editor        │ trouble  │
--   │  (L)     │                          │   (R)    │
--   ├──────────┴──────────────────────────┴──────────┤
--   │                terminal (bottom)               │
--   └────────────────────────────────────────────────┘
-- Plus floating compass (bottom-right) and radar (top-right).
local M = {}
local state = { active = false, main_win = nil }

local function pcall_step(name, fn)
  local ok, err = pcall(fn)
  if not ok then vim.notify("cockpit: " .. name .. " failed → " .. tostring(err), vim.log.levels.WARN) end
  return ok
end

local function focus(win)
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_set_current_win, win)
  end
end

function M.engage()
  if state.active then vim.notify("Cockpit already engaged"); return end

  -- 0. Remember the window we were in
  state.main_win = vim.api.nvim_get_current_win()

  -- 1. Bottom: ToggleTerm horizontal. Returns to previous window after open.
  pcall_step("terminal", function()
    vim.cmd("ToggleTerm direction=horizontal size=12")
    focus(state.main_win)
  end)

  -- 2. Right: Trouble diagnostics
  pcall_step("trouble", function()
    vim.cmd("Trouble diagnostics open focus=false win.position=right win.size=0.25")
    focus(state.main_win)
  end)

  -- 3. Left: SymTree (LSP outline)
  pcall_step("symtree", function()
    require("user.symtree").open()
    focus(state.main_win)
  end)

  -- 4. Floating: compass (always-on bottom-right)
  pcall_step("compass", function() require("user.compass").open() end)

  -- 5. Floating: radar (always-on top-right)
  pcall_step("radar", function() require("user.radar").open() end)

  -- 6. Final: equalize splits, restore focus to main editor window
  pcall_step("balance", function()
    vim.cmd("wincmd =")
    focus(state.main_win)
  end)

  state.active = true
  vim.notify("✈  COCKPIT ENGAGED  ·  :Disengage or :Eject to clear")
end

function M.disengage()
  if not state.active then vim.notify("Cockpit not active"); return end

  -- Floats first (no focus issues)
  pcall(function() require("user.compass").close() end)
  pcall(function() require("user.radar").close() end)
  -- Side panels
  pcall(function() require("user.symtree").close() end)
  pcall(vim.cmd, "Trouble diagnostics close")
  -- Terminal (toggleterm-aware: only close if visible)
  pcall(function()
    local terms = require("toggleterm.terminal").get_all()
    for _, t in pairs(terms) do if t:is_open() then t:close() end end
  end)
  -- Collapse remaining splits to just the main
  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    focus(state.main_win)
  end
  pcall(vim.cmd, "only")

  state.active = false
  state.main_win = nil
  vim.notify("Cockpit disengaged")
end

function M.toggle()
  if state.active then M.disengage() else M.engage() end
end

function M.status() return state.active end

function M.setup()
  vim.api.nvim_create_user_command("Cockpit",   M.toggle,    { desc = "Toggle Mission Control HUD" })
  vim.api.nvim_create_user_command("Engage",    M.engage,    { desc = "Engage cockpit HUD" })
  vim.api.nvim_create_user_command("Disengage", M.disengage, { desc = "Disengage cockpit HUD" })
end

return M
