-- Eject: emergency panic button. Closes all floating windows, kills running
-- jobs, stops the webhook server, exits all DAP/REPL/terminal sessions,
-- collapses splits to one. Single keystroke to return to a clean cockpit.
local M = {}

local function close_floats()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(w)
    if cfg.relative and cfg.relative ~= "" then
      pcall(vim.api.nvim_win_close, w, true)
      n = n + 1
    end
  end
  return n
end

local function kill_jobs()
  local ok, jobs = pcall(require, "user.jobs")
  if not ok then return 0 end
  local n = 0
  for id, _ in pairs(jobs._running or {}) do
    jobs.cancel(id); n = n + 1
  end
  return n
end

local function stop_webhook()
  local ok, w = pcall(require, "user.webhook")
  if ok and w._server then w.stop(); return true end
  return false
end

local function close_dap()
  local ok, dap = pcall(require, "dap"); if not ok then return end
  pcall(function() dap.terminate(); dap.disconnect({}, function() end) end)
  local ok2, dapui = pcall(require, "dapui"); if ok2 then pcall(dapui.close) end
end

function M.go()
  local floats = close_floats()
  local jobs = kill_jobs()
  local web = stop_webhook()
  close_dap()
  -- Close any toggleterms
  pcall(function() require("toggleterm").toggle(0) end)
  -- Clear search highlight
  vim.cmd("nohlsearch")
  -- Collapse splits but keep current
  pcall(vim.cmd, "only")
  vim.notify(string.format("EJECTED.  %d floats · %d jobs killed · webhook %s",
    floats, jobs, web and "stopped" or "(idle)"), vim.log.levels.WARN)
end

function M.setup()
  vim.api.nvim_create_user_command("Eject", M.go, { desc = "Panic: close floats, kill jobs, reset" })
end

return M
