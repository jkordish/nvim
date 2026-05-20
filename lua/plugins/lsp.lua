return {
  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    build = ":MasonUpdate",
    opts = { ui = { border = "rounded" } },
  },

  {
    "mason-org/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = {
        "lua_ls",
        "pyright",
        "ruff",
        "vtsls",
        "eslint",
        "gopls",
        -- rust_analyzer owned by rustaceanvim, do not install via mason-lspconfig
        "bashls",
        "jsonls",
        "yamlls",
        "marksman",
        "taplo",
        "dockerls",
        "emmet_language_server",
        "tailwindcss",
        "ltex",
      },
      automatic_installation = true,
    },
  },

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    event = "VeryLazy",
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      ensure_installed = {
        "stylua", "shfmt", "prettierd", "black", "isort", "goimports", "shellcheck",
        "debugpy",        -- python DAP
        "codelldb",       -- rust/c/c++ DAP
        "delve",          -- go DAP
        "js-debug-adapter",
        "hadolint", "markdownlint",
      },
      auto_update = false,
      run_on_start = true,
    },
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
      "mason-org/mason-lspconfig.nvim",
      "saghen/blink.cmp",
      "b0o/schemastore.nvim",
    },
    config = function()
      -- Diagnostics UI
      vim.diagnostic.config({
        severity_sort = true,
        float = { border = "rounded", source = "if_many" },
        underline = { severity = vim.diagnostic.severity.ERROR },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN]  = " ",
            [vim.diagnostic.severity.INFO]  = " ",
            [vim.diagnostic.severity.HINT]  = " ",
          },
        },
        virtual_text = {
          spacing = 4,
          source = "if_many",
          prefix = "●",
        },
      })

      -- Hover/sig help borders via nvim 0.12 global window border
      if vim.fn.has("nvim-0.11") == 1 then
        vim.o.winborder = "rounded"
      end

      -- On-attach: per-buffer keymaps + features
      local on_attach = function(client, bufnr)
        local function nmap(lhs, rhs, desc)
          vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
        end

        nmap("gd", function() require("telescope.builtin").lsp_definitions({ reuse_win = true }) end, "Goto definition")
        nmap("gD", vim.lsp.buf.declaration, "Goto declaration")
        nmap("gr", function() require("telescope.builtin").lsp_references() end, "References")
        nmap("gI", function() require("telescope.builtin").lsp_implementations({ reuse_win = true }) end, "Implementations")
        nmap("gy", function() require("telescope.builtin").lsp_type_definitions({ reuse_win = true }) end, "Type definition")
        nmap("K", vim.lsp.buf.hover, "Hover")
        nmap("gK", vim.lsp.buf.signature_help, "Signature help")
        vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, { buffer = bufnr, desc = "Signature help" })
        nmap("<leader>cr", vim.lsp.buf.rename, "Rename")
        nmap("<leader>ca", vim.lsp.buf.code_action, "Code action")
        vim.keymap.set("x", "<leader>ca", vim.lsp.buf.code_action, { buffer = bufnr, desc = "Code action" })
        nmap("<leader>cs", function() require("telescope.builtin").lsp_document_symbols() end, "Document symbols")
        nmap("<leader>cS", function() require("telescope.builtin").lsp_dynamic_workspace_symbols() end, "Workspace symbols")

        if client:supports_method("textDocument/inlayHint") then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
          nmap("<leader>th", function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
          end, "Toggle inlay hints")
        end

        if client:supports_method("textDocument/documentHighlight") then
          local grp = vim.api.nvim_create_augroup("user_lsp_highlight_" .. bufnr, { clear = true })
          vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
            group = grp, buffer = bufnr, callback = vim.lsp.buf.document_highlight,
          })
          vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
            group = grp, buffer = bufnr, callback = vim.lsp.buf.clear_references,
          })
        end
      end

      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client then on_attach(client, args.buf) end
        end,
      })

      local capabilities = require("blink.cmp").get_lsp_capabilities()

      -- Per-server settings
      local servers = {
        lua_ls = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
              hint = { enable = true, setType = false, paramType = true, paramName = "Disable", semicolon = "Disable", arrayIndex = "Disable" },
              completion = { callSnippet = "Replace" },
              diagnostics = { globals = { "vim" } },
            },
          },
        },
        pyright = {
          settings = {
            python = {
              analysis = {
                typeCheckingMode = "standard",
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticMode = "openFilesOnly",
              },
            },
          },
        },
        ruff = {
          init_options = {
            settings = {
              args = {},
            },
          },
        },
        vtsls = {
          settings = {
            typescript = {
              updateImportsOnFileMove = { enabled = "always" },
              suggest = { completeFunctionCalls = true },
              inlayHints = {
                parameterNames = { enabled = "literals" },
                parameterTypes = { enabled = true },
                variableTypes = { enabled = false },
                propertyDeclarationTypes = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
                enumMemberValues = { enabled = true },
              },
            },
            javascript = {
              inlayHints = {
                parameterNames = { enabled = "all" },
                parameterTypes = { enabled = true },
                variableTypes = { enabled = true },
                propertyDeclarationTypes = { enabled = true },
                functionLikeReturnTypes = { enabled = true },
                enumMemberValues = { enabled = true },
              },
            },
          },
        },
        eslint = {
          settings = { workingDirectories = { mode = "auto" } },
        },
        gopls = {
          settings = {
            gopls = {
              gofumpt = true,
              codelenses = { gc_details = false, generate = true, regenerate_cgo = true, test = true, tidy = true, upgrade_dependency = true, vendor = true },
              hints = { assignVariableTypes = true, compositeLiteralFields = true, compositeLiteralTypes = true, constantValues = true, functionTypeParameters = true, parameterNames = true, rangeVariableTypes = true },
              analyses = { fieldalignment = true, nilness = true, unusedparams = true, unusedwrite = true, useany = true },
              usePlaceholders = true,
              completeUnimported = true,
              staticcheck = true,
              directoryFilters = { "-.git", "-.vscode", "-.idea", "-node_modules" },
              semanticTokens = true,
            },
          },
        },
        -- rust_analyzer is managed by rustaceanvim (see lang-rust.lua)
        yamlls = {
          settings = {
            yaml = {
              keyOrdering = false,
              schemaStore = { enable = false, url = "" },
              schemas = (function()
                local ok, ss = pcall(require, "schemastore")
                return ok and ss.yaml.schemas() or {}
              end)(),
            },
          },
        },
        jsonls = {
          settings = {
            json = {
              schemas = (function()
                local ok, ss = pcall(require, "schemastore")
                return ok and ss.json.schemas() or {}
              end)(),
              validate = { enable = true },
            },
          },
        },
        bashls = {},
        marksman = {},
        taplo = {},
        dockerls = {},
        tailwindcss = {
          filetypes_exclude = { "markdown" },
          filetypes_include = {},
        },
        emmet_language_server = {
          filetypes = { "css", "eruby", "html", "javascript", "javascriptreact", "less", "sass", "scss", "pug", "typescriptreact", "vue", "svelte", "astro" },
        },
        -- ltex is wired in writing.lua so it only loads for prose buffers
      }

      for name, cfg in pairs(servers) do
        cfg.capabilities = vim.tbl_deep_extend("force", {}, capabilities, cfg.capabilities or {})
        vim.lsp.config(name, cfg)
        vim.lsp.enable(name)
      end
    end,
  },

  {
    "b0o/schemastore.nvim",
    lazy = true,
    version = false,
  },

  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true, lsp_format = "fallback" }) end, mode = { "n", "v" }, desc = "Format" },
      { "<leader>tF", function()
          vim.g.disable_autoformat = not vim.g.disable_autoformat
          vim.notify("Autoformat " .. (vim.g.disable_autoformat and "OFF" or "ON"))
        end, desc = "Toggle autoformat" },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format", "ruff_organize_imports" },
        javascript = { "prettierd", "prettier", stop_after_first = true },
        typescript = { "prettierd", "prettier", stop_after_first = true },
        javascriptreact = { "prettierd", "prettier", stop_after_first = true },
        typescriptreact = { "prettierd", "prettier", stop_after_first = true },
        json = { "prettierd", "prettier", stop_after_first = true },
        jsonc = { "prettierd", "prettier", stop_after_first = true },
        yaml = { "prettierd", "prettier", stop_after_first = true },
        markdown = { "prettierd", "prettier", stop_after_first = true },
        html = { "prettierd", "prettier", stop_after_first = true },
        css = { "prettierd", "prettier", stop_after_first = true },
        go = { "goimports", "gofmt" },
        rust = { "rustfmt", lsp_format = "fallback" },
        sh = { "shfmt" },
        bash = { "shfmt" },
      },
      format_on_save = function(bufnr)
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then return end
        return { timeout_ms = 1500, lsp_format = "fallback" }
      end,
    },
  },

  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile", "BufWritePost" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        sh = { "shellcheck" },
        bash = { "shellcheck" },
        dockerfile = { "hadolint" },
        markdown = { "markdownlint" },
      }
      local grp = vim.api.nvim_create_augroup("user_lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
        group = grp,
        callback = function() lint.try_lint() end,
      })
    end,
  },
}
