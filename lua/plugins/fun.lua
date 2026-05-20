return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Matrix rain + other animations made from your own code.
  -- :CellularAutomaton make_it_rain  |  game_of_life
  -- ─────────────────────────────────────────────────────────────────────
  {
    "eandrju/cellular-automaton.nvim",
    cmd = "CellularAutomaton",
    keys = {
      { "<leader>Xr", "<cmd>CellularAutomaton make_it_rain<CR>", desc = "Make it rain 🌧" },
      { "<leader>Xg", "<cmd>CellularAutomaton game_of_life<CR>", desc = "Game of life" },
      { "<leader>Xs", "<cmd>CellularAutomaton scramble<CR>",     desc = "Scramble code" },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Minimap on the right.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "echasnovski/mini.map",
    event = "VeryLazy",
    keys = {
      { "<leader>tm", function() require("mini.map").toggle() end, desc = "Toggle minimap" },
      { "<leader>tM", function() require("mini.map").toggle_focus() end, desc = "Focus minimap" },
    },
    config = function()
      local map = require("mini.map")
      map.setup({
        integrations = {
          map.gen_integration.builtin_search(),
          map.gen_integration.diff(),
          map.gen_integration.diagnostic({
            error = "DiagnosticFloatingError",
            warn  = "DiagnosticFloatingWarn",
            info  = "DiagnosticFloatingInfo",
            hint  = "DiagnosticFloatingHint",
          }),
        },
        symbols = {
          encode = map.gen_encode_symbols.dot("3x2"),
          scroll_line = "█",
          scroll_view = "┃",
        },
        window = { side = "right", width = 10, winblend = 25, show_integration_count = false },
      })
    end,
  },

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
      execution_message = { message = function() return "" end, dim = 0.2, cleaning_interval = 1500 },
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
