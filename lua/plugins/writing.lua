-- vim-pencil + vim-wordy REMOVED — niche prose tools we never reached for.
-- ltex-ls (LanguageTool grammar) covers the practical need; for soft-wrap
-- in markdown the FileType autocmd in core/autocmds.lua already sets wrap.
return {
  -- LanguageTool grammar checker via ltex-ls (installed by Mason).
  {
    "barreiroleo/ltex_extra.nvim",
    ft = { "markdown", "tex", "text", "gitcommit" },
    dependencies = { "neovim/nvim-lspconfig" },
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("user_ltex", { clear = true }),
        pattern = { "markdown", "tex", "text", "gitcommit" },
        once = true,
        callback = function()
          local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/ltex-ls"
          if vim.fn.executable(mason_bin) == 0 and vim.fn.executable("ltex-ls") == 0 then return end
          local ok = pcall(function()
            vim.lsp.config("ltex", {
              cmd = { vim.fn.executable(mason_bin) == 1 and mason_bin or "ltex-ls" },
              filetypes = { "markdown", "tex", "text", "gitcommit" },
              settings = {
                ltex = {
                  language = "en-US",
                  additionalRules = { enablePickyRules = true },
                  disabledRules = { ["en-US"] = { "MORFOLOGIK_RULE_EN_US" } },
                },
              },
              on_attach = function(_, bufnr)
                require("ltex_extra").setup({
                  load_langs = { "en-US" },
                  init_check = true,
                  path = vim.fn.stdpath("data") .. "/ltex",
                })
              end,
            })
            vim.lsp.enable("ltex")
          end)
        end,
      })
    end,
  },
}
