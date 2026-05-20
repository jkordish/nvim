-- Live regex tester: opens a floating input with your pattern and highlights
-- every match in the source buffer as you type. Press <CR> to commit (set
-- the search register), <Esc> to bail and clear highlights.
local M = {}

local NS = vim.api.nvim_create_namespace("user_rextest")
local state = { win = nil, buf = nil, src_buf = nil, src_win = nil, count = 0 }

local function clear_hl()
  if state.src_buf and vim.api.nvim_buf_is_valid(state.src_buf) then
    vim.api.nvim_buf_clear_namespace(state.src_buf, NS, 0, -1)
  end
end

local function highlight(pattern)
  clear_hl()
  state.count = 0
  if pattern == "" then return end
  local lines = vim.api.nvim_buf_get_lines(state.src_buf, 0, -1, false)
  local ok, regex = pcall(vim.regex, pattern)
  if not ok then return end
  for lnum, line in ipairs(lines) do
    local from = 0
    while from < #line do
      local s, e = regex:match_str(line:sub(from + 1))
      if not s then break end
      vim.api.nvim_buf_set_extmark(state.src_buf, NS, lnum - 1, from + s, {
        end_col = from + e,
        hl_group = "Search",
        priority = 200,
      })
      state.count = state.count + 1
      if e == s then from = from + s + 1 else from = from + e end
    end
  end
  -- Update title with match count
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_config, state.win, {
      title = (" regex tester  ·  %d matches "):format(state.count),
      title_pos = "center",
    })
  end
end

function M.open()
  state.src_buf = vim.api.nvim_get_current_buf()
  state.src_win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"

  local width = 60
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor", border = "rounded", style = "minimal",
    title = " regex tester ", title_pos = "center",
    width = width, height = 1,
    row = vim.o.lines - 6, col = math.floor((vim.o.columns - width) / 2),
  })

  -- Enter insert mode automatically
  vim.cmd("startinsert")

  -- Re-highlight on every keystroke
  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = state.buf,
    callback = function()
      local pat = vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
      highlight(pat)
    end,
  })

  -- Commit on <CR>: set the search register and close
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    local pat = vim.api.nvim_buf_get_lines(state.buf, 0, 1, false)[1] or ""
    if pat ~= "" then
      vim.fn.setreg("/", pat)
      vim.cmd("set hlsearch")
    end
    M.close()
  end, { buffer = state.buf })

  vim.keymap.set({ "n", "i" }, "<Esc>", function() M.close() end, { buffer = state.buf })
end

function M.close()
  clear_hl()
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  if state.src_win and vim.api.nvim_win_is_valid(state.src_win) then vim.api.nvim_set_current_win(state.src_win) end
  state.win, state.buf = nil, nil
end

function M.setup()
  vim.api.nvim_create_user_command("RegexTest", M.open, { desc = "Live regex tester with match highlighting" })
end

return M
