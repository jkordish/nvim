return {
  -- Tasteful animated LSP progress in the bottom-right.
  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {
      progress = {
        display = {
          done_icon = " ",
          progress_icon = { pattern = "dots", period = 1 },
          render_limit = 8,
          done_ttl = 1.5,
        },
        suppress_on_insert = false,
      },
      notification = {
        window = { winblend = 0, border = "rounded", relative = "editor" },
      },
    },
  },

  -- Replaces virtual_text with a pretty floating box near the cursor.
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "VeryLazy",
    priority = 1000,
    config = function()
      require("tiny-inline-diagnostic").setup({
        preset = "modern",
        options = {
          show_source = true,
          multilines = { enabled = true, always_show = false },
          throttle = 20,
          softwrap = 30,
          overflow = { mode = "wrap" },
          break_line = { enabled = false },
          format = function(d) return d.message end,
        },
      })
      -- Disable native virtual_text so the two don't double up
      vim.diagnostic.config({ virtual_text = false })
    end,
  },

  -- Floating filename badge in the top-right of each window with extras:
  -- file icon · path-tail · modified marker · LSP-attached count · line count.
  {
    "b0o/incline.nvim",
    event = "BufReadPost",
    config = function()
      local devicons = require("nvim-web-devicons")
      local function get_diag(bufnr)
        local counts = { 0, 0, 0, 0 } -- error, warn, info, hint
        for _, d in ipairs(vim.diagnostic.get(bufnr)) do
          counts[d.severity] = counts[d.severity] + 1
        end
        return counts
      end
      require("incline").setup({
        window = { margin = { vertical = 0, horizontal = 1 }, padding = 1, placement = { horizontal = "right", vertical = "top" } },
        hide = { cursorline = true },
        render = function(props)
          local fullpath = vim.api.nvim_buf_get_name(props.buf)
          local fname = vim.fn.fnamemodify(fullpath, ":t")
          if fname == "" then fname = "[No Name]" end
          local icon, color = devicons.get_icon_color(fname, nil, { default = true })
          local modified = vim.bo[props.buf].modified
          local clients = vim.lsp.get_clients({ bufnr = props.buf })
          local lsp_count = 0
          for _, c in ipairs(clients) do
            if c.name ~= "copilot" and c.name ~= "null-ls" then lsp_count = lsp_count + 1 end
          end
          local lines = vim.api.nvim_buf_line_count(props.buf)
          local d = get_diag(props.buf)

          local res = {
            { " " }, { icon, guifg = color }, { " " },
            { fname, gui = modified and "bold,italic" or "bold" },
          }
          if modified then table.insert(res, { " ", guifg = "#f38ba8" }) end
          table.insert(res, { "  ", guifg = "#6c7086" })
          if d[1] > 0 then table.insert(res, { ("  %d "):format(d[1]), guifg = "#f38ba8" }) end
          if d[2] > 0 then table.insert(res, { ("  %d "):format(d[2]), guifg = "#f9e2af" }) end
          if lsp_count > 0 then table.insert(res, { ("  %d "):format(lsp_count), guifg = "#89dceb" }) end
          table.insert(res, { ("  %d "):format(lines), guifg = "#a6adc8" })
          return res
        end,
      })
    end,
  },

  -- Scrollbar with diagnostic + git markers.
  {
    "petertriho/nvim-scrollbar",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "lewis6991/gitsigns.nvim" },
    opts = {
      handle = { color = "#45475a" },
      excluded_filetypes = { "prompt", "TelescopePrompt", "noice", "neo-tree", "alpha", "lazy", "mason" },
      handlers = { cursor = true, diagnostic = true, gitsigns = true, search = false, ale = false },
    },
    config = function(_, opts)
      require("scrollbar").setup(opts)
      require("scrollbar.handlers.gitsigns").setup()
    end,
  },

  -- Dim non-focused code (pairs with snacks.zen).
  {
    "folke/twilight.nvim",
    cmd = { "Twilight", "TwilightEnable", "TwilightDisable" },
    keys = {
      { "<leader>tT", "<cmd>Twilight<CR>", desc = "Toggle Twilight" },
    },
    opts = { dimming = { alpha = 0.25 }, context = 10, treesitter = true },
  },

}
