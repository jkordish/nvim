-- Jump pulse: when you land somewhere via a big movement (gd / gD / gr /
-- &lt;C-o&gt; / &lt;C-i&gt; / search), the destination line briefly highlights so the
-- eye finds the cursor immediately. Borrows the user.pulse extmark+timer
-- pattern but triggers off jump-causing events instead of `n`/`N`/`*`/`#`.
--
-- Why: in a multi-window IDE-like setup the cursor lands somewhere
-- unfamiliar and you spend a second locating it. The pulse erases that
-- second.
local M = {}

local NS = vim.api.nvim_create_namespace("user_jumppulse")
local DURATION = 320

local function _pulse(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local lc = vim.api.nvim_buf_line_count(bufnr)
  if lc == 0 then return end
  -- Schedule races: by the time we fire, the current window may not be
  -- showing bufnr anymore, so cursor[1] can be past bufnr's line count.
  -- Resolve the cursor against the window currently showing bufnr; if none,
  -- fall back to row 1 (still a valid pulse target).
  local line
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      line = vim.api.nvim_win_get_cursor(win)[1] - 1
      break
    end
  end
  if not line then line = 0 end
  if line >= lc then line = lc - 1 end
  if line < 0 then return end
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, line, 0, {
    end_row = math.min(line + 1, lc), end_col = 0,
    hl_group = "UserPulse",     -- defined by user.pulse (shared)
    hl_eol = true, priority = 200,
  })
  if not ok then return end
  local closed = false
  local timer = vim.uv.new_timer()
  timer:start(DURATION, 0, vim.schedule_wrap(function()
    if closed then return end
    closed = true
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, NS, id)
    end
    pcall(function() timer:stop() end)
    pcall(function() if not timer:is_closing() then timer:close() end end)
  end))
end

local _last_jump_buf, _last_jump_line = nil, nil
local function _jumped()
  local buf  = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  -- Filter spurious fires: only pulse when buffer changed OR line moved > 3 rows
  if _last_jump_buf == buf and math.abs((_last_jump_line or 0) - line) <= 3 then
    return
  end
  _last_jump_buf, _last_jump_line = buf, line
  vim.schedule(function() _pulse(buf) end)
end

-- Wrappers for the common jump verbs. These call the underlying command
-- first, then pulse. Set via `keys` on a buffer-agnostic basis.
-- For plain-character keys (gd, gD, …) `normal!` interprets them directly.
local function _wrap_jump(key)
  return function()
    pcall(vim.cmd, "normal! " .. vim.v.count1 .. key)
    _jumped()
  end
end

-- Termcode keys (<C-o>, <C-i>) can't go through `vim.cmd("normal! ...")` —
-- the bare argument isn't a vim string literal, so `\<C-o>` would stay
-- the literal six characters. Wrap in `:execute "normal! \<...>"` so
-- vim's Ex execute evaluates the inner string and interprets the
-- keycode. `keyname` is the bare name without angle brackets ("C-o").
local function _wrap_termcode(keyname)
  return function()
    vim.cmd(string.format([[execute "normal! %d\<%s>"]], vim.v.count1, keyname))
    _jumped()
  end
end

function M.setup()
  -- Reuse the UserPulse hl group from user.pulse (already defined there).
  -- If user.pulse hasn't loaded yet, define a fallback.
  pcall(vim.api.nvim_set_hl, 0, "UserPulse", { bg = "#585b70", default = true })

  local grp = vim.api.nvim_create_augroup("user_jumppulse", { clear = true })

  -- Pulse when LSP jumps land us somewhere
  vim.api.nvim_create_autocmd("LspAttach", {
    group = grp,
    callback = function(args)
      local bufnr = args.buf
      for _, k in ipairs({ "gd", "gD", "gr", "gi", "gy" }) do
        vim.keymap.set("n", k, _wrap_jump(k), { buffer = bufnr, silent = true,
          desc = "LSP jump (with pulse)" })
      end
    end,
  })

  -- Jumplist navigation — termcode form, see _wrap_termcode note above.
  vim.keymap.set("n", "<C-o>", _wrap_termcode("C-o"), { silent = true, desc = "Jump back (with pulse)" })
  vim.keymap.set("n", "<C-i>", _wrap_termcode("C-i"), { silent = true, desc = "Jump forward (with pulse)" })

  -- Pulse after entering a different buffer via mouse / picker / Telescope
  vim.api.nvim_create_autocmd("BufEnter", {
    group = grp,
    callback = function(args)
      -- Skip the very first BufEnter (avoid pulsing the launch buffer)
      if not _last_jump_buf then _last_jump_buf = args.buf; return end
      if args.buf ~= _last_jump_buf then
        _last_jump_buf = args.buf
        _last_jump_line = vim.api.nvim_win_get_cursor(0)[1]
        vim.schedule(function() _pulse(args.buf) end)
      end
    end,
  })
end

return M
