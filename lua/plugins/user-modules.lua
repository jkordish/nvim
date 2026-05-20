-- Hand-rolled native Lua modules under lua/user/ — none of these are
-- third-party plugins. Loaded eagerly so commands/autocmds are registered.
return {
  {
    name = "user.modules",
    dir = vim.fn.stdpath("config"),   -- satisfies lazy.nvim's spec validator
    lazy = false,
    priority = 100,
    config = function()
      require("user.yankring").setup()
      require("user.ai_cmd").setup()
      require("user.perfhud").setup()
      require("user.present").setup()
      require("user.workspace").setup()
      require("user.repl").setup()
      require("user.coverage").setup()
      require("user.jobs").setup()
      require("user.heatmap").setup()
      require("user.pulse").setup()
      require("user.webhook").setup()
      require("user.symtree").setup()
      require("user.today").setup()
    end,
    keys = {
      -- Yank ring (normal mode only — visual <leader>p is paste-without-yank)
      { "<leader>p",  function() require("user.yankring").pick() end, mode = "n", desc = "Yank ring" },
      -- AI cmd
      { "<leader>ai", function() vim.cmd("AI") end, desc = "AI: ask about cursor context" },
      -- Perf HUD
      { "<leader>up", function() require("user.perfhud").toggle() end, desc = "Perf HUD" },
      -- Presentation mode (capital P at top level — easy to remember)
      { "<leader>P",  function() require("user.present").start() end, desc = "Present markdown buffer", ft = "markdown" },
      -- Workspace snapshots
      { "<leader>WS", function() require("user.workspace").save() end, desc = "Workspace: save snapshot" },
      { "<leader>WR", function() require("user.workspace").load() end, desc = "Workspace: restore snapshot" },
      { "<leader>WL", function() require("user.workspace").list() end, desc = "Workspace: list/pick" },
      -- REPL
      { "<leader>rt", function() require("user.repl").toggle() end, desc = "REPL toggle" },
      { "<leader>rl", function() require("user.repl").send_line() end, desc = "REPL send line" },
      { "<leader>rp", function() require("user.repl").send_paragraph() end, desc = "REPL send paragraph" },
      { "<leader>rb", function() require("user.repl").send_buffer() end, desc = "REPL send buffer" },
      { "<leader>rr", function() require("user.repl").send_selection() end, mode = "v", desc = "REPL send selection" },
      -- Coverage
      { "<leader>uc", function() require("user.coverage").show() end, desc = "Coverage: show signs" },
      { "<leader>uC", function() require("user.coverage").hide() end, desc = "Coverage: hide signs" },
      -- Jobs
      { "<leader>uj", function() require("user.jobs").list() end, desc = "Jobs: list" },
      -- Heatmap
      { "<leader>uh", function() require("user.heatmap").toggle() end, desc = "Heatmap: toggle git churn" },
      -- Symbol tree
      { "<leader>uo", function() require("user.symtree").toggle() end, desc = "SymTree: toggle outline" },
      -- Today
      { "<leader>ut", function() require("user.today").show() end, desc = "Today: activity dashboard" },
      -- Webhook
      { "<leader>uw", function() vim.cmd("WebhookStart") end, desc = "Webhook: start server" },
      { "<leader>uW", function() vim.cmd("WebhookStop") end, desc = "Webhook: stop server" },
    },
  },
}
