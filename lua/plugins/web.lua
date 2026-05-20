return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Live HTML/JS/CSS reload in a browser. Drop-in Live Server replacement.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "barrett-ruth/live-server.nvim",
    build = "npm install -g live-server",
    cmd = { "LiveServerStart", "LiveServerStop", "LiveServerToggle" },
    keys = {
      { "<leader>Wl", "<cmd>LiveServerToggle<CR>", desc = "Live server toggle" },
    },
    config = true,
  },

  -- Color picker with hue/saturation wheels (replaces VSCode color picker).
  {
    "uga-rosa/ccc.nvim",
    cmd = { "CccPick", "CccConvert", "CccHighlighterToggle" },
    keys = {
      { "<leader>Wp", "<cmd>CccPick<CR>", desc = "Color picker" },
      { "<leader>Wc", "<cmd>CccConvert<CR>", desc = "Convert color" },
    },
    opts = {
      highlighter = { auto_enable = false, lsp = true },
    },
  },

  -- Tailwind class sorter (auto-sorts on save when tailwindcss-language-server
  -- is attached). Standalone formatter conform calls.
  {
    "luckasRanarison/tailwind-tools.nvim",
    ft = { "html", "css", "scss", "javascriptreact", "typescriptreact", "vue", "svelte", "astro" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      document_color = { enabled = true, kind = "background" },
      conceal = { enabled = false },
      cmp = { highlight = "background" },
    },
  },

  -- emmet_language_server + tailwindcss are configured in lsp.lua via the
  -- standard lspconfig + Mason flow.
}
