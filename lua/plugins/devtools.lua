return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Database client. Browse/query Postgres, MySQL, SQLite, BigQuery, etc.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "tpope/vim-dadbod",
    cmd = { "DB" },
    dependencies = {
      { "kristijanhusak/vim-dadbod-ui",
        cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
        init = function()
          vim.g.db_ui_use_nerd_fonts = 1
          vim.g.db_ui_show_database_icon = 1
          vim.g.db_ui_win_position = "left"
          vim.g.db_ui_winwidth = 35
          vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/dadbod_ui"
        end,
      },
      { "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" } },
    },
    keys = {
      { "<leader>D",  "<cmd>DBUIToggle<CR>", desc = "Database UI" },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- REST client. Open a .http file, hit <leader>Rs to send the request.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "mistweaverco/kulala.nvim",
    keys = {
      { "<leader>Rs", function() require("kulala").run() end, desc = "REST send request" },
      { "<leader>Ra", function() require("kulala").run_all() end, desc = "REST send all" },
      { "<leader>Rt", function() require("kulala").toggle_view() end, desc = "REST toggle body/headers" },
      { "<leader>Rl", function() require("kulala").replay() end, desc = "REST replay last" },
      { "<leader>RI", function() require("kulala").inspect() end, desc = "REST inspect current" },
      { "<leader>Rn", function() require("kulala").jump_next() end, desc = "REST next request" },
      { "<leader>Rp", function() require("kulala").jump_prev() end, desc = "REST prev request" },
      { "<leader>Rc", function() require("kulala").copy() end, desc = "REST copy as curl" },
      { "<leader>Rf", function() require("kulala").from_curl() end, desc = "REST from curl in clipboard" },
    },
    ft = { "http", "rest" },
    opts = {
      default_view = "body",
      default_env = "dev",
      debug = false,
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- GitHub PR & issue review inside nvim. Uses your gh CLI auth.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "pwntester/octo.nvim",
    cmd = "Octo",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>Op", "<cmd>Octo pr list<CR>",    desc = "Octo PRs" },
      { "<leader>OP", "<cmd>Octo pr create<CR>",  desc = "Octo new PR" },
      { "<leader>Oi", "<cmd>Octo issue list<CR>", desc = "Octo issues" },
      { "<leader>OI", "<cmd>Octo issue create<CR>", desc = "Octo new issue" },
      { "<leader>Or", "<cmd>Octo review start<CR>", desc = "Octo start review" },
      { "<leader>Oc", "<cmd>Octo pr checks<CR>",  desc = "Octo PR checks" },
      { "<leader>Os", "<cmd>Octo search<CR>",     desc = "Octo search" },
    },
    opts = {
      enable_builtin = true,
      default_to_projects_v2 = true,
      suppress_missing_scope = { projects_v2 = true },
      ui = { use_signcolumn = false, use_signstatus = true },
      picker = "telescope",
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Kubernetes panel. Browse pods, get logs, exec, port-forward.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "Ramilito/kubectl.nvim",
    cmd = { "Kubectl", "Kubectx", "Kubens" },
    keys = {
      { "<leader>k", function() require("kubectl").toggle() end, desc = "Kubectl panel" },
    },
    opts = {
      auto_refresh = { enabled = true, interval = 3000 },
      diff = { bin = "kubediff" },
      kubectl_cmd = { name = "kubectl", env = {}, args = {} },
      namespace = "All",
      namespace_fallback = {},
      hints = true,
      context = true,
      heartbeat = true,
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Project root detection + project picker.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "ahmedkhalf/project.nvim",
    event = "VeryLazy",
    main = "project_nvim",
    opts = {
      manual_mode = false,
      detection_methods = { "lsp", "pattern" },
      patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json", "go.mod", "Cargo.toml", "pyproject.toml" },
      show_hidden = false,
    },
    keys = {
      { "<leader>fp", function() require("telescope").extensions.projects.projects({}) end, desc = "Projects" },
    },
    config = function(_, opts)
      require("project_nvim").setup(opts)
      pcall(function() require("telescope").load_extension("projects") end)
    end,
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Tmux/wezterm-aware splits.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "mrjones2014/smart-splits.nvim",
    lazy = false,
    keys = {
      { "<A-h>", function() require("smart-splits").move_cursor_left() end,  desc = "Move left across mux" },
      { "<A-j>", function() require("smart-splits").move_cursor_down() end,  desc = "Move down across mux" },
      { "<A-k>", function() require("smart-splits").move_cursor_up() end,    desc = "Move up across mux" },
      { "<A-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move right across mux" },
      { "<A-S-h>", function() require("smart-splits").resize_left() end,  desc = "Resize left" },
      { "<A-S-j>", function() require("smart-splits").resize_down() end,  desc = "Resize down" },
      { "<A-S-k>", function() require("smart-splits").resize_up() end,    desc = "Resize up" },
      { "<A-S-l>", function() require("smart-splits").resize_right() end, desc = "Resize right" },
    },
  },
}
