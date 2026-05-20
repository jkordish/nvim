-- Treesitter playground: floating window showing the AST node chain at the
-- cursor. Updates live as you move. Press 'k' to copy the node type to clipboard.
local M = {}

local state = { win = nil, buf = nil, src_buf = nil, autocmd = nil }

local function get_node_chain(bufnr)
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
  if not lang then return nil, "no treesitter parser" end
  local parser = vim.treesitter.get_parser(bufnr, lang)
  local tree = parser:parse()[1]
  if not tree then return nil, "no AST" end
  local node = tree:root():descendant_for_range(row, col, row, col)
  local chain = {}
  while node do
    local s_row, s_col, e_row, e_col = node:range()
    table.insert(chain, 1, {
      type = node:type(),
      named = node:named(),
      start = { s_row, s_col },
      ["end"] = { e_row, e_col },
      text = vim.treesitter.get_node_text(node, bufnr):sub(1, 60):gsub("\n", "⏎"),
    })
    node = node:parent()
  end
  return chain
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local chain, err = get_node_chain(state.src_buf)
  local lines
  if not chain then
    lines = { "  (" .. (err or "unknown") .. ")" }
  else
    lines = { "  AST chain (cursor → root, deepest first)", "  ─────────────────────────────" }
    for i, n in ipairs(chain) do
      local prefix = string.rep("│ ", i - 1) .. (i == #chain and "└─" or "├─")
      local glyph = n.named and "●" or "○"
      table.insert(lines, string.format("  %s %s %s  %d:%d-%d:%d",
        prefix, glyph, n.type,
        n.start[1] + 1, n.start[2], n["end"][1] + 1, n["end"][2]))
    end
    table.insert(lines, "")
    table.insert(lines, "  Innermost text: " .. chain[#chain].text)
    table.insert(lines, "")
    table.insert(lines, "  [k] copy type  [r] refresh  [q] close")
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

function M.open()
  state.src_buf = vim.api.nvim_get_current_buf()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "tsplay"

  local width = 60
  local height = 20
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", border = "rounded", style = "minimal",
    title = " 󰔱 treesitter playground ", title_pos = "center",
    width = width, height = height,
    row = 1, col = vim.o.columns - width - 2, focusable = true,
  })

  vim.keymap.set("n", "q", function() M.close() end, { buffer = state.buf })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = state.buf })
  vim.keymap.set("n", "r", function() render() end, { buffer = state.buf })
  vim.keymap.set("n", "k", function()
    local chain = get_node_chain(state.src_buf)
    if chain and chain[#chain] then
      vim.fn.setreg("+", chain[#chain].type)
      vim.notify("TS: copied '" .. chain[#chain].type .. "'")
    end
  end, { buffer = state.buf })

  state.autocmd = vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
    callback = function()
      if state.win and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_get_current_buf() == state.src_buf then
        render()
      end
    end,
  })

  render()
end

function M.close()
  if state.autocmd then vim.api.nvim_del_autocmd(state.autocmd); state.autocmd = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf, state.src_buf = nil, nil, nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open() end
end

function M.setup()
  vim.api.nvim_create_user_command("TSPlay", M.toggle, { desc = "Toggle treesitter AST playground" })
end

return M
