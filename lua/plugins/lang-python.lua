return {
  -- Detect and pick virtualenvs (venv/poetry/pyenv/conda/pipenv). Sets
  -- VIRTUAL_ENV and reroutes pyright/ruff at the project's python.
  {
    "linux-cultist/venv-selector.nvim",
    branch = "regexp",
    ft = "python",
    dependencies = {
      "neovim/nvim-lspconfig",
      "nvim-telescope/telescope.nvim",
      "mfussenegger/nvim-dap-python",
    },
    cmd = { "VenvSelect", "VenvSelectCached" },
    keys = {
      { "<leader>cv", "<cmd>VenvSelect<CR>", desc = "Select venv" },
    },
    opts = {
      auto_refresh = false,
      search_venv_managers = true,
      search_workspace = true,
      dap_enabled = true,
      name = { "venv", ".venv", "env", ".env" },
    },
  },

  -- Python DAP via debugpy from Mason
  {
    "mfussenegger/nvim-dap-python",
    ft = "python",
    dependencies = { "mfussenegger/nvim-dap", "mason-org/mason.nvim" },
    config = function()
      local mason_path = vim.fn.stdpath("data") .. "/mason"
      local py = mason_path .. "/packages/debugpy/venv/bin/python"
      if vim.fn.executable(py) == 1 then
        require("dap-python").setup(py)
      else
        require("dap-python").setup("python3")
      end
    end,
    keys = {
      { "<leader>dpt", function() require("dap-python").test_method() end, desc = "Debug python test (method)" },
      { "<leader>dpc", function() require("dap-python").test_class() end, desc = "Debug python test (class)" },
      { "<leader>dps", function() require("dap-python").debug_selection() end, mode = "v", desc = "Debug python selection" },
    },
  },

  -- Neotest with python adapter for inline test running
  {
    "nvim-neotest/neotest",
    ft = { "python", "go", "rust" },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/nvim-nio",
      "nvim-neotest/neotest-python",
      "nvim-neotest/neotest-go",
      "rouge8/neotest-rust",
    },
    opts = function()
      return {
        adapters = {
          require("neotest-python")({ dap = { justMyCode = false }, runner = "pytest" }),
          require("neotest-go"),
          require("neotest-rust"),
        },
        status = { virtual_text = true },
        output = { open_on_run = true },
        icons = { running_animated = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" } },
      }
    end,
    keys = {
      { "<leader>tn", function() require("neotest").run.run() end, desc = "Test nearest" },
      { "<leader>tN", function() require("neotest").run.run(vim.fn.expand("%")) end, desc = "Test file" },
      { "<leader>ts", function() require("neotest").summary.toggle() end, desc = "Test summary" },
      { "<leader>to", function() require("neotest").output.open({ enter = true, auto_close = true }) end, desc = "Test output" },
      { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Test panel" },
      { "<leader>tS", function() require("neotest").run.stop() end, desc = "Test stop" },
      { "<leader>td", function() require("neotest").run.run({ strategy = "dap" }) end, desc = "Debug nearest test" },
    },
  },
}
