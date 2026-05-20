return {
  -- First-class Rust experience. Replaces bare rust_analyzer with macro
  -- expansion, integrated DAP, runnables, debuggables, code action grouping.
  {
    "mrcjkb/rustaceanvim",
    version = "^6",
    ft = { "rust" },
    dependencies = { "saghen/blink.cmp" },
    init = function()
      vim.g.rustaceanvim = function()
        local capabilities = require("blink.cmp").get_lsp_capabilities()
        return {
          server = {
            capabilities = capabilities,
            default_settings = {
              ["rust-analyzer"] = {
                cargo = { allFeatures = true, loadOutDirsFromCheck = true, buildScripts = { enable = true } },
                checkOnSave = true,
                check = { command = "clippy", extraArgs = { "--no-deps" } },
                procMacro = {
                  enable = true,
                  ignored = {
                    ["async-trait"] = { "async_trait" },
                    ["napi-derive"] = { "napi" },
                    ["async-recursion"] = { "async_recursion" },
                  },
                },
                inlayHints = {
                  bindingModeHints = { enable = false },
                  chainingHints = { enable = true },
                  closingBraceHints = { enable = true, minLines = 25 },
                  parameterHints = { enable = true },
                  typeHints = { enable = true },
                },
              },
            },
            on_attach = function(_, bufnr)
              local map = function(lhs, rhs, desc) vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc }) end
              map("<leader>cR", function() vim.cmd.RustLsp("codeAction") end, "Rust code action")
              map("<leader>cE", function() vim.cmd.RustLsp("expandMacro") end, "Rust expand macro")
              map("<leader>cC", function() vim.cmd.RustLsp("openCargo") end, "Open Cargo.toml")
              map("<leader>cM", function() vim.cmd.RustLsp("parentModule") end, "Rust parent module")
              map("<leader>tr", function() vim.cmd.RustLsp({ "runnables", bang = true }) end, "Rust runnable")
              map("<leader>tD", function() vim.cmd.RustLsp({ "debuggables", bang = true }) end, "Rust debug runnable")
              map("K", function() vim.cmd.RustLsp({ "hover", "actions" }) end, "Rust hover actions")
            end,
          },
          tools = {
            float_win_config = { border = "rounded" },
          },
        }
      end
    end,
  },

  -- Crate version display in Cargo.toml
  {
    "saecki/crates.nvim",
    event = { "BufRead Cargo.toml" },
    opts = {
      completion = { crates = { enabled = true } },
      lsp = { enabled = true, actions = true, completion = true, hover = true },
    },
  },
}
