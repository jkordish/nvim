-- Search jump pulse: when you press n/N/* or jump via /, the line briefly
-- highlights and fades out via extmarks + a uv timer. Tiny module, big vibe.
local M = {}

local NS = vim.api.nvim_create_namespace("user_pulse")
local DURATION = 320  -- ms total
local STEPS = 8
local HL_GROUP = "UserPulse"

local function ensure_hl()
  vim.api.nvim_set_hl(0, HL_GROUP, { bg = "#585b70", default = true })
end

function M.flash(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  ensure_hl()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local id = vim.api.nvim_buf_set_extmark(bufnr, NS, line, 0, {
    end_row = line + 1, end_col = 0,
    hl_group = HL_GROUP, hl_eol = true,
    priority = 200,
  })

  -- One-shot timer. (Previously this was a repeating interval timer whose
  -- C-side ticks queued multiple scheduled callbacks before the first one
  -- ran — every later callback then tried to close an already-closing
  -- handle, spamming "handle is already closing". Since the per-step body
  -- did nothing visible, one-shot at DURATION is functionally identical.)
  local timer = vim.uv.new_timer()
  local closed = false
  timer:start(DURATION, 0, vim.schedule_wrap(function()
    if closed then return end
    closed = true
    pcall(vim.api.nvim_buf_del_extmark, bufnr, NS, id)
    pcall(function() timer:stop() end)
    pcall(function() if not timer:is_closing() then timer:close() end end)
  end))
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("user_pulse", { clear = true })
  -- Pulse on search jump
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = grp,
    pattern = { "/", "?" },
    callback = function()
      vim.schedule(function()
        if vim.v.event and vim.v.event.abort then return end
        M.flash()
      end)
    end,
  })

  -- Wrap n / N / * / # so they pulse after jumping
  for _, k in ipairs({ "n", "N", "*", "#" }) do
    vim.keymap.set("n", k, function()
      pcall(vim.cmd, "normal! " .. vim.v.count1 .. k)
      vim.cmd("normal! zz")
      M.flash()
    end, { silent = true, desc = "Search " .. k .. " (with pulse)" })
  end

  vim.api.nvim_create_user_command("Pulse", function() M.flash() end, { desc = "Flash the current line" })
end

return M
