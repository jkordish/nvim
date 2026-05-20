return {
  -- Go DAP adapter — registers the delve-based configurations for nvim-dap.
  {
    "leoluz/nvim-dap-go",
    ft = "go",
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {},
    keys = {
      { "<leader>dgt", function() require("dap-go").debug_test() end, desc = "Debug nearest go test" },
      { "<leader>dgl", function() require("dap-go").debug_last_test() end, desc = "Debug last go test" },
    },
  },

  -- Quality-of-life: struct tag management, function signature tweaks, test gen.
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
      "nvim-treesitter/nvim-treesitter",
    },
    ft = { "go", "gomod", "gosum", "gotmpl", "gohtmltmpl", "gotexttmpl" },
    build = ':lua require("go.install").update_all_sync()',
    opts = {
      -- We let our own lsp.lua own gopls config — go.nvim's defaults conflict.
      lsp_cfg = false,
      lsp_inlay_hints = { enable = false }, -- already handled per-buffer
      lsp_keymaps = false,
      diagnostic = false,
      luasnip = true,
      icons = { breakpoint = "", currentpos = "" },
    },
    keys = {
      { "<leader>cgt", "<cmd>GoAddTag<CR>", desc = "Go add struct tags", ft = "go" },
      { "<leader>cgT", "<cmd>GoRmTag<CR>", desc = "Go remove struct tags", ft = "go" },
      { "<leader>cgi", "<cmd>GoImpl<CR>", desc = "Go impl interface", ft = "go" },
      { "<leader>cgf", "<cmd>GoFillStruct<CR>", desc = "Go fill struct", ft = "go" },
      { "<leader>cgs", "<cmd>GoFillSwitch<CR>", desc = "Go fill switch", ft = "go" },
      { "<leader>cge", "<cmd>GoIfErr<CR>", desc = "Go add if-err", ft = "go" },
      { "<leader>cgr", "<cmd>GoRun<CR>", desc = "Go run", ft = "go" },
    },
  },
}
