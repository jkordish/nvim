return {
  { "nvim-tree/nvim-web-devicons", lazy = true },
  { "MunifTanjim/nui.nvim", lazy = true },
  { "nvim-lua/plenary.nvim", lazy = true },

  {
    "rcarriga/nvim-notify",
    event = "VeryLazy",
    opts = {
      timeout = 2200,
      max_height = function() return math.floor(vim.o.lines * 0.75) end,
      max_width  = function() return math.min(80, math.floor(vim.o.columns * 0.4)) end,
      stages     = "slide",          -- subtle horizontal motion, premium-er than fade
      render     = "wrapped-default", -- shows title in a chip on left, multi-line body
      top_down   = false,             -- newest at bottom-right — calmer
      background_colour = "#1e1e2e",
      icons = { ERROR = "●", WARN = "●", INFO = "●", DEBUG = "●", TRACE = "●" },
      minimum_width = 28,
      fps = 60,
      level = vim.log.levels.INFO,
    },
    config = function(_, opts)
      local notify = require("notify")
      notify.setup(opts)
      vim.notify = notify
      -- Tint the level colors to match the brand palette
      vim.api.nvim_set_hl(0, "NotifyERRORBorder", { fg = "#f38ba8" })
      vim.api.nvim_set_hl(0, "NotifyWARNBorder",  { fg = "#f9e2af" })
      vim.api.nvim_set_hl(0, "NotifyINFOBorder",  { fg = "#cba6f7" })  -- brand accent
      vim.api.nvim_set_hl(0, "NotifyDEBUGBorder", { fg = "#7287fd" })
      vim.api.nvim_set_hl(0, "NotifyTRACEBorder", { fg = "#94e2d5" })
      vim.api.nvim_set_hl(0, "NotifyERRORTitle",  { fg = "#f38ba8", bold = true })
      vim.api.nvim_set_hl(0, "NotifyWARNTitle",   { fg = "#f9e2af", bold = true })
      vim.api.nvim_set_hl(0, "NotifyINFOTitle",   { fg = "#cba6f7", bold = true })
      vim.api.nvim_set_hl(0, "NotifyDEBUGTitle",  { fg = "#7287fd", bold = true })
      vim.api.nvim_set_hl(0, "NotifyTRACETitle",  { fg = "#94e2d5", bold = true })
    end,
  },

  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
    opts = {
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
      },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
        inc_rename = false,
        lsp_doc_border = true,
      },
      routes = {
        { filter = { event = "msg_show", any = { { find = "%d+L, %d+B" }, { find = "; after #%d+" }, { find = "; before #%d+" } } }, view = "mini" },
      },
    },
  },

  {
    "stevearc/dressing.nvim",
    event = "VeryLazy",
    opts = {},
  },

  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function()
      local colors = {
        rosewater = "#f5e0dc", flamingo = "#f2cdcd", pink = "#f5c2e7",
        mauve = "#cba6f7", red = "#f38ba8", maroon = "#eba0ac",
        peach = "#fab387", yellow = "#f9e2af", green = "#a6e3a1",
        teal = "#94e2d5", sky = "#89dceb", sapphire = "#74c7ec",
        blue = "#89b4fa", lavender = "#b4befe",
        text = "#cdd6f4", subtext1 = "#bac2de", subtext0 = "#a6adc8",
        overlay2 = "#9399b2", overlay1 = "#7f849c", overlay0 = "#6c7086",
        surface2 = "#585b70", surface1 = "#45475a", surface0 = "#313244",
        base = "#1e1e2e", mantle = "#181825", crust = "#11111b",
      }

      -- Macro recording indicator
      local macro = {
        function()
          local r = vim.fn.reg_recording()
          return r ~= "" and ("󰑊 @" .. r) or ""
        end,
        color = { fg = colors.red, gui = "bold" },
        cond = function() return vim.fn.reg_recording() ~= "" end,
      }

      -- Search results (n of N when /search active)
      local search = {
        function()
          if vim.v.hlsearch == 0 then return "" end
          local ok, s = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 250 })
          if not ok or s.total == 0 then return "" end
          return "  " .. s.current .. "/" .. s.total
        end,
        color = { fg = colors.yellow },
      }

      -- LSP servers attached to current buffer
      local lsp = {
        function()
          local clients = vim.lsp.get_clients({ bufnr = 0 })
          if #clients == 0 then return "" end
          local names = {}
          for _, c in ipairs(clients) do
            if c.name ~= "null-ls" and c.name ~= "copilot" then table.insert(names, c.name) end
          end
          if #names == 0 then return "" end
          return "  " .. table.concat(names, ",")
        end,
        color = { fg = colors.sky },
      }

      -- Autoformat indicator — unique to lualine_x (not in starship).
      local autoformat = {
        function()
          return (vim.g.disable_autoformat or vim.b.disable_autoformat) and "  fmt-off" or ""
        end,
        color = { fg = colors.peach, gui = "italic" },
      }

      -- ─── Starship-style left/right pre-composed segments ───────────────
      -- Filename, filetype icon, jobs, pomo, overseer tasks, and copilot
      -- status all live inside the starship chains now (richer chips, click
      -- handlers, severity coloring). Keeping them here too would just
      -- render two of each.
      local starship_left  = { function() return require("user.starship").left()  end }
      local starship_right = { function() return require("user.starship").right() end }

      return {
        options = {
          theme = "catppuccin-mocha",
          globalstatus = true,
          -- chain() already emits its own powerline wedges between segments;
          -- lualine's component separators would double them up.
          component_separators = { left = "", right = "" },
          section_separators   = { left = "", right = "" },
          disabled_filetypes = {
            statusline = { "dashboard", "alpha", "starter", "snacks_dashboard" },
            winbar = { "dashboard", "alpha", "starter", "neo-tree", "Trouble", "trouble", "snacks_dashboard" },
          },
          -- 250ms = 4fps. Spinner + macro pulse stay smooth enough; async
          -- providers call lualine.refresh() directly when their data lands,
          -- so the timer is just a fallback for purely time-based chips.
          refresh = { statusline = 250 },
        },
        sections = {
          -- A/B emptied — mode now lives inside the starship left chain so the
          -- entire left half is one continuous powerline (no theme-color seam
          -- between the lualine_a mode block and the starship chain).
          lualine_a = {},
          lualine_b = { starship_left },
          -- C: noice cmdline echo only (filename + filetype now in starship.file).
          -- The cmdline can legitimately contain `%` (filename register,
          -- :%s/.../, etc.) which the statusline parser interprets as a
          -- format directive — `% ` triggers `E539`. Escape `%` to `%%`.
          lualine_c = {
            { function()
                local ok, n = pcall(require, "noice")
                local s = ok and n.api.status.command.has() and n.api.status.command.get() or ""
                if type(s) ~= "string" then return "" end
                return (s:gsub("%%", "%%%%"))
            end },
          },
          -- X: autoformat indicator. Jobs/pomo/tasks/copilot moved to starship.
          lualine_x = {
            autoformat,
          },
          -- Y: starship-style right chain (lang version + venv  docker  k8s  aws  battery  time)
          lualine_y = { starship_right },
          -- Z: progress + location
          lualine_z = {
            { "progress", separator = " ", padding = { left = 1, right = 0 } },
            { "location", padding = { left = 0, right = 1 } },
          },
        },
        extensions = { "neo-tree", "lazy", "trouble", "mason", "quickfix", "fugitive", "nvim-dap-ui", "aerial" },
      }
    end,
  },

  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>bp", "<cmd>BufferLineTogglePin<CR>", desc = "Pin buffer" },
      { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<CR>", desc = "Close unpinned" },
    },
    opts = {
      options = {
        diagnostics = "nvim_lsp",
        diagnostics_indicator = function(_, _, diag)
          local icons = { error = " ", warning = " " }
          local s = (diag.error and icons.error .. diag.error or "")
                  .. (diag.warning and " " .. icons.warning .. diag.warning or "")
          return vim.trim(s)
        end,
        always_show_bufferline = true,
        show_buffer_close_icons = true,
        show_close_icon = false,
        separator_style = "slant",
        indicator = { style = "underline" },
        modified_icon = "●",
        buffer_close_icon = "󰅖",
        offsets = {
          { filetype = "neo-tree", text = "  Explorer", highlight = "Directory", text_align = "left", separator = true },
          { filetype = "Avante",   text = "  Avante",   highlight = "PanelHeading", text_align = "center", separator = true },
          { filetype = "dbui",     text = "  Database", highlight = "PanelHeading", text_align = "center", separator = true },
        },
        hover = { enabled = true, delay = 200, reveal = { "close" } },
      },
    },
  },

  -- indent-blankline replaced by snacks.indent (animated, scope-aware)

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = function()
      -- Lazy-load the filter so user.commandeer is available
      local ok, commandeer = pcall(require, "user.commandeer")
      local filter = ok and commandeer.filter or nil
      return {
        preset = "modern",
        filter = filter,
        delay = 350,                     -- snappier than default 1000ms
        notify = false,                  -- silence which-key's own notifications
        sort = { "alphanum", "manual", "local", "order", "group", "mod", "lower", "icase" },
        win = {
          border = "rounded",
          padding = { 1, 2 },
          title = "  ◆  what's available  ",
          title_pos = "left",
          wo = { winblend = 0 },
        },
        layout = { width = { min = 22 }, spacing = 4 },
        keys = { scroll_down = "<c-d>", scroll_up = "<c-u>" },
        -- Group labels — only kept ones still actively used after the cull
        spec = {
          { "<leader>!", group = "cockpit" },
          { "<leader>c", group = "code" },
          { "<leader>g", group = "git" },
          { "<leader>r", group = "REPL" },
          { "<leader>s", group = "search" },
          { "<leader>f", group = "find" },
          { "<leader>t", group = "toggle / test" },
          { "<leader>d", group = "debug" },
          { "<leader>u", group = "utility" },
          { "<leader>W", group = "workspace" },
          { "<leader>T", group = "tasks" },
          { "<leader>O", group = "GitHub (octo)" },
          { "<leader>q", group = "quit / macros" },
          { "<leader><tab>", group = "tabs" },
        },
        -- Style hooks tying back to the brand palette
        icons = {
          breadcrumb = "▸",
          separator  = "·",
          group      = "◆ ",
        },
      }
    end,
    keys = {
      -- Bare <leader>? = show ALL bindings (escape from the context filter)
      { "<leader>?", function() require("user.commandeer").show_all() end, desc = "All bindings (escape filter)" },
    },
    config = function(_, opts)
      require("which-key").setup(opts)
      -- Paint which-key with the brand palette
      vim.api.nvim_set_hl(0, "WhichKey",          { fg = "#cba6f7", bold = true })   -- the key itself
      vim.api.nvim_set_hl(0, "WhichKeyDesc",      { fg = "#cdd6f4" })                -- description
      vim.api.nvim_set_hl(0, "WhichKeyGroup",     { fg = "#7287fd", italic = true }) -- group label
      vim.api.nvim_set_hl(0, "WhichKeySeparator", { fg = "#45475a" })                -- · between cols
      vim.api.nvim_set_hl(0, "WhichKeyTitle",    { fg = "#cba6f7", bold = true })
      vim.api.nvim_set_hl(0, "WhichKeyBorder",   { fg = "#cba6f7" })
    end,
  },

  -- alpha-nvim replaced by snacks.dashboard (configured in extras.lua) — more
  -- modern, integrates with snacks ecosystem, and picks up recent files /
  -- sessions / git status as live sections.
}
