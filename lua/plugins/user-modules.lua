-- Hand-rolled native Lua modules under lua/user/.
--
-- Curated post-cull: only the modules that earn their place daily are loaded
-- eagerly. Novelty modules (aurora, matrix, tarot, tiny_world, haiku, synth,
-- oracle, glyph) live under lua/user/_play/ and are accessible via `:Play`.
-- Three modules were deleted in the cull: mirror, zen, contribcal.
return {
  {
    name = "user.modules",
    dir = vim.fn.stdpath("config"),   -- satisfies lazy.nvim's spec validator
    lazy = false,
    priority = 100,
    config = function()
      -- ─── design system (must come first) ───
      require("user.brand").setup()
      require("user.curtain").setup()
      require("user.welcome").setup()

      -- ─── primary entry points ───
      require("user.suggest").setup()
      require("user.commandeer").setup()

      -- ─── daily-driver tools ───
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

      -- ─── cockpit / mission control ───
      require("user.compass").setup()
      require("user.radar").setup()
      require("user.throttle").setup()
      require("user.checklist").setup()
      require("user.blackbox").setup()
      require("user.eject").setup()
      require("user.cockpit").setup()
      require("user.starship").setup()

      -- ─── opt-in / niche ───
      require("user.dreams").setup()
      require("user.rift").setup()
      require("user.constellation").setup()
      require("user.synesthesia").setup()
      require("user.cipher").setup()
      require("user.seance").setup()
      require("user.homunculus").setup()
      require("user.quill").setup()
      require("user.summon").setup()

      -- ─── novelty namespace (one entry point, lazy-loaded) ───
      require("user._play").setup()
    end,
    keys = {
      -- ═════ THE HEADLINE ═════
      { "<leader><space>", function() require("user.suggest").show() end, desc = "✦ what should I do next?" },

      -- ═════ DAILY ═════
      { "<leader>p",  function() require("user.yankring").pick() end, mode = "n", desc = "Yank ring" },
      { "<leader>ai", function() vim.cmd("AI") end, desc = "AI: ask about cursor context" },
      { "<leader>cX", function() require("user.explain").explain() end, desc = "AI explain diagnostic (streaming)" },
      { "<leader>cl", function() require("user.tsplay").toggle() end, desc = "Treesitter playground" },

      -- File / project entry points
      { "<leader>uS", function() require("user.spotlight").open() end, desc = "Spotlight: unified picker" },
      { "<C-S-Space>", function() require("user.spotlight").open() end, desc = "Spotlight", mode = { "n", "i" } },
      { "<leader>uv", function() require("user.smartpaste").paste() end, desc = "Smart paste with transforms" },

      -- REPL / language
      { "<leader>rt", function() require("user.repl").toggle() end, desc = "REPL toggle" },
      { "<leader>rl", function() require("user.repl").send_line() end, desc = "REPL send line" },
      { "<leader>rp", function() require("user.repl").send_paragraph() end, desc = "REPL send paragraph" },
      { "<leader>rb", function() require("user.repl").send_buffer() end, desc = "REPL send buffer" },
      { "<leader>rr", function() require("user.repl").send_selection() end, mode = "v", desc = "REPL send selection" },

      -- Background work + visible state
      { "<leader>uj", function() require("user.jobs").list() end, desc = "Jobs list" },
      { "<leader>up", function() require("user.perfhud").toggle() end, desc = "Perf HUD" },
      { "<leader>uo", function() require("user.symtree").toggle() end, desc = "SymTree outline" },
      { "<leader>ut", function() require("user.today").show() end, desc = "Today: activity dashboard" },
      { "<leader>uh", function() require("user.heatmap").toggle() end, desc = "Heatmap: git churn" },
      { "<leader>uc", function() require("user.coverage").show() end, desc = "Coverage: show" },
      { "<leader>uC", function() require("user.coverage").hide() end, desc = "Coverage: hide" },
      { "<leader>uR", function() require("user.rextest").open() end, desc = "Regex tester" },

      -- Git history scrubbing
      { "<leader>gT", function() require("user.timetravel").start() end, desc = "Git time machine" },

      -- Workspace
      { "<leader>WS", function() require("user.workspace").save() end, desc = "Workspace save" },
      { "<leader>WR", function() require("user.workspace").load() end, desc = "Workspace load" },
      { "<leader>WL", function() require("user.workspace").list() end, desc = "Workspace list" },

      -- Macros
      { "<leader>qm", function() require("user.macroreg").pick() end, desc = "Macros pick" },
      { "<leader>qM", function()
          vim.ui.input({ prompt = "Macro name (saves register q): " }, function(name)
            if name and name ~= "" then require("user.macroreg").save_macro(name, "q") end
          end)
        end, desc = "Macros save reg q" },

      -- Markdown
      { "<leader>P",  function() require("user.present").start() end, desc = "Present markdown", ft = "markdown" },

      -- ═════ COCKPIT (<leader>!) ═════
      { "<leader>!!", function() require("user.cockpit").toggle() end, desc = "Cockpit toggle" },
      { "<leader>!c", function() require("user.compass").toggle() end, desc = "Compass" },
      { "<leader>!r", function() require("user.radar").toggle() end, desc = "Radar" },
      { "<leader>!t", function() require("user.throttle").open() end, desc = "Throttle launcher" },
      { "<F1>",       function() require("user.throttle").open() end, desc = "Throttle launcher", mode = { "n", "i" } },
      { "<leader>!p", function() require("user.checklist").run() end, desc = "Pre-flight checklist" },
      { "<leader>!b", function() require("user.blackbox").show() end, desc = "Black box timeline" },
      { "<leader>!e", function() require("user.eject").go() end, desc = "Eject (panic reset)" },

      -- ═════ NICHE (each invoked by command — no surface keys) ═════
      -- :Suggest :Welcome :Dreams :Rift :Constellation :Synesthesia :Cipher
      -- :Seance :HomunculusWake :HomunculusRead :Quill :Summon :Webhook* :Play
    },
  },
}
