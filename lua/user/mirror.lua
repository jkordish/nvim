-- Mirror: split the current file into two side-by-side windows. Right pane
-- shows the same buffer flipped upside-down (lines reversed + chars reversed
-- per-line, rendered via extmark virt_text). Edits in the left propagate
-- live; the mirror redraws.
local M = {}

local NS = vim.api.nvim_create_namespace("user_mirror")
local state = { src_buf = nil, mirror_buf = nil, mirror_win = nil, autocmd = nil }

-- Reverse the order of characters (Unicode-aware via vim.fn.split)
local function reverse_line(line)
  local out = {}
  for i = #line, 1, -1 do table.insert(out, line:sub(i, i)) end
  return table.concat(out)
end

local function rebuild()
  if not state.mirror_buf or not vim.api.nvim_buf_is_valid(state.mirror_buf) then return end
  vim.api.nvim_buf_clear_namespace(state.mirror_buf, NS, 0, -1)
  local src_lines = vim.api.nvim_buf_get_lines(state.src_buf, 0, -1, false)
  -- Replace each mirror line with a reversed virt overlay of the source line.
  -- Need same line count, so set blank lines first.
  vim.bo[state.mirror_buf].modifiable = true
  local blanks = {}
  for _ = 1, #src_lines do table.insert(blanks, "") end
  vim.api.nvim_buf_set_lines(state.mirror_buf, 0, -1, false, blanks)
  vim.bo[state.mirror_buf].modifiable = false

  -- Mirror = reverse line order AND reverse each line's characters
  for i = 1, #src_lines do
    local mirrored_idx = #src_lines - i + 1  -- top of mirror is bottom of src
    local text = reverse_line(src_lines[i])
    if text ~= "" then
      pcall(vim.api.nvim_buf_set_extmark, state.mirror_buf, NS, mirrored_idx - 1, 0, {
        virt_text = { { text, "Normal" } },
        virt_text_pos = "overlay",
      })
    end
  end
end

function M.open()
  if state.mirror_win and vim.api.nvim_win_is_valid(state.mirror_win) then
    vim.notify("mirror: already open"); return
  end
  state.src_buf = vim.api.nvim_get_current_buf()
  state.mirror_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.mirror_buf].buftype = "nofile"
  vim.bo[state.mirror_buf].bufhidden = "wipe"

  vim.cmd("vsplit")
  vim.cmd("wincmd l")
  state.mirror_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.mirror_win, state.mirror_buf)
  vim.wo[state.mirror_win].number = false
  vim.wo[state.mirror_win].relativenumber = false
  vim.wo[state.mirror_win].cursorline = false
  vim.wo[state.mirror_win].signcolumn = "no"
  vim.wo[state.mirror_win].statusline = "  ⤺  mirror  ·  read-only reflection"
  vim.api.nvim_buf_set_name(state.mirror_buf, "[mirror]")

  rebuild()
  -- Live sync
  state.autocmd = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    buffer = state.src_buf,
    callback = function() vim.schedule(rebuild) end,
  })

  -- Focus back to the source pane
  vim.cmd("wincmd h")
  vim.notify("mirror: engaged (right pane is read-only)")
end

function M.close()
  if state.autocmd then pcall(vim.api.nvim_del_autocmd, state.autocmd); state.autocmd = nil end
  if state.mirror_win and vim.api.nvim_win_is_valid(state.mirror_win) then
    vim.api.nvim_win_close(state.mirror_win, true)
  end
  state.src_buf, state.mirror_buf, state.mirror_win = nil, nil, nil
end

function M.toggle()
  if state.mirror_win and vim.api.nvim_win_is_valid(state.mirror_win) then M.close() else M.open() end
end

function M.setup() vim.api.nvim_create_user_command("Mirror", M.toggle, { desc = "Toggle reversed mirror of current file" }) end
return M
