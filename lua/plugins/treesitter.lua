-- nvim-treesitter on the maintained `main` branch (post-archival of master).
-- Requires the tree-sitter CLI for parser compilation.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    lazy = false,
    priority = 500,
    opts = {
      install_dir = vim.fn.stdpath("data") .. "/site",
    },
    config = function(_, opts)
      require("nvim-treesitter").setup(opts)

      local ensure = {
        "bash", "c", "cpp", "css", "diff", "dockerfile", "go", "gomod", "gosum",
        "html", "javascript", "json", "jsonc", "lua", "luadoc", "luap",
        "markdown", "markdown_inline", "python", "query", "regex", "rust",
        "scss", "sql", "toml", "tsx", "typescript", "vim", "vimdoc", "yaml",
        "gitcommit", "gitignore", "git_config", "git_rebase",
      }
      local installed = require("nvim-treesitter").get_installed("parsers") or {}
      local need = vim.tbl_filter(function(p) return not vim.tbl_contains(installed, p) end, ensure)
      if #need > 0 then require("nvim-treesitter").install(need) end

      -- Start highlighting + indent on FileType (main-branch idiom).
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_ts_start", { clear = true }),
        callback = function(ev)
          local ft = vim.bo[ev.buf].filetype
          local lang = vim.treesitter.language.get_lang(ft)
          if not lang then return end
          local ok = pcall(vim.treesitter.start, ev.buf, lang)
          if ok then
            vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- Textobjects on main branch — separate plugin, separate setup.
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
          selection_modes = {
            ["@parameter.outer"] = "v",
            ["@function.outer"] = "V",
            ["@class.outer"] = "<c-v>",
          },
        },
        move = { set_jumps = true },
      })

      local map = vim.keymap.set
      local select = require("nvim-treesitter-textobjects.select").select_textobject
      for _, mode in ipairs({ "x", "o" }) do
        map(mode, "af", function() select("@function.outer", "textobjects") end, { desc = "a function" })
        map(mode, "if", function() select("@function.inner", "textobjects") end, { desc = "inner function" })
        map(mode, "ac", function() select("@class.outer", "textobjects") end, { desc = "a class" })
        map(mode, "ic", function() select("@class.inner", "textobjects") end, { desc = "inner class" })
        map(mode, "aa", function() select("@parameter.outer", "textobjects") end, { desc = "a parameter" })
        map(mode, "ia", function() select("@parameter.inner", "textobjects") end, { desc = "inner parameter" })
      end
      local move = require("nvim-treesitter-textobjects.move")
      map({ "n", "x", "o" }, "]f", function() move.goto_next_start("@function.outer", "textobjects") end, { desc = "Next function" })
      map({ "n", "x", "o" }, "[f", function() move.goto_previous_start("@function.outer", "textobjects") end, { desc = "Prev function" })
      map({ "n", "x", "o" }, "]c", function() move.goto_next_start("@class.outer", "textobjects") end, { desc = "Next class" })
      map({ "n", "x", "o" }, "[c", function() move.goto_previous_start("@class.outer", "textobjects") end, { desc = "Prev class" })
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPost", "BufNewFile" },
    opts = { mode = "cursor", max_lines = 4, multiline_threshold = 1 },
    keys = {
      { "<leader>tc", function() require("treesitter-context").toggle() end, desc = "Toggle TS context" },
    },
  },

  {
    "windwp/nvim-ts-autotag",
    event = { "BufReadPost", "BufNewFile" },
    opts = {},
  },
}
