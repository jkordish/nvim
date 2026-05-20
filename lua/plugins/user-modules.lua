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
      require("user.spotlight").setup()
      require("user.smartpaste").setup()
      require("user.tsplay").setup()
      require("user.rextest").setup()
      require("user.explain").setup()
      require("user.timetravel").setup()
      require("user.macroreg").setup()
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
      -- Spotlight (the new home for ⌘+Space-style nav)
      { "<C-S-Space>", function() require("user.spotlight").open() end, desc = "Spotlight: unified picker", mode = { "n", "i" } },
      { "<leader>uS",  function() require("user.spotlight").open() end, desc = "Spotlight: unified picker" },
      -- Smart paste (overlaps <leader>P with Present in markdown only — both registered, ft filter on Present wins there)
      { "<leader>uv",  function() require("user.smartpaste").paste() end, desc = "Smart paste with transforms" },
      -- Treesitter playground
      { "<leader>uT",  function() require("user.tsplay").toggle() end, desc = "Treesitter playground" },
      -- Regex tester
      { "<leader>uR",  function() require("user.rextest").open() end, desc = "Live regex tester" },
      -- Explain diagnostic (capital X to avoid rust's <leader>cE = expand macro)
      { "<leader>cX",  function() require("user.explain").explain() end, desc = "AI explain diagnostic (streaming)" },
      -- Time travel
      { "<leader>gT",  function() require("user.timetravel").start() end, desc = "Git time machine: scrub commits" },
      -- Macros
      { "<leader>qm",  function() require("user.macroreg").pick() end, desc = "Saved macros: pick" },
      { "<leader>qM",  function()
          vim.ui.input({ prompt = "Macro name (saves register q): " }, function(name)
            if name and name ~= "" then require("user.macroreg").save_macro(name, "q") end
          end)
        end, desc = "Saved macros: save reg q" },
    },
  },
}
