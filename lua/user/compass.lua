-- Compass: always-on floating heading display, bottom-right corner.
-- Refreshes every 1s with branch · cwd · LSP count · mode · git dirty · time.
local M = {}

local state = { win = nil, buf = nil, timer = nil }
local CACHE = { branch = "?", dirty = "?", t = 0 }

local function git_branch_cached()
  local now = vim.uv.now()
  if now - CACHE.t < 3000 then return CACHE.branch, CACHE.dirty end
  local b = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.getcwd()) .. " rev-parse --abbrev-ref HEAD 2>/dev/null")[1] or ""
  local s = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.getcwd()) .. " status --porcelain 2>/dev/null")
  CACHE.branch = b == "" and "—" or b
  CACHE.dirty = (#s > 0) and "✗" or "✓"
  CACHE.t = now
  return CACHE.branch, CACHE.dirty
end

local MODE_GLYPHS = {
  n = " NRM ", i = " INS ", v = " VIS ", V = " V-L ", [""] = " V-B ",
  c = " CMD ", t = " TRM ", R = " REP ", s = " SEL ",
}

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local mode = MODE_GLYPHS[vim.api.nvim_get_mode().mode] or "  ?  "
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  local branch, dirty = git_branch_cached()
  local lsp = #vim.lsp.get_clients({ bufnr = 0 })
  local time = os.date("%H:%M")
  local lines = {
    "╭─ COMPASS ──────────────╮",
    "│  " .. mode .. "                │",
    string.format("│   %-19s │", cwd:sub(1, 19)),
    string.format("│   %s %-15s │", dirty, branch:sub(1, 15)),
    string.format("│   %d LSP   %s     │", lsp, time),
    "╰────────────────────────╯",
  }
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", focusable = false, noautocmd = true,
    width = 26, height = 6,
    row = vim.o.lines - 8, col = vim.o.columns - 28,
  })
  vim.wo[state.win].winhighlight = "Normal:NormalFloat"
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 1000, vim.schedule_wrap(render))
end

function M.close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open() end
end

function M.is_open() return state.win ~= nil end

function M.setup()
  vim.api.nvim_create_user_command("Compass", M.toggle, { desc = "Toggle floating compass HUD" })
end

return M
