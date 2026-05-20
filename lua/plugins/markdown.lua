return {
  -- image.nvim disabled: requires the `magick` luarock which needs Lua 5.1,
  -- conflicting with system Lua 5.5. Snacks.image (already enabled) handles
  -- PNG inline rendering in Ghostty via the kitty graphics protocol natively.

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

  -- headlines.nvim removed: conflicts with render-markdown.nvim per its
  -- healthcheck. render-markdown handles header styling itself.

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
