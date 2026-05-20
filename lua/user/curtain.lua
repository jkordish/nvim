-- Curtain: subtle open/close animation for floating windows. The window
-- starts at a small height + width pinned to its final center, then
-- expands over ~140ms in 7 steps with quadratic easing. Closing reverses.
-- This is the single source of motion that makes the UI feel "alive".
local M = {}

local DURATION = 140
local STEPS    = 7

local function ease_out_quad(t) return 1 - (1 - t) * (1 - t) end

-- Animate window open. Returns the window id; safe even if interrupted.
function M.open(buf, target_opts)
  -- Start with a small clipping size; animate to target. Always min 3x1.
  local target_w = target_opts.width
  local target_h = target_opts.height
  local cx = target_opts.col + math.floor(target_w / 2)
  local cy = target_opts.row + math.floor(target_h / 2)

  local start_w = math.max(3, math.floor(target_w * 0.5))
  local start_h = math.max(1, math.floor(target_h * 0.4))

  local opts = vim.deepcopy(target_opts)
  opts.width  = start_w
  opts.height = start_h
  opts.row    = cy - math.floor(start_h / 2)
  opts.col    = cx - math.floor(start_w / 2)
  local win = vim.api.nvim_open_win(buf, target_opts.focusable ~= false, opts)

  local step = 0
  local timer = vim.uv.new_timer()
  local interval = math.floor(DURATION / STEPS)
  -- Single guarded close: the timer is repeating and `schedule_wrap` defers
  -- callbacks onto the main loop, so several callbacks can already be queued
  -- by the time we decide to stop. Without the guard, the queued callbacks
  -- re-enter and call close() on an already-closing handle ("handle is
  -- already closing" — spammed once per remaining queued tick).
  local function stop_timer()
    if timer and not timer:is_closing() then
      timer:stop(); timer:close()
    end
    timer = nil
  end
  timer:start(interval, interval, vim.schedule_wrap(function()
    if not timer then return end  -- already torn down by a prior tick
    if not vim.api.nvim_win_is_valid(win) then stop_timer(); return end
    step = step + 1
    local t = ease_out_quad(step / STEPS)
    local w = math.floor(start_w + (target_w - start_w) * t)
    local h = math.max(1, math.floor(start_h + (target_h - start_h) * t))
    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = cy - math.floor(h / 2),
      col = cx - math.floor(w / 2),
      width = w, height = h,
    })
    if step >= STEPS then
      -- snap to exact target
      pcall(vim.api.nvim_win_set_config, win, {
        relative = "editor",
        row = target_opts.row, col = target_opts.col,
        width = target_w, height = target_h,
      })
      stop_timer()
    end
  end))

  return win
end

-- Animate window close, then destroy.
function M.close(win)
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  local cfg = vim.api.nvim_win_get_config(win)
  local cur_w, cur_h = cfg.width, cfg.height
  local cur_r, cur_c = cfg.row, cfg.col
  local cx = cur_c + math.floor(cur_w / 2)
  local cy = cur_r + math.floor(cur_h / 2)
  local end_w, end_h = math.max(3, math.floor(cur_w * 0.4)), 1

  local step = 0
  local timer = vim.uv.new_timer()
  local interval = math.floor(DURATION / STEPS)
  local function stop_timer()
    if timer and not timer:is_closing() then
      timer:stop(); timer:close()
    end
    timer = nil
  end
  timer:start(interval, interval, vim.schedule_wrap(function()
    if not timer then return end
    if not vim.api.nvim_win_is_valid(win) then stop_timer(); return end
    step = step + 1
    local t = ease_out_quad(step / STEPS)
    local w = math.floor(cur_w + (end_w - cur_w) * t)
    local h = math.max(1, math.floor(cur_h + (end_h - cur_h) * t))
    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = cy - math.floor(h / 2),
      col = cx - math.floor(w / 2),
      width = w, height = h,
    })
    if step >= STEPS then
      pcall(vim.api.nvim_win_close, win, true)
      stop_timer()
    end
  end))
end

function M.setup() end  -- no autocmds; pure helper
return M
