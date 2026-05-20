return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Yazi — blazing fast TUI file manager (Rust). Beats vim's file
  -- exploration for moves/renames/multi-select/previews.
  -- Requires: `brew install yazi`
  -- ─────────────────────────────────────────────────────────────────────
  {
    "mikavilpas/yazi.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>fy",  "<cmd>Yazi<CR>",            desc = "Yazi (file at cursor)" },
      { "<leader>fY",  "<cmd>Yazi cwd<CR>",        desc = "Yazi (cwd)" },
      { "<C-y>",       "<cmd>Yazi toggle<CR>",     desc = "Yazi resume" },
    },
    opts = {
      open_for_directories = false,
      keymaps = {
        show_help = "<f1>",
        open_file_in_vertical_split = "<c-v>",
        open_file_in_horizontal_split = "<c-x>",
        open_file_in_tab = "<c-t>",
        grep_in_directory = "<c-s>",
        replace_in_directory = "<c-g>",
        cycle_open_buffers = "<tab>",
        copy_relative_path_to_selected_files = "<c-y>",
        send_to_quickfix_list = "<c-q>",
      },
      yazi_floating_window_winblend = 0,
      yazi_floating_window_border = "rounded",
      log_level = vim.log.levels.OFF,
    },
  },
}
