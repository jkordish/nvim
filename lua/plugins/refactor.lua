return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Code refactoring: extract function/variable, inline, debug prints.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "ThePrimeagen/refactoring.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-treesitter/nvim-treesitter" },
    keys = {
      { "<leader>cre", function() require("refactoring").refactor("Extract Function") end,         mode = "x", desc = "Extract function" },
      { "<leader>crf", function() require("refactoring").refactor("Extract Function To File") end, mode = "x", desc = "Extract function to file" },
      { "<leader>crv", function() require("refactoring").refactor("Extract Variable") end,         mode = "x", desc = "Extract variable" },
      { "<leader>cri", function() require("refactoring").refactor("Inline Variable") end,          mode = { "n", "x" }, desc = "Inline variable" },
      { "<leader>crI", function() require("refactoring").refactor("Inline Function") end,          desc = "Inline function" },
      { "<leader>crb", function() require("refactoring").refactor("Extract Block") end,            desc = "Extract block" },
      { "<leader>crB", function() require("refactoring").refactor("Extract Block To File") end,    desc = "Extract block to file" },
      { "<leader>crp", function() require("refactoring").debug.printf({ below = false }) end,      desc = "Debug printf" },
      { "<leader>crV", function() require("refactoring").debug.print_var() end, mode = { "n", "x" }, desc = "Debug print var" },
      { "<leader>crc", function() require("refactoring").debug.cleanup({}) end, desc = "Debug print cleanup" },
      { "<leader>crm", function() require("refactoring").select_refactor() end, mode = { "n", "x" }, desc = "Refactor menu" },
    },
    opts = {},
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Sublime-style multiple cursors.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "smoka7/multicursors.nvim",
    event = "VeryLazy",
    dependencies = { "smoka7/hydra.nvim" },
    cmd = { "MCstart", "MCvisual", "MCclear", "MCpattern", "MCvisualPattern", "MCunderCursor" },
    keys = {
      { "<leader>m",  "<cmd>MCstart<CR>",        mode = { "n" }, desc = "Multicursor start" },
      { "<leader>m",  "<cmd>MCvisual<CR>",       mode = { "v" }, desc = "Multicursor selection" },
      { "<leader>mw", "<cmd>MCunderCursor<CR>",  desc = "Multicursor word" },
      { "<leader>mP", "<cmd>MCpattern<CR>",      desc = "Multicursor pattern" },
      { "<leader>mc", "<cmd>MCclear<CR>",        desc = "Multicursor clear" },
    },
    opts = {
      hint_config = { border = "rounded", position = "bottom-right" },
      generate_hints = { normal = true, insert = true, extend = true, config = { format = "%s | ", max_hints = 5 } },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Beautiful floating LSP preview (definitions, refs, implementations).
  -- ─────────────────────────────────────────────────────────────────────
  {
    "dnlhc/glance.nvim",
    cmd = "Glance",
    keys = {
      { "gpd", "<cmd>Glance definitions<CR>",      desc = "Peek definitions" },
      { "gpr", "<cmd>Glance references<CR>",       desc = "Peek references" },
      { "gpt", "<cmd>Glance type_definitions<CR>", desc = "Peek type definition" },
      { "gpi", "<cmd>Glance implementations<CR>",  desc = "Peek implementations" },
    },
    opts = {
      height = 18,
      border = { enable = true, top_char = "─", bottom_char = "─" },
      list = { position = "right", width = 0.33 },
      theme = { enable = true, mode = "auto" },
      hooks = {
        before_open = function(results, open, jump, _)
          if #results == 1 then jump(results[1]) else open(results) end
        end,
      },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Auto-generate docstrings (JSDoc, Godoc, rustdoc, PEP257, etc.)
  -- ─────────────────────────────────────────────────────────────────────
  {
    "danymat/neogen",
    cmd = "Neogen",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    keys = {
      { "<leader>cn", function() require("neogen").generate() end,                   desc = "Generate docstring" },
      { "<leader>cN", function() require("neogen").generate({ type = "class" }) end, desc = "Generate class doc" },
    },
    opts = {
      snippet_engine = "luasnip",
      languages = {
        python = { template = { annotation_convention = "google_docstrings" } },
        rust   = { template = { annotation_convention = "rustdoc" } },
        go     = { template = { annotation_convention = "godoc" } },
        lua    = { template = { annotation_convention = "ldoc" } },
        typescript = { template = { annotation_convention = "tsdoc" } },
        typescriptreact = { template = { annotation_convention = "tsdoc" } },
        javascript = { template = { annotation_convention = "jsdoc" } },
      },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Show usage count above functions/symbols inline.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "Wansmer/symbol-usage.nvim",
    event = "LspAttach",
    opts = {
      vt_position = "end_of_line",
      references = { enabled = true, include_declaration = false },
      definition = { enabled = false },
      implementation = { enabled = true },
      kinds = {
        vim.lsp.protocol.SymbolKind.Function,
        vim.lsp.protocol.SymbolKind.Method,
        vim.lsp.protocol.SymbolKind.Class,
        vim.lsp.protocol.SymbolKind.Interface,
      },
    },
  },
}
