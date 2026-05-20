return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Neogit — magit for nvim. Full git workflow in a buffer.
  -- Stage hunks, commit, push, rebase, log, stash — without leaving nvim.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    keys = {
      { "<leader>gn", "<cmd>Neogit<CR>",                   desc = "Neogit" },
      { "<leader>gN", "<cmd>Neogit kind=floating<CR>",     desc = "Neogit floating" },
      { "<leader>gc", "<cmd>Neogit commit<CR>",            desc = "Neogit commit" },
      { "<leader>gP", "<cmd>Neogit push<CR>",              desc = "Neogit push" },
      { "<leader>gp", "<cmd>Neogit pull<CR>",              desc = "Neogit pull" },
      { "<leader>gl", "<cmd>Neogit log<CR>",               desc = "Neogit log" },
    },
    opts = {
      integrations = { telescope = true, diffview = true },
      graph_style = "unicode",
      commit_editor = { kind = "tab", show_staged_diff = true },
      signs = { hunk = { "", "" }, item = { "", "" }, section = { "", "" } },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Inline merge-conflict resolver.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      default_mappings = true,
      default_commands = true,
      list_opener = "copen",
    },
    keys = {
      { "<leader>gxo", "<Plug>(git-conflict-ours)",       desc = "Conflict: take ours" },
      { "<leader>gxt", "<Plug>(git-conflict-theirs)",     desc = "Conflict: take theirs" },
      { "<leader>gxb", "<Plug>(git-conflict-both)",       desc = "Conflict: take both" },
      { "<leader>gxn", "<Plug>(git-conflict-none)",       desc = "Conflict: take none" },
      { "<leader>gx]", "<Plug>(git-conflict-next-conflict)", desc = "Conflict: next" },
      { "<leader>gx[", "<Plug>(git-conflict-prev-conflict)", desc = "Conflict: prev" },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- GitHub Actions panel — list workflows, view runs, tail logs.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "topaxi/gh-actions.nvim",
    cmd = { "GhActions" },
    keys = {
      { "<leader>gA", "<cmd>GhActions<CR>", desc = "GitHub Actions" },
    },
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
    build = "make",
    opts = {},
  },
}
