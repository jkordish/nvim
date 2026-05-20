-- Toast: top-right corner stack of small floating messages for events that
-- aren't statusbar-worthy but you still want to see acknowledge.
--
-- Surfaces:
--   save     — "✓ saved · file.lua"
--   format   — "󰉢 formatted · file.lua"
--   task     — "⠹ task: build … running"  /  " task: build · 1.4s"
--   test     — " 12/12 passed · 1.2s"    /  "  3 failed"
--   diag     — "⚠ 2 warnings in file.lua"  (only when severity jumps)
--
-- Toasts stack from top-right downward. Each toast lives ~3.5s, fades over
-- the last 600ms (3-step color shift, same idea as the save_pulse chip).
local M = {}
local brand = require("user.brand")

local DEFAULT_TTL_MS  = 3500
local FADE_MS         = 600
local MARGIN_RIGHT    = 2
local MARGIN_TOP      = 1
local GAP             = 1

-- {win, buf, ttl_until, level, height, on_click}
local _stack = {}

-- ─── highlights ──────────────────────────────────────────────────────────
local function apply_hl()
  local c = brand.c
  local set = vim.api.nvim_set_hl
  set(0, "UserToastBorder",  { fg = c.accent,   bg = "NONE" })
  set(0, "UserToastInfo",    { fg = c.text,     bg = c.surface })
  set(0, "UserToastOk",      { fg = c.bg,       bg = c.green,   bold = true })
  set(0, "UserToastWarn",    { fg = c.bg,       bg = c.yellow,  bold = true })
  set(0, "UserToastErr",     { fg = c.bg,       bg = c.red,     bold = true })
  set(0, "UserToastFade",    { fg = c.muted,    bg = c.surface })
end

-- ─── stack maintenance ───────────────────────────────────────────────────
local function _reflow()
  local row = MARGIN_TOP
  for _, t in ipairs(_stack) do
    if t.win and vim.api.nvim_win_is_valid(t.win) then
      pcall(vim.api.nvim_win_set_config, t.win, {
        relative = "editor",
        row = row,
        col = vim.o.columns - t.width - MARGIN_RIGHT,
      })
      row = row + t.height + GAP
    end
  end
end

local function _close(toast)
  if toast.win and vim.api.nvim_win_is_valid(toast.win) then
    pcall(vim.api.nvim_win_close, toast.win, true)
  end
  if toast.timer and not toast.timer:is_closing() then
    pcall(function() toast.timer:stop() end)
    pcall(function() toast.timer:close() end)
  end
  for i, t in ipairs(_stack) do
    if t == toast then table.remove(_stack, i); break end
  end
  _reflow()
end

local LEVEL_HL = { info = "UserToastInfo", ok = "UserToastOk",
                   warn = "UserToastWarn", err = "UserToastErr" }

-- ─── public ──────────────────────────────────────────────────────────────
-- M.show("text", { level = "ok"|"warn"|"err"|"info", ttl_ms = 4000, on_click = fn })
function M.show(text, opts)
  opts = opts or {}
  apply_hl()
  local level   = opts.level or "info"
  local ttl     = opts.ttl_ms or DEFAULT_TTL_MS
  local content = " " .. text .. " "
  local width   = math.max(20, vim.api.nvim_strwidth(content) + 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { content })
  -- color the line via extmark using the level-mapped hl group
  local ns = vim.api.nvim_create_namespace("user_toast")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0,
    { end_line = 1, hl_group = LEVEL_HL[level] or "UserToastInfo" })

  local row = MARGIN_TOP
  for _, t in ipairs(_stack) do row = row + t.height + GAP end
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", style = "minimal",
    border = "rounded",
    row = row, col = vim.o.columns - width - MARGIN_RIGHT,
    width = width, height = 1,
    focusable = false, zindex = 200, noautocmd = true,
  })
  pcall(function()
    vim.wo[win].winhighlight = "FloatBorder:UserToastBorder,Normal:" .. (LEVEL_HL[level] or "UserToastInfo")
    vim.wo[win].winblend = 0
  end)

  local toast = {
    buf = buf, win = win, width = width, height = 1,
    on_click = opts.on_click,
  }
  table.insert(_stack, toast)
  _reflow()

  -- click via simple buffer keymap if focusable were on, but we use 'no
  -- focusable'. So instead expose dismiss via timer + optional explicit M.click()

  -- Fade phase: at FADE_MS remaining, swap to a muted hl
  toast.timer = vim.uv.new_timer()
  toast.timer:start(ttl - FADE_MS, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      vim.api.nvim_buf_set_extmark(buf, ns, 0, 0,
        { end_line = 1, hl_group = "UserToastFade" })
    end
    -- second stage: actually close
    local dismiss = vim.uv.new_timer()
    dismiss:start(FADE_MS, 0, vim.schedule_wrap(function()
      pcall(function() dismiss:stop(); dismiss:close() end)
      _close(toast)
    end))
  end))
  return toast
end

function M.ok(text, opts)   return M.show(text, vim.tbl_extend("force", { level = "ok"   }, opts or {})) end
function M.warn(text, opts) return M.show(text, vim.tbl_extend("force", { level = "warn" }, opts or {})) end
function M.err(text, opts)  return M.show(text, vim.tbl_extend("force", { level = "err"  }, opts or {})) end
function M.info(text, opts) return M.show(text, vim.tbl_extend("force", { level = "info" }, opts or {})) end

function M.clear()
  for i = #_stack, 1, -1 do _close(_stack[i]) end
end

-- ─── auto-hooks (save, format, test, task) ───────────────────────────────
function M.setup()
  apply_hl()
  local grp = vim.api.nvim_create_augroup("user_toast", { clear = true })

  -- Save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = grp,
    callback = function(ev)
      local name = vim.fn.fnamemodify(ev.file or "", ":t")
      if name == "" then return end
      M.ok(" saved · " .. name)
    end,
  })

  -- LSP formatting done — there's no native event; hook formatexpr-like flow
  -- by listening for LspProgress done with kind = "format". This is best-effort
  -- and may not fire for synchronous formatters; in that case the user just
  -- sees the save toast above, which is fine.

  -- Overseer task completion
  pcall(function()
    local ov = require("overseer")
    if ov and ov.add_template then  -- presence check only
      vim.api.nvim_create_autocmd("User", {
        group = grp,
        pattern = "OverseerTaskComplete",
        callback = function(ev)
          local task = ev.data and ev.data.task
          if not task then return end
          if task.status == "FAILURE" then
            M.err(" task · " .. task.name)
          elseif task.status == "SUCCESS" then
            M.ok(" task · " .. task.name)
          end
        end,
      })
    end
  end)

  -- Neotest results
  pcall(function()
    if pcall(require, "neotest") then
      vim.api.nvim_create_autocmd("User", {
        group = grp,
        pattern = "NeotestSuiteFinished",
        callback = function(ev)
          local data = ev.data or {}
          if data.failed and data.failed > 0 then
            M.err(("  %d failed"):format(data.failed))
          elseif data.passed and data.passed > 0 then
            M.ok(("  %d/%d passed"):format(data.passed, (data.passed + (data.skipped or 0))))
          end
        end,
      })
    end
  end)

  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = apply_hl })
  vim.api.nvim_create_autocmd("VimResized",  { group = grp, callback = _reflow })

  vim.api.nvim_create_user_command("Toast", function(a) M.show(a.args) end,
    { nargs = "+", desc = "Show a toast (for testing / scripting)" })
  vim.api.nvim_create_user_command("ToastClear", M.clear, { desc = "Dismiss all toasts" })
end

return M
