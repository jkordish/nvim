-- Brand: design tokens + window builder. The single source of truth for
-- the look-and-feel of every floating UI. Import this and call brand.win()
-- instead of nvim_open_win + your own border + your own title format.
local M = {}

-- ─── color tokens (catppuccin mocha-aligned) ───────────────────────────────
M.c = {
  bg          = "#1e1e2e",
  surface     = "#313244",
  overlay     = "#6c7086",
  muted       = "#7f849c",
  text        = "#cdd6f4",
  subtext     = "#bac2de",
  accent      = "#cba6f7",     -- the single accent threaded through everything
  accent_dim  = "#7287fd",
  ok          = "#a6e3a1",
  warn        = "#f9e2af",
  err         = "#f38ba8",
  info        = "#89b4fa",
}

-- ─── geometry & motion tokens ─────────────────────────────────────────────
M.g = {
  border      = "rounded",
  border_dbl  = "rounded",     -- never use a different border style anywhere
  padding     = 1,
  blend       = 0,             -- floats don't fade through background
  animate_ms  = 140,
  animate_steps = 7,
}

-- ─── typography ────────────────────────────────────────────────────────────
M.t = {
  signature       = "─  ◆  ─",
  title_lead      = "  ",
  title_tail      = "  ",
  bullet          = "◆ ",
  divider_char    = "─",
}

-- Format a window title with consistent leading dot + spacing.
function M.title(text, opts)
  opts = opts or {}
  local glyph = opts.glyph or "◆"
  return string.format("  %s  %s  ", glyph, text)
end

-- A divider line of the right length.
function M.divider(width)
  return string.rep(M.t.divider_char, width)
end

-- ─── highlight groups ──────────────────────────────────────────────────────
-- Re-applied on every ColorScheme so themes don't strip them.
local function apply_hl()
  local set = vim.api.nvim_set_hl
  set(0, "BrandFloat",       { bg = "NONE" })
  set(0, "BrandFloatBorder", { fg = M.c.accent, bg = "NONE" })
  set(0, "BrandFloatTitle",  { fg = M.c.accent, bold = true })
  set(0, "BrandAccent",      { fg = M.c.accent, bold = true })
  set(0, "BrandMuted",       { fg = M.c.muted })
  set(0, "BrandSubtext",     { fg = M.c.subtext })
  set(0, "BrandOk",          { fg = M.c.ok })
  set(0, "BrandWarn",        { fg = M.c.warn })
  set(0, "BrandErr",         { fg = M.c.err })
  set(0, "BrandInfo",        { fg = M.c.info })
  set(0, "BrandSignature",   { fg = M.c.muted, italic = true })
  -- Chip tokens — colored capsules for use inside buffer content via extmarks.
  -- Pair with a leading + trailing space character so the bg block reads as a
  -- pill rather than a tight box around the text.
  set(0, "BrandChipAccent",  { fg = M.c.bg,   bg = M.c.accent, bold = true })
  set(0, "BrandChipSurface", { fg = M.c.text, bg = M.c.surface, bold = true })
  set(0, "BrandChipOk",      { fg = M.c.bg,   bg = M.c.ok,     bold = true })
  set(0, "BrandChipWarn",    { fg = M.c.bg,   bg = M.c.warn,   bold = true })
  set(0, "BrandChipErr",     { fg = M.c.bg,   bg = M.c.err,    bold = true })
  set(0, "BrandChipInfo",    { fg = M.c.bg,   bg = M.c.info,   bold = true })
end

