-- Welcome: a one-time ritual on first launch. A brief gradient sweep, a
-- tagline, and the single key the user needs to know (<F1>). After it
-- runs, a marker file is written so it never fires again unless the user
-- runs :Welcome manually.
local M = {}

local MARKER = vim.fn.stdpath("state") .. "/.welcomed"
local NS = vim.api.nvim_create_namespace("user_welcome")

local function gradient_palette(n)
  -- Smooth lavender → blue → teal gradient for the sweep.
  local stops = { { 0xcb, 0xa6, 0xf7 }, { 0x89, 0xb4, 0xfa }, { 0x94, 0xe2, 0xd5 } }
  local out = {}
  for i = 1, n do
    local p = (i - 1) / (n - 1) * (#stops - 1)
    local a, b = stops[math.floor(p) + 1], stops[math.min(#stops, math.floor(p) + 2)]
    local f = p - math.floor(p)
    local r = math.floor(a[1] + (b[1] - a[1]) * f)
    local g = math.floor(a[2] + (b[2] - a[2]) * f)
    local bl = math.floor(a[3] + (b[3] - a[3]) * f)
    table.insert(out, string.format("#%02x%02x%02x", r, g, bl))
  end
  return out
end

local function hl_for(hex)
  local name = "Welcome_" .. hex:sub(2)
  vim.api.nvim_set_hl(0, name, { fg = hex, bold = true })
  return name
end

function M.run(opts)
  opts = opts or {}
  local brand = require("user.brand")
  local W, H = 64, 14
  local row = math.floor((vim.o.lines - H) / 2)
  local col = math.floor((vim.o.columns - W) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"

  -- Open the float without curtain animation — we'll do our own sweep instead.
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = "  ◆  welcome  ", title_pos = "center",
    width = W, height = H, row = row, col = col,
    focusable = true,
  })
  vim.wo[win].winhighlight = "Normal:BrandFloat,FloatBorder:BrandFloatBorder,FloatTitle:BrandFloatTitle"
  vim.wo[win].cursorline = false; vim.wo[win].number = false

  local lines = {
    "",
    "                  ███╗   ██╗██╗   ██╗██╗███╗   ███╗",
    "                  ████╗  ██║██║   ██║██║████╗ ████║",
    "                  ██╔██╗ ██║██║   ██║██║██╔████╔██║",
    "                  ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║",
    "                  ██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║",
    "                  ╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝",
    "",
    "                  ─────────────────────────────────",
    "                          welcome aboard",
    "",
    "                  press  F1  to open the throttle",
    "",
    "",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Sweep a colored highlight across the banner rows (rows 2..7), one column
  -- at a time, leaving each column tinted with a gradient color permanently.
  local palette = gradient_palette(W)
  local step = 0
  local timer = vim.uv.new_timer()
  timer:start(60, 20, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) then timer:stop(); timer:close(); return end
    step = step + 1
    if step > W then
      -- After sweep: hold a moment, then prepare auto-close on any key
      timer:stop(); timer:close()
      vim.defer_fn(function()
        for _, k in ipairs({ "<CR>", "<Esc>", "q", "<Space>" }) do
          pcall(vim.keymap.set, "n", k, function()
            if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
          end, { buffer = buf, silent = true, nowait = true })
        end
      end, 800)
      -- write marker
      vim.fn.mkdir(vim.fn.fnamemodify(MARKER, ":h"), "p")
      local f = io.open(MARKER, "w"); if f then f:write(os.date("%Y-%m-%dT%H:%M:%S")); f:close() end
      return
    end
    local hex = palette[step]
    for r = 1, 6 do  -- banner rows (0-indexed: 1..6 in lines)
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, r, step - 1, {
        end_col = step, hl_group = hl_for(hex), priority = 200,
      })
    end
  end))
end

function M.maybe_run()
  if vim.fn.filereadable(MARKER) == 1 then return end
  -- Defer so plugins finish loading
  vim.defer_fn(function() M.run() end, 700)
end

function M.reset() vim.fn.delete(MARKER); vim.notify("welcome: marker reset; next launch will play the welcome again") end

function M.setup()
  vim.api.nvim_create_user_command("Welcome",      M.run,   { desc = "Play the welcome ritual" })
  vim.api.nvim_create_user_command("WelcomeReset", M.reset, { desc = "Clear welcome marker so it fires on next launch" })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("user_welcome", { clear = true }),
    once = true,
    callback = function()
      -- Only fire on bare nvim launch (no args), so opening a file doesn't trigger it
      if vim.fn.argc(-1) == 0 then M.maybe_run() end
    end,
  })
end

return M
