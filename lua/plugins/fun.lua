return {
  -- cellular-automaton REMOVED — `user.matrix` (lua/user/_play/matrix.lua)
  -- and `user.aurora` cover the same novelty surface using extmarks only,
  -- no external plugin.
  --
  -- mini.map REMOVED — visual real estate cost > value. Snacks.scope already
  -- shows scope edges in the gutter; aerial/symtree show outline on demand.

  -- ─────────────────────────────────────────────────────────────────────
  -- Auto-save (silent) — saves on focus loss / leave insert if file has name.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "okuuva/auto-save.nvim",
    cmd = "ASToggle",
    event = { "InsertLeave", "TextChanged" },
    keys = {
      { "<leader>ta", "<cmd>ASToggle<CR>", desc = "Toggle autosave" },
    },
    opts = {
      enabled = false, -- start OFF; toggle with <leader>ta
      -- execution_message removed upstream — silence its complaint
      trigger_events = {
        immediate_save = { "BufLeave", "FocusLost" },
        defer_save = { "InsertLeave", "TextChanged" },
        cancel_deferred_save = { "InsertEnter" },
      },
      debounce_delay = 2000,
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Modicator — color the line number based on Vim mode.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "mawkler/modicator.nvim",
    event = "VeryLazy",
    init = function() vim.o.cursorline = true; vim.o.number = true; vim.o.termguicolors = true end,
    opts = {
      show_warnings = false,
      highlights = { defaults = { bold = true } },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Wakatime-free time tracking inside the editor (local only).
  -- ─────────────────────────────────────────────────────────────────────
  {
    "ptdewey/yarepl-nvim",
    enabled = false, -- placeholder; toggle if you want REPL split for any language
  },
}
