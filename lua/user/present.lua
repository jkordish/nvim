-- Markdown presentation mode: turn any .md into a slideshow.
-- Slides split on h1 (#). Navigate with l/h or arrows, q to quit.
-- :Present launches; or <leader>mP on a .md buffer.
local M = {}

local state = { slides = {}, idx = 1, win = nil, buf = nil, src_buf = nil }

local function parse_slides(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local slides, current = {}, { title = "", body = {} }
  for _, line in ipairs(lines) do
    if line:match("^# ") and #current.body > 0 then
      table.insert(slides, current)
      current = { title = line:sub(3), body = {} }
    elseif line:match("^# ") then
      current.title = line:sub(3)
    else
      table.insert(current.body, line)
    end
  end
  if #current.body > 0 or current.title ~= "" then table.insert(slides, current) end
  return slides
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local slide = state.slides[state.idx]
  if not slide then return end
  local width = vim.api.nvim_win_get_width(state.win)
  local title = slide.title
  local pad = math.max(0, math.floor((width - vim.api.nvim_strwidth(title)) / 2))
  local hr = string.rep("─", width)
  local lines = { "", string.rep(" ", pad) .. title, hr, "" }
  for _, b in ipairs(slide.body) do table.insert(lines, "  " .. b) end
  table.insert(lines, "")
  table.insert(lines, hr)
  local footer = string.format("  %d / %d                          [h/l] prev/next  [g/G] first/last  [q] quit", state.idx, #state.slides)
  table.insert(lines, footer)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function next_slide() if state.idx < #state.slides then state.idx = state.idx + 1; render() end end
local function prev_slide() if state.idx > 1 then state.idx = state.idx - 1; render() end end

function M.start()
  if vim.bo.filetype ~= "markdown" then vim.notify("Present: not a markdown buffer", vim.log.levels.WARN); return end
  state.src_buf = vim.api.nvim_get_current_buf()
  state.slides = parse_slides(state.src_buf)
  if #state.slides == 0 then vim.notify("Present: no slides (need at least one '# heading')") return end
  state.idx = 1

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "markdown"

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    width = math.floor(vim.o.columns * 0.9),
    height = math.floor(vim.o.lines * 0.85),
    row = math.floor(vim.o.lines * 0.05),
    col = math.floor(vim.o.columns * 0.05),
    title = " ▶ Presenting ", title_pos = "center",
  })
  vim.wo[state.win].wrap = true
  vim.wo[state.win].conceallevel = 2
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false

  local keymap = function(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = state.buf, silent = true, nowait = true })
  end
  keymap("l",     next_slide)
  keymap("<Right>", next_slide)
  keymap("<Space>", next_slide)
  keymap("<CR>",  next_slide)
  keymap("h",     prev_slide)
  keymap("<Left>", prev_slide)
  keymap("<BS>",  prev_slide)
  keymap("g",     function() state.idx = 1; render() end)
  keymap("G",     function() state.idx = #state.slides; render() end)
  keymap("q",     function() M.stop() end)
  keymap("<Esc>", function() M.stop() end)

  render()
end

function M.stop()
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.setup()
  vim.api.nvim_create_user_command("Present", M.start, { desc = "Present current markdown buffer as slides" })
end

return M
