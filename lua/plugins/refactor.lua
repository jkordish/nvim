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
  -- Sublime-style multiple cursors. Replaced smoka7/multicursors.nvim
  -- (which depends on hydra.nvim, broken on nvim 0.12 because hydra calls
  -- `vim.tbl_deep_extend('force', getfenv(), {...})` and modern globals
  -- contain values tbl_deep_extend can't merge).
  -- ─────────────────────────────────────────────────────────────────────
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc })
      end
      -- Add cursor above / below / matching word
      map({ "n", "v" }, "<up>",   function() mc.lineAddCursor(-1) end, "MC: add cursor up")
      map({ "n", "v" }, "<down>", function() mc.lineAddCursor( 1) end, "MC: add cursor down")
      map({ "n", "v" }, "<leader>md", function() mc.matchAddCursor( 1) end, "MC: add cursor on next match")
      map({ "n", "v" }, "<leader>mD", function() mc.matchAddCursor(-1) end, "MC: add cursor on prev match")
      map({ "n", "v" }, "<leader>mA", function() mc.matchAllAddCursors() end,    "MC: add cursors on all matches")
      map({ "n", "v" }, "<leader>ms", function() mc.matchSkipCursor( 1) end,     "MC: skip next match")
      map({ "n", "v" }, "<leader>mw", function() mc.addCursorOperator() end,     "MC: add cursor on motion")
      map("n",          "<leader>mc", function() mc.clearCursors() end,          "MC: clear cursors")
      map("n",          "<esc>",      function()
        if not mc.cursorsEnabled() then mc.enableCursors()
        elseif mc.hasCursors() then mc.clearCursors()
        else vim.cmd("nohlsearch") end
      end, "Esc: clear cursors or nohl")
      -- Visual-mode: start multicursor from selection
      map("v", "<leader>m", function() mc.matchAddCursor(1) end, "MC: add cursor on next match (selection)")
      -- Normal-mode: start at cursor on next occurrence of word
      map("n", "<leader>m", function() mc.matchAddCursor(1) end, "MC: add cursor on next match (word)")
    end,
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
