return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Obsidian inside nvim — backlinks, daily notes, templates, search.
  -- Set vault path to your existing Obsidian vault (or any markdown dir).
  -- ─────────────────────────────────────────────────────────────────────
  {
    "epwalsh/obsidian.nvim",
    version = "*",
    ft = "markdown",
    cmd = {
      "ObsidianNew", "ObsidianOpen", "ObsidianQuickSwitch", "ObsidianSearch",
      "ObsidianFollowLink", "ObsidianBacklinks", "ObsidianTags", "ObsidianToday",
      "ObsidianYesterday", "ObsidianTomorrow", "ObsidianTemplate", "ObsidianRename",
      "ObsidianPasteImg", "ObsidianWorkspace",
    },
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
    keys = {
      { "<leader>nn", "<cmd>ObsidianNew<CR>",         desc = "New note" },
      { "<leader>no", "<cmd>ObsidianQuickSwitch<CR>", desc = "Open note" },
      { "<leader>ns", "<cmd>ObsidianSearch<CR>",      desc = "Search notes" },
      { "<leader>nt", "<cmd>ObsidianToday<CR>",       desc = "Today's note" },
      { "<leader>ny", "<cmd>ObsidianYesterday<CR>",   desc = "Yesterday's note" },
      { "<leader>nT", "<cmd>ObsidianTomorrow<CR>",    desc = "Tomorrow's note" },
      { "<leader>nb", "<cmd>ObsidianBacklinks<CR>",   desc = "Backlinks" },
      { "<leader>nf", "<cmd>ObsidianFollowLink<CR>",  desc = "Follow link" },
      { "<leader>ng", "<cmd>ObsidianTags<CR>",        desc = "Tags" },
      { "<leader>nr", "<cmd>ObsidianRename<CR>",      desc = "Rename note" },
      { "<leader>np", "<cmd>ObsidianPasteImg<CR>",    desc = "Paste image" },
    },
    opts = {
      workspaces = {
        {
          name = "personal",
          path = vim.fn.expand("~/notes"),
        },
      },
      notes_subdir = "inbox",
      new_notes_location = "notes_subdir",
      daily_notes = { folder = "daily", date_format = "%Y-%m-%d", template = nil },
      completion = { nvim_cmp = false, blink = true, min_chars = 2 },
      ui = { enable = false }, -- render-markdown/headlines handle this
      attachments = { img_folder = "assets" },
      picker = { name = "telescope.nvim" },
      mappings = {
        ["gf"] = {
          action = function() return require("obsidian").util.gf_passthrough() end,
          opts = { noremap = false, expr = true, buffer = true },
        },
        ["<leader>nx"] = {
          action = function() return require("obsidian").util.toggle_checkbox() end,
          opts = { buffer = true, desc = "Toggle checkbox" },
        },
      },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Pomodoro timer that appears in the statusline.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "epwalsh/pomo.nvim",
    version = "*",
    cmd = { "TimerStart", "TimerRepeat", "TimerStop", "TimerHide", "TimerShow" },
    keys = {
      { "<leader>np1", "<cmd>TimerStart 25m focus<CR>",        desc = "Pomo: 25m focus" },
      { "<leader>np2", "<cmd>TimerStart 5m  break<CR>",        desc = "Pomo: 5m break" },
      { "<leader>np3", "<cmd>TimerStart 15m long-break<CR>",   desc = "Pomo: 15m long break" },
      { "<leader>nps", "<cmd>TimerStop<CR>",                   desc = "Pomo: stop" },
      { "<leader>nph", "<cmd>TimerHide<CR>",                   desc = "Pomo: hide" },
      { "<leader>npS", "<cmd>TimerShow<CR>",                   desc = "Pomo: show" },
    },
    dependencies = { "rcarriga/nvim-notify" },
    opts = {
      sessions = {
        pomodoro = {
          { name = "focus", duration = "25m" },
          { name = "break", duration = "5m" },
          { name = "focus", duration = "25m" },
          { name = "break", duration = "5m" },
          { name = "focus", duration = "25m" },
          { name = "break", duration = "5m" },
          { name = "focus", duration = "25m" },
          { name = "long-break", duration = "15m" },
        },
      },
      notifiers = {
        { name = "Default", opts = { sticky = true, title_icon = " ", text_icon = "󰄉 " } },
        { name = "System" },
      },
    },
  },
}
