-- Synesthesia: gives every identifier in the buffer a deterministic color
-- based on its hash. Repeated names share a color, so visual patterns
-- emerge — you can SEE which variables recur. Toggle with :Synesthesia.
local M = {}

local NS = vim.api.nvim_create_namespace("user_synesthesia")
local active = {}

-- Pleasing palette of 24 distinguishable pastel-ish hues
local PALETTE = {
  "#f5e0dc", "#f2cdcd", "#f5c2e7", "#cba6f7", "#f38ba8", "#eba0ac",
  "#fab387", "#f9e2af", "#a6e3a1", "#94e2d5", "#89dceb", "#74c7ec",
  "#89b4fa", "#b4befe", "#cdd6f4", "#bac2de", "#a6adc8", "#9399b2",
  "#fc967a", "#a4e3c2", "#d6c1ff", "#ffe3a0", "#a0d6ff", "#ffaad4",
}

local function hash_color(name)
  local h = 5381
  for i = 1, #name do h = (h * 33 + name:byte(i)) end
  return PALETTE[(h % #PALETTE) + 1]
end

local hl_cache = {}
local function color_hl(hex)
  if hl_cache[hex] then return hl_cache[hex] end
  local name = "Syn_" .. hex:sub(2)
  vim.api.nvim_set_hl(0, name, { fg = hex, bold = true })
  hl_cache[hex] = name
  return name
end

local function apply(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
  if not lang then return false, "no parser" end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok then return false, "parser failed" end
  local tree = parser:parse()[1]
  local query
  -- Same query for most languages — match all identifier-like nodes
  ok, query = pcall(vim.treesitter.query.parse, lang,
    "[(identifier) (property_identifier) (field_identifier) (variable) (name)] @id")
  if not ok then return false, "no identifier query for " .. lang end

  local n = 0
  for _, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    local s_row, s_col, e_row, e_col = node:range()
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text and #text >= 2 then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, s_row, s_col, {
        end_row = e_row, end_col = e_col,
        hl_group = color_hl(hash_color(text)),
        priority = 250,
      })
      n = n + 1
    end
  end
  return true, n .. " identifiers colored"
end

function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ok, msg = apply(bufnr)
  if not ok then vim.notify("synesthesia: " .. msg, vim.log.levels.WARN); return end
  active[bufnr] = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function() apply(bufnr) end,
  })
  vim.notify("synesthesia ON · " .. msg)
end

function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  if active[bufnr] then vim.api.nvim_del_autocmd(active[bufnr]); active[bufnr] = nil end
  vim.notify("synesthesia OFF")
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then M.disable(bufnr) else M.enable(bufnr) end
end

function M.setup()
  vim.api.nvim_create_user_command("Synesthesia", function() M.toggle() end, { desc = "Hash-color every identifier" })
end

return M
