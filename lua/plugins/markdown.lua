return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Inline image rendering via Kitty/Wezterm graphics protocol or ueberzug.
  -- Renders images in markdown buffers, neorg, html, etc.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "3rd/image.nvim",
    ft = { "markdown", "norg", "vimwiki", "html", "css", "javascript", "typescript" },
    dependencies = {
      { "leafo/magick", lazy = true }, -- luarock; install with `luarocks --local install magick` if not present
    },
    opts = {
      backend = "kitty",
      processor = "magick_cli",
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
          filetypes = { "markdown", "vimwiki" },
        },
        neorg = { enabled = true, filetypes = { "norg" } },
        html  = { enabled = false },
        css   = { enabled = false },
      },
      max_width = nil,
      max_height = nil,
      max_width_window_percentage = nil,
      max_height_window_percentage = 50,
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Paste clipboard images into markdown — auto-saves the image and
  -- inserts the link. Crucial for note-taking and prompting Avante.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "HakonHarnes/img-clip.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>cP", function() require("img-clip").paste_image() end, desc = "Paste image from clipboard" },
    },
    opts = {
      default = {
        embed_image_as_base64 = false,
        prompt_for_file_name = false,
        drag_and_drop = { insert_mode = true },
        use_absolute_path = false,
        relative_to_current_file = true,
      },
      filetypes = {
        markdown = { url_encode_path = true, template = "![$CURSOR]($FILE_PATH)" },
        Avante   = { template = "<img src=\"$FILE_PATH\" />" },
      },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Pretty markdown headers with colored backgrounds.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "lukas-reineke/headlines.nvim",
    ft = { "markdown", "norg", "rmd", "org" },
    dependencies = "nvim-treesitter/nvim-treesitter",
    opts = function()
      local o = {}
      for _, ft in ipairs({ "markdown", "rmd", "norg", "org" }) do
        o[ft] = {
          headline_highlights = { "Headline1", "Headline2", "Headline3", "Headline4", "Headline5", "Headline6" },
          bullets = { "◉", "○", "✸", "✿" },
          codeblock_highlight = "CodeBlock",
          dash_highlight = "Dash",
          dash_string = "─",
          quote_highlight = "Quote",
          quote_string = "┃",
          fat_headlines = true,
          fat_headline_upper_string = "▃",
          fat_headline_lower_string = "🬂",
        }
      end
      return o
    end,
    config = function(_, opts)
      -- Catppuccin-flavored header backgrounds
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("user_headlines", { clear = true }),
        callback = function()
          local set = vim.api.nvim_set_hl
          set(0, "Headline1", { bg = "#3b4261", fg = "#f5c2e7" })
          set(0, "Headline2", { bg = "#2e3344", fg = "#cba6f7" })
          set(0, "Headline3", { bg = "#252939", fg = "#89b4fa" })
          set(0, "Headline4", { bg = "#1f2333", fg = "#94e2d5" })
          set(0, "Headline5", { bg = "#1a1d2a", fg = "#a6e3a1" })
          set(0, "Headline6", { bg = "#16191f", fg = "#f9e2af" })
          set(0, "CodeBlock", { bg = "#1a1c2a" })
          set(0, "Dash",      { fg = "#89b4fa", bold = true })
          set(0, "Quote",     { fg = "#fab387" })
        end,
      })
      vim.cmd.doautocmd("ColorScheme")
      require("headlines").setup(opts)
    end,
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Browser-based live markdown preview with synced scroll.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = "markdown",
    build = function() vim.fn["mkdp#util#install"]() end,
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<CR>", desc = "Markdown preview", ft = "markdown" },
    },
    init = function()
      vim.g.mkdp_theme = "dark"
      vim.g.mkdp_auto_close = 1
    end,
  },
}
