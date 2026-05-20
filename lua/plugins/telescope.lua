return {
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    branch = "master",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make", cond = vim.fn.executable("make") == 1 },
      "nvim-telescope/telescope-ui-select.nvim",
      "nvim-telescope/telescope-file-browser.nvim",
    },
    keys = {
      -- <leader><space> is now the Suggest contextual launcher (user.suggest)
      -- <leader>ff is the explicit find-files binding (kept below)
      { "<leader>ff", function() require("telescope.builtin").find_files() end, desc = "Find files" },
      { "<leader>fg", function() require("telescope.builtin").git_files() end, desc = "Git files" },
      { "<leader>fr", function() require("telescope.builtin").oldfiles() end, desc = "Recent files" },
      { "<leader>fb", function() require("telescope.builtin").buffers({ sort_mru = true, ignore_current_buffer = true }) end, desc = "Buffers" },
      { "<leader>fn", function() require("telescope").extensions.file_browser.file_browser({ path = "%:p:h", select_buffer = true }) end, desc = "File browser" },
      { "<leader>sg", function() require("telescope.builtin").live_grep() end, desc = "Live grep" },
      { "<leader>sw", function() require("telescope.builtin").grep_string() end, mode = { "n", "v" }, desc = "Grep word" },
      { "<leader>sb", function() require("telescope.builtin").current_buffer_fuzzy_find() end, desc = "Buffer fuzzy" },
      { "<leader>sh", function() require("telescope.builtin").help_tags() end, desc = "Help" },
      { "<leader>sk", function() require("telescope.builtin").keymaps() end, desc = "Keymaps" },
      { "<leader>sc", function() require("telescope.builtin").commands() end, desc = "Commands" },
      { "<leader>sd", function() require("telescope.builtin").diagnostics() end, desc = "Diagnostics" },
      { "<leader>s.", function() require("telescope.builtin").resume() end, desc = "Resume search" },
      { "<leader>sm", function() require("telescope.builtin").marks() end, desc = "Marks" },
      { "<leader>sr", function() require("telescope.builtin").registers() end, desc = "Registers" },
      { "<leader>gC", function() require("telescope.builtin").git_commits() end, desc = "Git commits" },
      { "<leader>gb", function() require("telescope.builtin").git_branches() end, desc = "Git branches" },
      { "<leader>gs", function() require("telescope.builtin").git_status() end, desc = "Git status" },
    },
    opts = function()
      local actions = require("telescope.actions")
      return {
        defaults = {
          prompt_prefix = "  ",
          selection_caret = " ",
          path_display = { "truncate" },
          sorting_strategy = "ascending",
          layout_config = {
            horizontal = { prompt_position = "top", preview_width = 0.55 },
            vertical = { mirror = false },
            width = 0.87, height = 0.80, preview_cutoff = 120,
          },
          mappings = {
            i = {
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<C-u>"] = false,
              ["<Esc>"] = actions.close,
            },
            n = { q = actions.close },
          },
          file_ignore_patterns = { "%.git/", "node_modules/", "%.venv/", "dist/", "build/", "%.lock" },
          vimgrep_arguments = {
            "rg", "--color=never", "--no-heading", "--with-filename",
            "--line-number", "--column", "--smart-case", "--hidden", "--glob=!.git/",
          },
        },
        pickers = {
          find_files = { hidden = true, find_command = { "rg", "--files", "--hidden", "--glob=!.git/" } },
        },
        extensions = {
          ["ui-select"] = { require("telescope.themes").get_dropdown({}) },
          fzf = { fuzzy = true, override_generic_sorter = true, override_file_sorter = true, case_mode = "smart_case" },
        },
      }
    end,
    config = function(_, opts)
      local telescope = require("telescope")
      telescope.setup(opts)
      pcall(telescope.load_extension, "fzf")
      pcall(telescope.load_extension, "ui-select")
      pcall(telescope.load_extension, "file_browser")
    end,
  },
}
