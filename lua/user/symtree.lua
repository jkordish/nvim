-- Symbol tree: ASCII outline of the current buffer's symbols via LSP +
-- Treesitter fallback. Side panel. Press <CR> on a symbol to jump.
local M = {}

local state = { win = nil, buf = nil, src = nil, src_win = nil, items = {} }

-- LSP SymbolKind → glyph
local KIND = {
  [1]  = "  ",  -- File
  [2]  = "  ",  -- Module
  [3]  = "  ",  -- Namespace
  [4]  = "  ",  -- Package
  [5]  = "  ",  -- Class
  [6]  = "  ",  -- Method
  [7]  = "  ",  -- Property
  [8]  = "  ",  -- Field
  [9]  = "  ",  -- Constructor
  [10] = " 練 ", -- Enum
  [11] = "  ",  -- Interface
  [12] = "  ",  -- Function
  [13] = "  ",  -- Variable
  [14] = "  ",  -- Constant
  [15] = "  ",  -- String
  [16] = "  ",  -- Number
  [17] = " ◩ ",  -- Boolean
  [18] = "  ",  -- Array
  [19] = "  ",  -- Object
  [20] = "  ",  -- Key
  [21] = " ﳠ ",  -- Null
  [22] = "  ",  -- EnumMember
  [23] = "  ",  -- Struct
  [24] = "  ",  -- Event
  [25] = "  ",  -- Operator
  [26] = "  ",  -- TypeParameter
}

local function flatten(symbols, out, depth, last_at_depth)
  out = out or {}
  last_at_depth = last_at_depth or {}
  for i, sym in ipairs(symbols) do
    local is_last = (i == #symbols)
    last_at_depth[depth] = is_last
    -- Build prefix: pipes for ancestors, ├ or └ for current
    local prefix = ""
    for d = 1, depth - 1 do
      prefix = prefix .. (last_at_depth[d] and "  " or "│ ")
    end
    if depth > 0 then prefix = prefix .. (is_last and "└─" or "├─") end
    local kind = sym.kind or 13
    local label = (sym.name or "?"):gsub("\n", " ")
    table.insert(out, {
      display = prefix .. (KIND[kind] or " · ") .. label,
      sym = sym,
    })
    if sym.children then
      flatten(sym.children, out, depth + 1, last_at_depth)
    end
  end
  return out
end

local function render(items)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.bo[state.buf].modifiable = true
  local lines = {}
  for _, it in ipairs(items) do table.insert(lines, it.display) end
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  state.items = items
end

local function open_panel()
  if state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.src = vim.api.nvim_get_current_buf()
  state.src_win = vim.api.nvim_get_current_win()

  vim.cmd("topleft vsplit | vertical resize 40")
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)

  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "symtree"
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].signcolumn = "no"

  vim.keymap.set("n", "q", function() M.close() end, { buffer = state.buf })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = state.buf })
  vim.keymap.set("n", "<CR>", function() M.jump_current() end, { buffer = state.buf })
  vim.keymap.set("n", "o", function() M.jump_current() end, { buffer = state.buf })
  vim.keymap.set("n", "R", function() M.refresh() end, { buffer = state.buf })
end

function M.jump_current()
  local cursor = vim.api.nvim_win_get_cursor(state.win)[1]
  local item = state.items[cursor]
  if not item then return end
  local sym = item.sym
  local range = (sym.location and sym.location.range) or sym.range or sym.selectionRange
  if not range then return end
  vim.api.nvim_set_current_win(state.src_win)
  pcall(vim.api.nvim_win_set_cursor, state.src_win, { range.start.line + 1, range.start.character })
  vim.cmd("normal! zz")
end

function M.refresh()
  state.src = state.src or vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = state.src, method = "textDocument/documentSymbol" })
  if #clients == 0 then
    render({ { display = "  (no LSP server with documentSymbol attached)", sym = {} } })
    return
  end
  vim.lsp.buf_request(state.src, "textDocument/documentSymbol",
    { textDocument = vim.lsp.util.make_text_document_params(state.src) },
    function(err, result)
      if err or not result then
        render({ { display = "  (LSP returned no symbols)", sym = {} } })
        return
      end
      -- result can be SymbolInformation[] (flat) or DocumentSymbol[] (nested)
      local function normalize(items)
        for _, it in ipairs(items) do
          if it.location and not it.range then it.range = it.location.range end
          if it.children then normalize(it.children) end
        end
        return items
      end
      render(flatten(normalize(result)))
    end)
end

function M.open()
  open_panel()
  M.refresh()
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open() end
end

function M.setup()
  vim.api.nvim_create_user_command("SymTree", M.toggle, { desc = "Toggle ASCII symbol tree" })
end

return M
