-- Restyle the stock LSP floating windows (hover + signature_help) so they
-- match the brand look — rounded accent border, max width/height, markdown
-- ft so code fences render with treesitter.
local M = {}

local DEFAULTS = {
  border = "rounded",
  max_width = 80,
  max_height = 20,
  focusable = true,
  silent = true,
  close_events = { "CursorMoved", "BufLeave", "InsertEnter", "FocusLost" },
}

function M.setup()
  -- vim.lsp.util.open_floating_preview is the choke-point. Wrap it once.
  -- Some plugins call it with `opts` as a boolean (legacy 3rd arg), so we
  -- type-guard before tbl_deep_extend (which requires tables).
  local orig = vim.lsp.util.open_floating_preview
  vim.lsp.util.open_floating_preview = function(contents, syntax, opts, ...)
    if type(opts) ~= "table" then opts = {} end
    opts = vim.tbl_deep_extend("force", DEFAULTS, opts)
    return orig(contents, syntax, opts, ...)
  end

  -- vim.diagnostic float defaults too — keeps style consistent
  local cur_float = (vim.diagnostic.config() or {}).float
  if type(cur_float) ~= "table" then cur_float = {} end
  vim.diagnostic.config({
    float = vim.tbl_deep_extend("force", cur_float, { border = "rounded", max_width = 80 }),
  })
end

return M
