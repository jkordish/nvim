return {
  -- All-in-one quality-of-life from folke. Only enabling modules that don't
  -- collide with what's already wired (notify/dashboard/picker stay separate).
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      quickfile = { enabled = true },
      statuscolumn = { enabled = true, left = { "mark", "sign" }, right = { "fold", "git" } },
      words = { enabled = true, debounce = 200 },
      animate = { enabled = true, duration = 20, easing = "linear", fps = 60 },
      scroll = { enabled = true, animate = { duration = { step = 15, total = 200 }, easing = "linear" } },
      indent = {
        enabled = true,
        animate = { enabled = true, style = "out", easing = "linear", duration = { step = 20, total = 500 } },
        scope = { enabled = true, animate = { enabled = true } },
      },
      scratch = { enabled = true },
      gitbrowse = { enabled = true },
      lazygit = { enabled = true },
      terminal = { enabled = true },
      zen = { enabled = true, toggles = { dim = true, git_signs = false, mini_diff_signs = false } },
      dim = { enabled = true },
      input = { enabled = true },
      image = { enabled = true },
      notifier = { enabled = false }, -- using nvim-notify
      dashboard = { enabled = false }, -- using alpha-nvim
      picker = { enabled = false },    -- using telescope
    },
    keys = {
      { "<leader>.",  function() Snacks.scratch() end, desc = "Scratch buffer" },
      { "<leader>S",  function() Snacks.scratch.select() end, desc = "Select scratch" },
      { "<leader>z",  function() Snacks.zen() end, desc = "Zen mode" },
      { "<leader>Z",  function() Snacks.zen.zoom() end, desc = "Zoom (zen+max)" },
      { "<leader>gB", function() Snacks.gitbrowse() end, mode = { "n", "v" }, desc = "Browse on remote (GitHub/etc)" },
      { "<leader>un", function() Snacks.notifier.hide() end, desc = "Dismiss notifications" },
      { "]]",         function() Snacks.words.jump(vim.v.count1) end, desc = "Next reference" },
      { "[[",         function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev reference" },
    },
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          _G.dd = function(...) Snacks.debug.inspect(...) end
          _G.bt = function() Snacks.debug.backtrace() end
          vim.print = _G.dd
        end,
      })
    end,
  },

  -- One-key bookmarked-file jumps. Press <leader>1..4 to teleport.
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = function()
      local h = function() return require("harpoon") end
      return {
        { "<leader>H", function() h():list():add() end, desc = "Harpoon add" },
        { "<leader>h", function() h().ui:toggle_quick_menu(h():list()) end, desc = "Harpoon menu" },
        { "<leader>1", function() h():list():select(1) end, desc = "Harpoon 1" },
        { "<leader>2", function() h():list():select(2) end, desc = "Harpoon 2" },
        { "<leader>3", function() h():list():select(3) end, desc = "Harpoon 3" },
        { "<leader>4", function() h():list():select(4) end, desc = "Harpoon 4" },
        { "<M-S-P>",   function() h():list():prev() end, desc = "Harpoon prev" },
        { "<M-S-N>",   function() h():list():next() end, desc = "Harpoon next" },
      }
    end,
    config = function() require("harpoon"):setup({ settings = { save_on_toggle = true, sync_on_ui_close = true } }) end,
  },

  -- Silky-smooth animated cursor motion.
  {
    "sphamba/smear-cursor.nvim",
    event = "VeryLazy",
    opts = {
      stiffness = 0.8,
      trailing_stiffness = 0.5,
      distance_stop_animating = 0.5,
      hide_target_hack = false,
      legacy_computing_symbols_support = false,
    },
  },

  -- Pick a window with a single keypress (used for "send to window" flows).
  {
    "s1n7ax/nvim-window-picker",
    name = "window-picker",
    event = "VeryLazy",
    version = "2.*",
    opts = {
      hint = "floating-big-letter",
      filter_rules = {
        include_current_win = false,
        autoselect_one = true,
        bo = {
          filetype = { "neo-tree", "neo-tree-popup", "notify", "snacks_notif" },
          buftype = { "terminal", "quickfix" },
        },
      },
    },
    keys = {
      { "<leader>wp", function()
          local p = require("window-picker").pick_window()
          if p then vim.api.nvim_set_current_win(p) end
        end, desc = "Pick window" },
      { "<leader>ws", function()
          local p = require("window-picker").pick_window()
          if not p then return end
          local cur = vim.api.nvim_get_current_win()
          local cb, pb = vim.api.nvim_win_get_buf(cur), vim.api.nvim_win_get_buf(p)
          vim.api.nvim_win_set_buf(cur, pb); vim.api.nvim_win_set_buf(p, cb)
        end, desc = "Swap window" },
    },
  },

  -- High-contrast outline view of symbols (LSP/Treesitter).
  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen" },
    keys = {
      { "<leader>cO", "<cmd>AerialToggle!<CR>", desc = "Outline" },
    },
    opts = {
      backends = { "lsp", "treesitter", "markdown", "man" },
      layout = { default_direction = "right", min_width = 28 },
      attach_mode = "global",
      show_guides = true,
      filter_kind = false,
    },
  },

  -- Show full breadcrumb at top of file (replaces in-statusline path for nav).
  {
    "Bekaboo/dropbar.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-telescope/telescope-fzf-native.nvim" },
    keys = {
      { "<leader>cp", function() require("dropbar.api").pick() end, desc = "Pick breadcrumb" },
    },
  },

  -- ASCII screenshots of selected code (great for blog posts / Slack).
  {
    "mistricky/codesnap.nvim",
    build = "make",
    cmd = { "CodeSnap", "CodeSnapSave", "CodeSnapHighlight", "CodeSnapASCII" },
    keys = {
      { "<leader>cy", "<cmd>CodeSnap<CR>", mode = "x", desc = "Snap to clipboard" },
      { "<leader>cY", "<cmd>CodeSnapSave<CR>", mode = "x", desc = "Snap to file" },
    },
    opts = {
      save_path = "~/Pictures/codesnap",
      has_breadcrumbs = true,
      bg_theme = "bamboo",
      watermark = "",
    },
  },

  -- Treesitter rainbow delimiters — match nested braces by color.
  {
    "HiPhish/rainbow-delimiters.nvim",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local rd = require("rainbow-delimiters")
      vim.g.rainbow_delimiters = {
        strategy = {
          [""] = rd.strategy["global"],
          vim = rd.strategy["local"],
        },
        query = { [""] = "rainbow-delimiters", lua = "rainbow-blocks" },
        highlight = {
          "RainbowDelimiterRed", "RainbowDelimiterYellow", "RainbowDelimiterBlue",
          "RainbowDelimiterOrange", "RainbowDelimiterGreen", "RainbowDelimiterViolet", "RainbowDelimiterCyan",
        },
      }
    end,
  },
}
