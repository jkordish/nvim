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
      dim = {
        enabled = true,
        scope = { min_size = 5, max_size = 20, siblings = true },
      },
      input = { enabled = false },     -- dressing.nvim handles vim.ui.input
      image = {
        enabled = true,                -- PNG inline rendering via Ghostty kitty protocol
        formats = { "png", "jpg", "jpeg", "gif", "bmp", "webp", "avif", "svg" },
        doc = { inline = true, max_width = 80, max_height = 40 },
        convert = { magick = { "-density", "200" } },
        -- Disable formats that need extra tools we don't have installed:
        math = { enabled = false },    -- needs tectonic/pdflatex
        diagram = { enabled = false }, -- mermaid needs mmdc
        pdf = { enabled = false },     -- needs ghostscript
      },
      notifier = { enabled = false },  -- using nvim-notify
      picker = { enabled = false },    -- using telescope
      dashboard = {
        enabled = true,
        -- A calm dashboard: a wordmark, a time-aware greeting, and only the
        -- three actions you actually open nvim to do. Recent files and the
        -- git pane appear underneath, quietly. No version chest-thumping.
        preset = {
          -- Newer snacks requires preset.header to be a string, not a function
          -- (format_field passes it through `"%s":format()`, then block() does
          -- `text[1]:find(...)` which crashes on functions). The dynamic
          -- greeting now lives in a custom function-section below — same look,
          -- works on the current snacks API.
          header = "",
          keys = {
            { icon = "  ", key = "f", desc = "find a file",        action = ":Telescope find_files" },
            { icon = "  ", key = "g", desc = "grep the project",   action = ":Telescope live_grep" },
            { icon = "  ", key = "r", desc = "pick up where I was", action = function() require("persistence").load() end },
            -- separator-style empty slot, then quieter secondary actions
            { icon = " ◇ ", key = "n", desc = "new buffer",         action = ":ene | startinsert" },
            { icon = " ◇ ", key = "c", desc = "edit config",        action = ":e $MYVIMRC" },
            { icon = " ◇ ", key = "q", desc = "quit",               action = ":qa" },
          },
        },
        sections = {
          -- Custom dynamic greeting — replaces the old preset.header function.
          -- A function-section returns text on every dashboard open, so the
          -- greeting + username can stay dynamic (time-of-day aware).
          function()
            local greet, user
            local ok, brand = pcall(require, "user.brand")
            greet = (ok and brand.greeting and brand.greeting()) or "welcome back"
            user = (vim.env.USER or ""):match("^[^.]+") or ""
            return {
              align = "center",
              padding = 1,
              text = table.concat({
                "",
                "◆  nvim",
                "",
                greet .. (user ~= "" and (", " .. user) or "") .. ".",
                "",
              }, "\n"),
            }
          end,
          { section = "keys", gap = 1, padding = 1 },
          { section = "recent_files", icon = "  ", title = "recent", indent = 4, padding = { 1, 1 }, limit = 5 },
          { pane = 2, icon = "  ", title = "git", section = "terminal",
            enabled = function() return Snacks.git.get_root() ~= nil end,
            cmd = "git status --short --branch", height = 4, padding = 1, ttl = 5 * 60, indent = 3,
          },
          { pane = 2, icon = "  ", title = "recent commits", section = "terminal",
            enabled = function() return Snacks.git.get_root() ~= nil end,
            cmd = "git --no-pager log --pretty=format:'%C(magenta)%h%C(white) %an %C(blue)%ar  %C(reset)%s' -4", height = 5, padding = 1, ttl = 5 * 60, indent = 3,
          },
          -- intentionally omit "startup time" — premium software doesn't brag
        },
        formats = {
          key = { "[%s]", hl = "BrandAccent" },
        },
      },
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
    -- After Snacks loads, patch its global metatable's __index so it only
    -- triggers require() for *string* keys. Without this, hydra.nvim's
    -- `vim.tbl_deep_extend('force', getfenv(), {...})` recurses into the
    -- Snacks global, calls islist(Snacks) which accesses Snacks[1], which
    -- the autoloader interprets as `require('snacks.1')` and crashes.
    config = function(_, opts)
      require("snacks").setup(opts)
      local mt = getmetatable(_G.Snacks)
      if mt and type(mt.__index) == "function" then
        local orig = mt.__index
        mt.__index = function(t, k)
          if type(k) ~= "string" then return nil end
          return orig(t, k)
        end
      end
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

  -- codesnap REMOVED — used twice in 6 months. macOS screenshot tools and
  -- carbon.now.sh cover the same need without a rust build dependency.

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