-- ─── window builder ────────────────────────────────────────────────────────
-- brand.win({
--   title       = "perf hud",
--   glyph       = "◆",           -- optional, defaults to brand glyph
--   width       = 50,             -- absolute or fraction (< 1 = percent of cols)
--   height      = 22,
--   anchor      = "center"|"tr"|"br"|"bl"|"tl"|"top"|"bottom",
--   focusable   = false,          -- default true
--   buf         = nil,            -- bring your own buf, else a scratch is made
--   animate     = true,           -- default true; curtain open animation
--   close_keys  = { "q", "<Esc>" },  -- default keymaps
--   on_close    = function() ... end,
-- })  -> { win, buf, close }
function M.win(opts)
  opts = opts or {}
  local W = opts.width  or 60
  local H = opts.height or 12
  if W < 1 then W = math.floor(vim.o.columns * W) end
  if H < 1 then H = math.floor(vim.o.lines   * H) end

  local row, col
  local anchor = opts.anchor or "center"
  if anchor == "center" then
    row = math.floor((vim.o.lines   - H) / 2)
    col = math.floor((vim.o.columns - W) / 2)
  elseif anchor == "tr" then row, col = 1, vim.o.columns - W - 2
  elseif anchor == "br" then row, col = vim.o.lines - H - 4, vim.o.columns - W - 2
  elseif anchor == "tl" then row, col = 1, 2
  elseif anchor == "bl" then row, col = vim.o.lines - H - 4, 2
  elseif anchor == "top"    then row, col = 2, math.floor((vim.o.columns - W) / 2)
  elseif anchor == "bottom" then row, col = vim.o.lines - H - 3, math.floor((vim.o.columns - W) / 2)
  end

  local buf = opts.buf or vim.api.nvim_create_buf(false, true)
  if not opts.buf then
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
  end

  local win_opts = {
    relative  = "editor",
    style     = "minimal",
    border    = M.g.border,
    title     = M.title(opts.title or "", { glyph = opts.glyph }),
    title_pos = "left",
    width     = W,
    height    = H,
    row       = row,
    col       = col,
    focusable = (opts.focusable ~= false),
    noautocmd = opts.noautocmd,
  }

  local win
  if opts.animate ~= false and not opts.noautocmd then
    local ok, curtain = pcall(require, "user.curtain")
    if ok then win = curtain.open(buf, win_opts) end
  end
  if not win then win = vim.api.nvim_open_win(buf, opts.focusable ~= false, win_opts) end

  -- Apply consistent highlight scheme to this window
  apply_hl()
  pcall(function()
    vim.wo[win].winblend = M.g.blend
    vim.wo[win].winhighlight = table.concat({
      "Normal:BrandFloat",
      "NormalFloat:BrandFloat",
      "FloatBorder:BrandFloatBorder",
      "FloatTitle:BrandFloatTitle",
      "CursorLine:Visual",
    }, ",")
    vim.wo[win].cursorline = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
  end)

  -- Close keymaps
  local close_fn = function()
    if opts.on_close then pcall(opts.on_close) end
    local ok, curtain = pcall(require, "user.curtain")
    if ok and opts.animate ~= false then curtain.close(win) else
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    end
  end
  for _, k in ipairs(opts.close_keys or { "q", "<Esc>" }) do
    pcall(vim.keymap.set, "n", k, close_fn, { buffer = buf, silent = true, nowait = true })
  end

  return { win = win, buf = buf, close = close_fn }
end

-- ─── notifications (calls back into nvim-notify with brand styling) ────────
function M.notify(msg, level, opts)
  opts = opts or {}
  -- Keep notify titles short + match brand. Level → accent color.
  local title = opts.title or "◆"
  vim.notify(msg, level or vim.log.levels.INFO, { title = title, icon = "" })
end

-- ─── premium UX helpers ────────────────────────────────────────────────────

-- A poetic empty state instead of "X is empty". Returns lines suitable for
-- buffer content, with a leading blank line for breathing room.
--   brand.poetic_empty("yank ring", "try yanking with y")
function M.poetic_empty(thing, hint)
  return {
    "",
    "",
    "        ◆",
    "",
    "        your " .. thing .. " is quiet.",
    "",
    "        " .. (hint or ""),
    "",
  }
end

-- A short keymap chip: " ⏎ " or " ⌃-p " — used inline in helpful text.
function M.kbd(key)
  return " " .. key .. " "
end

-- Time-of-day greeting. Returns "good morning" / "good afternoon" / etc.
function M.greeting()
  local h = tonumber(os.date("%H"))
  if h < 5  then return "still up"
  elseif h < 12 then return "good morning"
  elseif h < 17 then return "good afternoon"
  elseif h < 22 then return "good evening"
  else return "good evening" end
end

-- Progress spinner (return current frame as string). Call repeatedly with
-- the same key; advances internally so multiple spinners stay separate.
local _spin_state = {}
local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
function M.spinner(key)
  key = key or "default"
  _spin_state[key] = ((_spin_state[key] or 0) % #SPIN) + 1
  return SPIN[_spin_state[key]]
end

-- Center a string inside a given width using single-space padding.
function M.center(text, width)
  local len = vim.api.nvim_strwidth(text or "")
  local pad = math.max(0, math.floor((width - len) / 2))
  return string.rep(" ", pad) .. text
end

-- Right-align inside a width.
function M.right_pad(text, width)
  local len = vim.api.nvim_strwidth(text or "")
  return string.rep(" ", math.max(0, width - len)) .. text
end

-- ─── colorscheme hook to keep highlights alive ─────────────────────────────
function M.setup()
  apply_hl()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("user_brand_hl", { clear = true }),
    callback = apply_hl,
  })
end

return M
