return {
  -- ─────────────────────────────────────────────────────────────────────
  -- Overseer — VSCode tasks.json + launch.json equivalent.
  -- Define tasks in .overseer/, run with templates, watch output, attach
  -- DAP to running processes.
  -- ─────────────────────────────────────────────────────────────────────
  {
    "stevearc/overseer.nvim",
    cmd = {
      "OverseerOpen", "OverseerClose", "OverseerToggle", "OverseerSaveBundle",
      "OverseerLoadBundle", "OverseerDeleteBundle", "OverseerRunCmd", "OverseerRun",
      "OverseerInfo", "OverseerBuild", "OverseerQuickAction", "OverseerTaskAction",
      "OverseerClearCache",
    },
    keys = {
      { "<leader>Tt", "<cmd>OverseerToggle<CR>",      desc = "Tasks toggle" },
      { "<leader>Tr", "<cmd>OverseerRun<CR>",         desc = "Run task" },
      { "<leader>Tc", "<cmd>OverseerRunCmd<CR>",      desc = "Run cmd as task" },
      { "<leader>Ta", "<cmd>OverseerQuickAction<CR>", desc = "Task quick action" },
      { "<leader>Ti", "<cmd>OverseerInfo<CR>",        desc = "Task info" },
      { "<leader>Tl", "<cmd>OverseerLoadBundle<CR>",  desc = "Load task bundle" },
      { "<leader>Ts", "<cmd>OverseerSaveBundle<CR>",  desc = "Save task bundle" },
      { "<leader>Tb", "<cmd>OverseerBuild<CR>",       desc = "Build task" },
    },
    opts = {
      strategy = { "toggleterm", direction = "horizontal", autoscroll = true, quit_on_exit = "success" },
      templates = { "builtin" },
      task_list = {
        direction = "bottom",
        min_height = 12,
        max_height = 20,
        default_detail = 1,
      },
      component_aliases = {
        default = {
          { "display_duration", detail_level = 2 },
          "on_output_summarize",
          "on_exit_set_status",
          "on_complete_notify",
          "on_complete_dispose",
        },
      },
      form = { border = "rounded" },
      task_win = { border = "rounded" },
      confirm = { border = "rounded" },
    },
  },

  -- Conventional-commit-style commit messages via picker.
  {
    "Saecki/crates.nvim",
    enabled = false, -- duplicate guard; real spec lives in lang-rust.lua
  },
  {
    "olimorris/persisted.nvim",
    enabled = false, -- using folke/persistence already
  },
}
