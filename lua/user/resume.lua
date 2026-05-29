-- Resume: capture task intent per project; surface a Resume Brief with
-- evidence ("what changed while you were away") on return. Conservative
-- switch detection — zero prompts during a steady-state focused hour.
-- Inspired by vscode-tacos; cited principle: Calm Tech (Weiser, 1995).
local M = {}

-- ─── config (defaults; overridden by setup{} merge) ───────────────────────
M.opts = {
  idle_capture_ms      = 15 * 60 * 1000,
  idle_hint_ms         =  5 * 60 * 1000,
  hint_dwell_ms        = 10 * 1000,
  hint_rate_limit_ms   =  5 * 60 * 1000,
  hint_enabled         = true,
  branch_change_prompt = true,
  auto_resume_buffers  = true,
  confirm_overwrite    = true,
  excluded_filetypes   = { "neo-tree", "lazy", "mason", "qf", "help", "TelescopePrompt" },
  excluded_paths       = { vim.fn.stdpath("config") },
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  -- TODO(task-2): _load()
  -- TODO(task-7+): _autocmds()
end

-- Public API (stubs; filled in later tasks)
function M.capture()  vim.notify("resume: capture (not yet implemented)", vim.log.levels.INFO) end
function M.brief()    vim.notify("resume: brief (not yet implemented)",   vim.log.levels.INFO) end
function M.resolve()  vim.notify("resume: resolve (not yet implemented)", vim.log.levels.INFO) end
function M.list()     vim.notify("resume: list (not yet implemented)",    vim.log.levels.INFO) end

return M
