return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = false,
      term_colors = true,
      styles = {
        comments = { "italic" },
        conditionals = { "italic" },
        keywords = { "italic" },
      },
      integrations = {
        cmp = true,
        gitsigns = true,
        treesitter = true,
        treesitter_context = true,
        telescope = { enabled = true },
        mason = true,
        which_key = true,
        notify = true,
        noice = true,
        mini = { enabled = true },
        native_lsp = {
          enabled = true,
          virtual_text = { errors = { "italic" }, hints = { "italic" }, warnings = { "italic" }, information = { "italic" } },
          underlines = { errors = { "underline" }, hints = { "underline" }, warnings = { "underline" }, information = { "underline" } },
          inlay_hints = { background = true },
        },
        indent_blankline = { enabled = true, scope_color = "lavender" },
        dap = true,
        dap_ui = true,
        markdown = true,
        neotree = true,
        copilot_vim = true,
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },
}
