return {
  { "nvim-tree/nvim-web-devicons", lazy = true },
  { "MunifTanjim/nui.nvim", lazy = true },
  { "nvim-lua/plenary.nvim", lazy = true },

  {
    "rcarriga/nvim-notify",
    event = "VeryLazy",
    opts = {
      timeout = 2500,
      max_height = function() return math.floor(vim.o.lines * 0.75) end,
      max_width = function() return math.floor(vim.o.columns * 0.5) end,
      stages = "fade",
      render = "compact",
    },
    init = function() vim.notify = require("notify") end,
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

      -- Copilot status (uses copilot.lua api)
      local copilot = {
        function()
          local ok, api = pcall(require, "copilot.api")
          if not ok then return "" end
          local status = api.status.data
          if status.status == "InProgress" then return "  " end
          if status.status == "Warning" then return "  " end
          return "  "
        end,
        color = function()
          local ok, api = pcall(require, "copilot.api")
          if not ok then return { fg = colors.overlay0 } end
          local s = api.status.data.status
          if s == "Warning" then return { fg = colors.red } end
          if s == "InProgress" then return { fg = colors.yellow } end
          return { fg = colors.green }
        end,
      }

      -- Indent mode (spaces:N | tab:N)
      local indent = {
        function()
          local et = vim.bo.expandtab
          local sw = vim.bo.shiftwidth
          return (et and "" or "󰌒 ") .. (et and "sp:" or "tab:") .. sw
        end,
        color = { fg = colors.overlay1 },
      }

      -- File size
      local filesize = {
        function()
          local f = vim.api.nvim_buf_get_name(0)
          if f == "" then return "" end
          local ok, stat = pcall(vim.uv.fs_stat, f)
          if not ok or not stat then return "" end
          local b = stat.size
          if b < 1024 then return b .. "B" end
          if b < 1024 * 1024 then return string.format("%.1fK", b / 1024) end
          return string.format("%.1fM", b / 1024 / 1024)
        end,
        color = { fg = colors.overlay1 },
      }

      -- Autoformat indicator
      local autoformat = {
        function()
          return (vim.g.disable_autoformat or vim.b.disable_autoformat) and "  fmt-off" or ""
        end,
        color = { fg = colors.peach, gui = "italic" },
      }

      -- TS active indicator
      local treesitter = {
        function()
          return vim.b.ts_highlight and "  TS" or ""
        end,
        color = { fg = colors.green },
      }

      -- Pomodoro timer (epwalsh/pomo.nvim)
      local pomo_timer = {
        function()
          local ok, pomo = pcall(require, "pomo")
          if not ok then return "" end
          local timer = pomo.get_first_to_finish()
          if timer == nil then return "" end
          return string.format("  %s %s", timer:remaining_time_str(), timer.name or "")
        end,
        color = { fg = colors.peach, gui = "bold" },
      }

      -- Overseer task count
      local overseer_tasks = {
        function()
          local ok, ov = pcall(require, "overseer")
          if not ok then return "" end
          local STATUS = ov.constants and ov.constants.STATUS
          if not STATUS then return "" end
          local tasks = ov.list_tasks({ unique = true })
          local running, ok_count, fail = 0, 0, 0
          for _, t in ipairs(tasks) do
            if t.status == STATUS.RUNNING then running = running + 1
            elseif t.status == STATUS.SUCCESS then ok_count = ok_count + 1
            elseif t.status == STATUS.FAILURE then fail = fail + 1 end
          end
          local parts = {}
          if running > 0 then table.insert(parts, "󰑮 " .. running) end
          if fail > 0    then table.insert(parts, " " .. fail) end
          if ok_count > 0 and #parts > 0 then table.insert(parts, " " .. ok_count) end
          return #parts > 0 and (" " .. table.concat(parts, " ")) or ""
        end,
        color = { fg = colors.mauve },
      }

      return {
        options = {
          theme = "catppuccin",
          globalstatus = true,
          component_separators = { left = "│", right = "│" },
          section_separators = { left = "", right = "" },
          disabled_filetypes = {
            statusline = { "dashboard", "alpha", "starter" },
            winbar = { "dashboard", "alpha", "starter", "neo-tree", "Trouble", "trouble" },
          },
          refresh = { statusline = 100 },
        },
        sections = {
          lualine_a = { { "mode", fmt = function(s) return " " .. s end } },
          lualine_b = {
            { "branch", icon = "" },
            { "diff", symbols = { added = " ", modified = " ", removed = " " },
              diff_color = { added = { fg = colors.green }, modified = { fg = colors.yellow }, removed = { fg = colors.red } } },
          },
          lualine_c = {
            { "diagnostics",
              symbols = { error = " ", warn = " ", info = " ", hint = "󰌵 " },
              diagnostics_color = {
                error = { fg = colors.red }, warn = { fg = colors.yellow },
                info = { fg = colors.sky }, hint = { fg = colors.teal },
              } },
            { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
            { "filename", path = 1, symbols = { modified = "  ", readonly = " ", unnamed = "[No Name]" } },
            macro,
            search,
            { function() local ok, n = pcall(require, "noice"); return ok and n.api.status.command.has() and n.api.status.command.get() or "" end },
          },
          lualine_x = {
            pomo_timer,
            overseer_tasks,
            autoformat,
            copilot,
            lsp,
            treesitter,
            filesize,
            indent,
            { "encoding", color = { fg = colors.overlay1 } },
            { "fileformat", symbols = { unix = "", dos = "", mac = "" }, color = { fg = colors.overlay1 } },
          },
          lualine_y = {
            { "progress", separator = " ", padding = { left = 1, right = 0 } },
            { "location", padding = { left = 0, right = 1 } },
          },
          lualine_z = {
            { function() return " " .. os.date("%R") end },
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
    opts = {
      preset = "modern",
      spec = {
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find/file" },
        { "<leader>g", group = "git" },
        { "<leader>l", group = "lsp" },
        { "<leader>s", group = "search" },
        { "<leader>t", group = "toggle/test" },
        { "<leader>x", group = "diagnostics/quickfix" },
        { "<leader>a", group = "ai" },
        { "<leader><tab>", group = "tab" },
      },
    },
    keys = {
      { "<leader>?", function() require("which-key").show({ global = false }) end, desc = "Buffer keymaps" },
    },
  },

  -- alpha-nvim replaced by snacks.dashboard (configured in extras.lua) — more
  -- modern, integrates with snacks ecosystem, and picks up recent files /
  -- sessions / git status as live sections.
}
