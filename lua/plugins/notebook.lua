-- Notebook stack is opt-in: only activates when jupyter_client + pynvim
-- python modules are importable. Install via:
--   pip install --user pynvim jupyter_client cairosvg pnglatex plotly kaleido pyperclip nbformat
-- then restart nvim. Until then these plugins stay dormant — no errors.
local has_jupyter = vim.fn.executable("python3") == 1
  and vim.fn.system("python3 -c 'import jupyter_client' 2>/dev/null; echo $?"):match("^0") ~= nil

return {
  {
    "quarto-dev/quarto-nvim",
    cond = has_jupyter,
    ft = { "quarto" },
    dependencies = {
      "jmbuhr/otter.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      lspFeatures = {
        languages = { "r", "python", "julia", "bash", "html", "lua" },
        chunks = "all",
        diagnostics = { enabled = true, triggers = { "BufWritePost" } },
        completion = { enabled = true },
      },
      codeRunner = {
        enabled = true,
        default_method = "molten",
        ft_runners = { python = "molten", julia = "molten", r = "molten" },
      },
    },
    keys = {
      { "<leader>Qp", function() require("quarto").quartoPreview() end, desc = "Quarto preview" },
      { "<leader>Qq", function() require("quarto").quartoClosePreview() end, desc = "Quarto stop preview" },
      { "<leader>Qa", "<cmd>QuartoActivate<CR>",                 desc = "Quarto activate" },
      { "<leader>Qh", "<cmd>QuartoHelp<CR>",                     desc = "Quarto help" },
      { "<leader>Qe", "<cmd>QuartoSendAbove<CR>",                desc = "Run above (incl current)" },
      { "<leader>QE", "<cmd>QuartoSendAll<CR>",                  desc = "Run all cells" },
      { "<leader>Qr", "<cmd>QuartoSendBelow<CR>",                desc = "Run from cursor" },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Molten — Jupyter kernel client; renders text, plots, images in nvim.
  -- Pairs with quarto for cell-based execution.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "benlubas/molten-nvim",
    cond = has_jupyter,
    version = "^1.0.0",
    ft = { "quarto" },
    dependencies = {},
    build = ":UpdateRemotePlugins",
    init = function()
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_output_win_max_height = 20
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_wrap_output = true
      vim.g.molten_use_border_highlights = true
    end,
    keys = {
      { "<leader>Ji", ":MoltenInit<CR>",                 desc = "Molten init" },
      { "<leader>Je", ":MoltenEvaluateOperator<CR>",     desc = "Eval operator" },
      { "<leader>Jl", ":MoltenEvaluateLine<CR>",         desc = "Eval line" },
      { "<leader>Jc", ":MoltenReevaluateCell<CR>",       desc = "Re-eval cell" },
      { "<leader>Jr", ":MoltenEvaluateVisual<CR>gv",     mode = "v", desc = "Eval visual" },
      { "<leader>Jd", ":MoltenDelete<CR>",               desc = "Delete output" },
      { "<leader>Jh", ":MoltenHideOutput<CR>",           desc = "Hide output" },
      { "<leader>Jo", ":noautocmd MoltenEnterOutput<CR>", desc = "Enter output window" },
    },
  },

  -- Jupyter notebook (.ipynb) <-> .py sync via jupytext.
  {
    "GCBallesteros/jupytext.nvim",
    cond = has_jupyter,
    ft = { "ipynb" },
    config = true,
    opts = {
      style = "markdown",
      output_extension = "md",
      force_ft = "markdown",
    },
  },
}
