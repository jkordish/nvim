return {
  -- ─────────────────────────────────────────────────────────────────────
  -- CRITICAL: when you `:term` and run `nvim foo.txt`, that nested nvim
  -- collapses into the parent — file opens in the host nvim instead of
  -- spawning an editor inside an editor. This is THE quality-of-life
  -- plugin for living in nvim.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "willothy/flatten.nvim",
    lazy = false,
    priority = 1001,
    opts = function()
      local saved_terminal
      return {
        window = { open = "alternate" },
        hooks = {
          -- REQUIRED in current flatten: identifies this nvim's IPC socket so
          -- nested `nvim` calls from within :term can collapse into us.
          pipe_path = function()
            local n = vim.v.servername
            if n and n ~= "" then return n end
            return vim.env.NVIM or ""
          end,
          should_block = function(argv)
            return vim.tbl_contains(argv, "-b")
          end,
          pre_open = function()
            local ok, term = pcall(require, "toggleterm.terminal")
            if not ok then return end
            local termid = term.get_focused_id()
            saved_terminal = term.get(termid)
          end,
          post_open = function(bufnr, winnr, ft, is_blocking)
            if is_blocking and saved_terminal then
              saved_terminal:close()
            else
              vim.api.nvim_set_current_win(winnr)
            end
            if ft == "gitcommit" or ft == "gitrebase" then
              vim.api.nvim_create_autocmd("BufWritePost", {
                buffer = bufnr, once = true,
                callback = vim.schedule_wrap(function() vim.api.nvim_buf_delete(bufnr, {}) end),
              })
            end
          end,
          block_end = function()
            vim.schedule(function() if saved_terminal then saved_terminal:open() end end)
          end,
        },
      }
    end,
  },

  -- fzf-lua REMOVED — Telescope (with telescope-fzf-native) is the single
  -- picker. We never invoked fzf-lua post-keymap-cull anyway.

  -- ─────────────────────────────────────────────────────────────────────
  -- Dev Containers — open a project in its declared devcontainer.
  -- VSCode Remote Containers parity.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "https://codeberg.org/esensar/nvim-dev-container",
    cmd = { "DevcontainerUp", "DevcontainerStart", "DevcontainerStop", "DevcontainerAttach", "DevcontainerExec", "DevcontainerLogs", "DevcontainerEditDockerfile", "DevcontainerEditNearestDockerfile" },
    keys = {
      -- Devcontainer lives under <leader>D to keep <leader>C free for
      -- Confluence (user.confluence owns the C namespace).
      { "<leader>Du", "<cmd>DevcontainerUp<CR>",      desc = "Devcontainer up" },
      { "<leader>Dd", "<cmd>DevcontainerStop<CR>",    desc = "Devcontainer down" },
      { "<leader>Dl", "<cmd>DevcontainerLogs<CR>",    desc = "Devcontainer logs" },
      { "<leader>Da", "<cmd>DevcontainerAttach<CR>",  desc = "Devcontainer attach" },
      { "<leader>Dx", "<cmd>DevcontainerExec<CR>",    desc = "Devcontainer exec" },
    },
    config = function()
      require("devcontainer").setup({
        autocommands = { init = true, clean = false, update = true },
        container_runtime = "docker",
        compose_command = "docker compose",
      })
    end,
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- TLDR / cheat.sh inside nvim. Quick syntax reminders for any tool.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "RishabhRD/nvim-cheat.sh",
    cmd = { "Cheat", "CheatWithoutComments", "CheatList" },
    dependencies = { "RishabhRD/popfix" },
    keys = {
      { "<leader>?h", "<cmd>Cheat<CR>", desc = "cheat.sh lookup" },
    },
  },

  -- ─────────────────────────────────────────────────────────────────────
  -- Local devdocs.io browser. Offline docs for any language.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "luckasRanarison/nvim-devdocs",
    cmd = { "DevdocsOpen", "DevdocsInstall", "DevdocsUninstall", "DevdocsFetch", "DevdocsUpdate", "DevdocsUpdateAll" },
    keys = {
      { "<leader>?d", "<cmd>DevdocsOpenCurrentFloat<CR>", desc = "Devdocs current ft" },
      { "<leader>?D", "<cmd>DevdocsOpenFloat<CR>",        desc = "Devdocs search" },
    },
    opts = {
      previewer_cmd = "glow",
      cmd_args = { "-s", "dark", "-w", "80" },
      cmd_ignore = {},
      picker_cmd = false,
      ensure_installed = { "lua-5.4", "rust", "go", "python~3.12", "typescript", "javascript", "node~20_lts" },
      wrap = true,
    },
  },

  -- Numbered terminals (terminal definitions live in editor.lua).
  {
    "akinsho/toggleterm.nvim",
    keys = {
      { "<leader>1t",  "<cmd>1ToggleTerm<CR>", desc = "Term 1" },
      { "<leader>2t",  "<cmd>2ToggleTerm<CR>", desc = "Term 2" },
      { "<leader>3t",  "<cmd>3ToggleTerm<CR>", desc = "Term 3" },
    },
  },
}
