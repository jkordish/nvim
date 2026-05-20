return {
  {
    "echasnovski/mini.nvim",
    event = "VeryLazy",
    config = function()
      require("mini.ai").setup({ n_lines = 500 })
      require("mini.surround").setup({
        mappings = {
          add = "gsa", delete = "gsd", find = "gsf", find_left = "gsF",
          highlight = "gsh", replace = "gsr", update_n_lines = "gsn",
        },
      })
      require("mini.pairs").setup()
      require("mini.move").setup()
      require("mini.bracketed").setup()
      require("mini.splitjoin").setup()
      require("mini.comment").setup()
      require("mini.icons").setup()
    end,
  },

  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next todo" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Prev todo" },
      { "<leader>st", "<cmd>TodoTelescope<CR>", desc = "Todos" },
    },
    opts = {},
  },

  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    opts = { use_diagnostic_signs = true },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<CR>", desc = "Diagnostics" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Buffer diagnostics" },
      { "<leader>xL", "<cmd>Trouble loclist toggle<CR>", desc = "Loclist" },
      { "<leader>xQ", "<cmd>Trouble qflist toggle<CR>", desc = "Quickfix" },
      { "<leader>xs", "<cmd>Trouble symbols toggle focus=false<CR>", desc = "Symbols" },
      { "<leader>xr", "<cmd>Trouble lsp toggle focus=false win.position=right<CR>", desc = "LSP refs" },
    },
  },

  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash TS" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "TS Search" },
    },
  },

  {
    "kylechui/nvim-surround",
    enabled = false, -- using mini.surround
  },

  {
    "akinsho/toggleterm.nvim",
    cmd = { "ToggleTerm", "TermExec" },
    keys = {
      { [[<C-/>]], "<cmd>ToggleTerm<CR>", desc = "Toggle terminal", mode = { "n", "t" } },
      { "<leader>tt", "<cmd>ToggleTerm direction=horizontal size=15<CR>", desc = "Term horizontal" },
      { "<leader>tv", "<cmd>ToggleTerm direction=vertical size=80<CR>", desc = "Term vertical" },
      { "<leader>tf", "<cmd>ToggleTerm direction=float<CR>", desc = "Term float" },
    },
    opts = {
      open_mapping = [[<C-/>]],
      direction = "float",
      shade_terminals = true,
      float_opts = { border = "rounded" },
    },
  },

  {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      providers = { "lsp", "treesitter", "regex" },
      delay = 200,
      filetypes_denylist = { "neo-tree", "Trouble", "alpha", "dashboard", "lazy", "mason" },
    },
    config = function(_, opts) require("illuminate").configure(opts) end,
  },

  {
    "NvChad/nvim-colorizer.lua",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      user_default_options = { tailwind = true, css = true, RGB = true, RRGGBB = true, names = false },
    },
  },

  {
    "kevinhwang91/nvim-ufo",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "kevinhwang91/promise-async" },
    init = function()
      vim.opt.foldcolumn = "0"
      vim.opt.foldlevel = 99
      vim.opt.foldlevelstart = 99
      vim.opt.foldenable = true
    end,
    opts = {
      provider_selector = function() return { "lsp", "treesitter" } end,
      fold_virt_text_handler = function(virt_text, lnum, end_lnum, width, truncate)
        local suffix = ("  󰁂 %d "):format(end_lnum - lnum)
        local sufWidth = vim.fn.strdisplaywidth(suffix)
        local target_width = width - sufWidth
        local cur_width = 0
        local new_virt = {}
        for _, chunk in ipairs(virt_text) do
          local text, hl = chunk[1], chunk[2]
          local chunkWidth = vim.fn.strdisplaywidth(text)
          if target_width > cur_width + chunkWidth then
            table.insert(new_virt, chunk)
          else
            text = truncate(text, target_width - cur_width)
            table.insert(new_virt, { text, hl })
            chunkWidth = vim.fn.strdisplaywidth(text)
            if cur_width + chunkWidth < target_width then
              suffix = suffix .. (" "):rep(target_width - cur_width - chunkWidth)
            end
            break
          end
          cur_width = cur_width + chunkWidth
        end
        table.insert(new_virt, { suffix, "MoreMsg" })
        return new_virt
      end,
    },
    keys = {
      { "zR", function() require("ufo").openAllFolds() end, desc = "Open all folds" },
      { "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds" },
      { "zp", function() require("ufo").peekFoldedLinesUnderCursor() end, desc = "Peek fold" },
    },
  },

  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {
      options = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" },
    },
    keys = {
      { "<leader>qs", function() require("persistence").load() end, desc = "Restore session" },
      { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore last session" },
      { "<leader>qd", function() require("persistence").stop() end, desc = "Stop session save" },
    },
    -- Auto-restore session when nvim is opened in a project dir with no args
    config = function(_, opts)
      require("persistence").setup(opts)
      vim.api.nvim_create_autocmd("VimEnter", {
        group = vim.api.nvim_create_augroup("user_persistence_autoload", { clear = true }),
        nested = true,
        callback = function()
          if vim.fn.argc(-1) > 0 then return end           -- args supplied: skip
          if vim.fn.line2byte("$") ~= -1 then return end   -- buffer has content: skip
          local cwd = vim.fn.getcwd()
          -- Only auto-restore inside known project roots (have .git or similar)
          for _, m in ipairs({ ".git", "Cargo.toml", "go.mod", "package.json", "pyproject.toml" }) do
            if vim.fn.findfile(m, cwd .. ";") ~= "" or vim.fn.finddir(m, cwd .. ";") ~= "" then
              require("persistence").load()
              return
            end
          end
        end,
      })
    end,
  },

  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    keys = {
      { "<leader>sR", function() require("grug-far").grug_far() end, desc = "Project replace" },
    },
    opts = {},
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown", "Avante", "copilot-chat" },
    opts = {
      file_types = { "markdown", "Avante", "copilot-chat" },
      latex = { enabled = false },     -- no latex parser installed
      checkbox = { enabled = true },   -- (older `position` field removed in newer versions)
    },
  },
}
