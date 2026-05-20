-- Warning lights: a tiny string of LED-like indicators for the statusline.
-- ● green = ok    ● amber = caution    ● red = warning
-- Conditions:
--   MOD = any modified buffer
--   ERR = any LSP error in any buffer
--   JOB = any running user.jobs
--   GIT = git tree dirty (cached 5s)
--   NET = webhook server running
local M = {}

local CACHE = { git_dirty = false, t = 0 }

local function git_dirty()
  local now = vim.uv.now()
  if now - CACHE.t < 5000 then return CACHE.git_dirty end
  local out = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.getcwd()) .. " status --porcelain 2>/dev/null")
  CACHE.git_dirty = #out > 0
  CACHE.t = now
  return CACHE.git_dirty
end

function M.statusline()
  local lights = {}

  -- MOD
  local any_mod = false
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then any_mod = true; break end
  end
  table.insert(lights, any_mod and "%#DiagnosticWarn#●%* MOD" or "%#DiagnosticOk#●%* MOD")

  -- ERR
  local errs = #vim.diagnostic.get(nil, { severity = vim.diagnostic.severity.ERROR })
  table.insert(lights, errs > 0 and ("%#DiagnosticError#●%* ERR " .. errs) or "%#DiagnosticOk#●%* ERR")

  -- JOB
  local jobs_running = 0
  local ok, jobs = pcall(require, "user.jobs")
  if ok then jobs_running = vim.tbl_count(jobs._running or {}) end
  table.insert(lights, jobs_running > 0 and ("%#DiagnosticInfo#●%* JOB " .. jobs_running) or "%#DiagnosticOk#●%* JOB")

  -- GIT
  table.insert(lights, git_dirty() and "%#DiagnosticWarn#●%* GIT" or "%#DiagnosticOk#●%* GIT")

  -- NET (webhook)
  local net_ok = pcall(require, "user.webhook")
  local webhook_up = net_ok and require("user.webhook")._server ~= nil
  table.insert(lights, webhook_up and "%#DiagnosticInfo#●%* NET" or "%#NonText#●%* net")

  return table.concat(lights, " ")
end

function M.setup() end  -- nothing eager; statusline calls into M.statusline()

return M
