return {
  {
    "yetone/avante.nvim",
    event = "VeryLazy",
    version = false,
    build = "make",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
      "zbirenbaum/copilot.lua",
      {
        "MeanderingProgrammer/render-markdown.nvim",
        opts = { file_types = { "markdown", "Avante" } },
        ft = { "markdown", "Avante" },
      },
    },
    opts = {
      provider = "claude",
      providers = {
        claude = {
          endpoint = "https://api.anthropic.com",
          model = "claude-sonnet-4-6",
          timeout = 30000,
          extra_request_body = {
            temperature = 0,
            max_tokens = 8192,
          },
        },
      },
      behaviour = {
        auto_suggestions = false,
        auto_set_highlight_group = true,
        auto_set_keymaps = true,
        auto_apply_diff_after_generation = false,
        support_paste_from_clipboard = false,
      },
      mappings = {
        ask = "<leader>aA",
        edit = "<leader>aE",
        refresh = "<leader>aR",
        toggle = { default = "<leader>aT", debug = "<leader>aTd", hint = "<leader>aTh", suggestion = "<leader>aTs", repomap = "<leader>aTr" },
      },
      hints = { enabled = true },
      windows = {
        position = "right",
        wrap = true,
        width = 35,
        sidebar_header = { align = "center", rounded = true },
      },
    },
  },
}
