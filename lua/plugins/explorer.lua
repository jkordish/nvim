return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    cmd = "Neotree",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<CR>", desc = "Explorer" },
      { "<leader>E", "<cmd>Neotree focus<CR>", desc = "Explorer focus" },
      { "<leader>ge", "<cmd>Neotree git_status<CR>", desc = "Git explorer" },
    },
    deactivate = function() vim.cmd([[Neotree close]]) end,
    init = function()
      vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("user_neotree_start", { clear = true }),
        desc = "Start Neo-tree with directory",
        once = true,
        callback = function()
          if package.loaded["neo-tree"] then return end
          local stats = (vim.uv or vim.loop).fs_stat(vim.fn.argv(0))
          if stats and stats.type == "directory" then require("neo-tree") end
        end,
      })
    end,
    opts = {
      sources = { "filesystem", "buffers", "git_status" },
      open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "Outline" },
      window = { mappings = { ["<space>"] = "none" } },
      event_handlers = {
        {
          event = "file_open_requested",
          handler = function(args)
            -- If there's >1 window open, pick one with window-picker
            local ok, picker = pcall(require, "window-picker")
            if not ok then return end
            local wins = vim.tbl_filter(function(w)
              return vim.api.nvim_win_get_config(w).relative == ""
            end, vim.api.nvim_tabpage_list_wins(0))
            if #wins <= 2 then return end -- neotree + 1 = no need to pick
            local target = picker.pick_window({ include_current_win = false })
            if target then
              vim.api.nvim_set_current_win(target)
              vim.cmd.edit(args.path)
              return { handled = true }
            end
          end,
        },
      },
      filesystem = {
        bind_to_cwd = false,
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = { visible = true, hide_dotfiles = false, hide_gitignored = false },
      },
      window = {
        width = 32,
        mappings = {
          ["<space>"] = "none",
          ["Y"] = function(state)
            local node = state.tree:get_node()
            vim.fn.setreg("+", node.path, "c")
          end,
        },
      },
      default_component_configs = {
        indent = { with_expanders = true, expander_collapsed = "", expander_expanded = "", expander_highlight = "NeoTreeExpander" },
        git_status = { symbols = { added = "✚", modified = "", deleted = "✖", renamed = "󰁕", untracked = "", ignored = "", unstaged = "󰄱", staged = "", conflict = "" } },
      },
    },
  },

  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    keys = {
      { "-", "<cmd>Oil<CR>", desc = "Open parent dir (Oil)" },
    },
    opts = {
      default_file_explorer = false,
      view_options = { show_hidden = true },
      keymaps = { ["<C-h>"] = false, ["<C-l>"] = false },
    },
  },
}
