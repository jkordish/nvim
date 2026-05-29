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
      require("user.playbooks").setup()
      require("user.tour").setup()
      require("user.state").setup()

      -- ─── daily-driver tools ───
      require("user.yankring").setup()
      require("user.ai_cmd").setup()
      require("user.perfhud").setup()
      require("user.present").setup()
      require("user.workspace").setup()
      require("user.repl").setup()
      require("user.coverage").setup()
      require("user.jobs").setup()
      require("user.resume").setup()
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
      require("user.jira").setup()
      require("user.confluence").setup()
      require("user.contextmenu").setup()
      require("user.tabs").setup()
      require("user.windows").setup()
      require("user.dock").setup()
      require("user.projects").setup()
      require("user.toast").setup()
      require("user.jumppulse").setup()
      require("user.lsp_ui").setup()
      require("user.hints").setup()
      require("user.profiles").setup()
      require("user.recall").setup()

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
      { "<leader>up",      function() require("user.playbooks").show() end, desc = "Playbooks: learned chains" },
      { "<leader>us",      function() require("user.state").show() end,     desc = "UserState: inspect persistent data" },

      -- ═════ DAILY ═════
      { "<leader>p",  function() require("user.yankring").pick() end, mode = "n", desc = "Yank ring" },
      { "<leader>ai", function() vim.cmd("AI") end, desc = "AI: ask about cursor context" },
      { "<leader>cX", function() require("user.explain").explain() end, desc = "AI explain diagnostic (streaming)" },
      { "<leader>cl", function() require("user.tsplay").toggle() end, desc = "Treesitter playground" },

      -- ═════ RESUME (task intent + brief) ═════
      { "<leader>Kc", function() require("user.resume").capture() end, desc = "Resume: capture task" },
      { "<leader>Kr", function() require("user.resume").brief()   end, desc = "Resume: show brief" },
      { "<leader>Kx", function() require("user.resume").resolve() end, desc = "Resume: resolve task" },
      { "<leader>Kl", function() require("user.resume").list()    end, desc = "Resume: list paused tasks" },

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
      { "<leader>uP", function() require("user.perfhud").toggle() end, desc = "Perf HUD" },
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

      -- ═════ JIRA / CONFLUENCE (<leader>j / <leader>C) ═════
      { "<leader>ji", function() require("user.jira").show_issue() end,        desc = "Jira: show issue (branch/prompt)" },
      { "<leader>jm", function() require("user.jira").show_mine() end,         desc = "Jira: my open issues" },
      { "<leader>js", function() require("user.jira").show_search() end,       desc = "Jira: JQL search" },
      { "<leader>jo", function() require("user.jira").open_in_browser() end,   desc = "Jira: open in browser" },
      { "<leader>jc", function() require("user.jira").prompt_comment() end,    desc = "Jira: comment" },
      { "<leader>jt", function() require("user.jira").prompt_transition() end, desc = "Jira: transition status" },
      { "<leader>jb", function()
          vim.ui.input({ prompt = "pin ticket to this cwd (empty=clear): " }, function(v)
            require("user.jira").pin_ticket(v or "")
          end)
        end, desc = "Jira: pin ticket to cwd" },
      { "<leader>jr", function() require("user.jira").show_recent() end,        desc = "Jira: recently viewed" },
      { "<leader>jK", function() require("user.jira").peek_under_cursor() end,  desc = "Jira: peek issue under cursor" },
      { "<leader>jI", function() require("user.jira").insert_ref("mine") end,   desc = "Jira: insert ref at cursor (mine)" },
      { "<leader>jR", function() require("user.jira").insert_ref("recent") end, desc = "Jira: insert ref at cursor (recent)" },
      { "<leader>jf", function() require("user.jira").show_filters() end,       desc = "Jira: saved filters" },
      { "<leader>jF", function()
          vim.ui.input({ prompt = "save last JQL as filter name: " }, function(n)
            if n and n ~= "" then require("user.jira").save_filter(n) end
          end)
        end, desc = "Jira: save last search as filter" },
      { "<leader>jn", function() require("user.jira").create_flow() end,     desc = "Jira: new issue (composer)" },
      { "<leader>ja", function() require("user.jira").prompt_assignee() end,  desc = "Jira: assign issue" },
      { "<leader>jE", function() require("user.jira").edit_description() end, desc = "Jira: edit description" },
      { "<leader>jw", function() require("user.jira").log_work() end,         desc = "Jira: log work (current ticket)" },

      { "<leader>Cs", function() require("user.confluence").show_search() end,       desc = "Confluence: search" },
      { "<leader>Cp", function() require("user.confluence").show_page() end,         desc = "Confluence: open page (id/url)" },
      { "<leader>Cr", function() require("user.confluence").show_recent() end,       desc = "Confluence: recent pages (yours)" },
      { "<leader>CR", function() require("user.confluence").show_recent_edits() end, desc = "Confluence: recently modified (wiki)" },
      { "<leader>CI", function() require("user.confluence").insert_ref("recent") end, desc = "Confluence: insert page ref (recent)" },
      { "<leader>CS", function() require("user.confluence").insert_ref("search") end, desc = "Confluence: insert page ref (search)" },

      -- ═════ WINDOWS / TABS ═════
      { "<leader>ww", function() require("user.windows").pick() end,            desc = "Windows: pick" },
      { "<leader>wz", function() require("user.windows").toggle_maximize() end, desc = "Windows: maximize/zen toggle" },
      { "<leader>wm", function() require("user.windows").toggle_maximize() end, desc = "Windows: maximize toggle (alias)" },
      { "<leader>wS", function() require("user.windows").save_layout() end,     desc = "Windows: save layout" },
      { "<leader>wL", function() require("user.windows").show_layouts() end,    desc = "Windows: load layout (pick)" },
      { "<leader>wD", function() require("user.windows").delete_layout() end,   desc = "Windows: delete layout (pick)" },
      { "<leader><tab>r",     "<cmd>TabRename<CR>",         desc = "Tab: rename" },
      { "<leader><tab>R",     "<cmd>TabRenameRevert<CR>",   desc = "Tab: revert last rename (swap with previous name)" },
      { "<leader><tab>a",     "<cmd>TabRenameAuto<CR>",     desc = "Tab: revert to auto-name" },
      { "<leader><tab>N",     "<cmd>TabNewNamed<CR>",     desc = "Tab: new + name" },
      { "<leader><tab>p",     "<cmd>TabPick<CR>",         desc = "Tab: pick by name (MRU sorted · <C-r> rename · <C-x> close)" },
      { "<leader><tab>D",     "<cmd>TabPickClose<CR>",    desc = "Tab: pick one to close" },
      { "<leader><tab>u",     "<cmd>TabUndoClose<CR>",      desc = "Tab: undo close (reopen last closed)" },
      { "<leader><tab>U",     "<cmd>TabUndoCloseBatch<CR>", desc = "Tab: batch undo (reopen everything from last close op)" },
      { "<leader><tab>o",     "<cmd>TabCloseOthers<CR>",  desc = "Tab: close others" },
      { "<leader><tab><tab>", "<cmd>TabLast<CR>",         desc = "Tab: last used (toggle)" },
      { "<leader><tab>>",     "<cmd>TabMoveRight<CR>",    desc = "Tab: move right" },
      { "<leader><tab><",     "<cmd>TabMoveLeft<CR>",     desc = "Tab: move left" },
      { "<leader><tab>1",     function() require("user.tabs").jump(1) end, desc = "Tab: jump 1" },
      { "<leader><tab>2",     function() require("user.tabs").jump(2) end, desc = "Tab: jump 2" },
      { "<leader><tab>3",     function() require("user.tabs").jump(3) end, desc = "Tab: jump 3" },
      { "<leader><tab>4",     function() require("user.tabs").jump(4) end, desc = "Tab: jump 4" },
      { "<leader><tab>5",     function() require("user.tabs").jump(5) end, desc = "Tab: jump 5" },
      { "<leader><tab>6",     function() require("user.tabs").jump(6) end, desc = "Tab: jump 6" },
      { "<leader><tab>7",     function() require("user.tabs").jump(7) end, desc = "Tab: jump 7" },
      { "<leader><tab>8",     function() require("user.tabs").jump(8) end, desc = "Tab: jump 8" },
      { "<leader><tab>9",     function() require("user.tabs").jump(9) end, desc = "Tab: jump 9" },

      -- Chord-free instant jump. <M-N> is the universal "switch to tab N"
      -- shortcut (Chrome/VSCode/iTerm) — much faster than the 3-key chord.
      { "<M-1>", function() require("user.tabs").jump(1) end, desc = "Tab: jump 1 (Alt)" },
      { "<M-2>", function() require("user.tabs").jump(2) end, desc = "Tab: jump 2 (Alt)" },
      { "<M-3>", function() require("user.tabs").jump(3) end, desc = "Tab: jump 3 (Alt)" },
      { "<M-4>", function() require("user.tabs").jump(4) end, desc = "Tab: jump 4 (Alt)" },
      { "<M-5>", function() require("user.tabs").jump(5) end, desc = "Tab: jump 5 (Alt)" },
      { "<M-6>", function() require("user.tabs").jump(6) end, desc = "Tab: jump 6 (Alt)" },
      { "<M-7>", function() require("user.tabs").jump(7) end, desc = "Tab: jump 7 (Alt)" },
      { "<M-8>", function() require("user.tabs").jump(8) end, desc = "Tab: jump 8 (Alt)" },
      { "<M-9>", function() require("user.tabs").jump(9) end, desc = "Tab: jump 9 (Alt)" },
      { "<M-`>", function() require("user.tabs").jump_last() end, desc = "Tab: last used (Alt)" },
      { "<M-j>", function() require("user.tabs").jump_by_label() end,           desc = "Tab: jump by letter label (stable across reorder)" },
      { "<M-J>", function() require("user.tabs").jump_by_label_sustained() end,  desc = "Tab: sustained label-jump (browse multiple, <Esc>/<CR> exits)" },

      -- ═════ DOCK ═════
      { "<leader>`",  function() require("user.dock").toggle() end,         desc = "Dock: toggle", mode = { "n", "t" } },
      { "<leader>1`", function() require("user.dock").switch(1) end,        desc = "Dock: term 1" },
      { "<leader>2`", function() require("user.dock").switch(2) end,        desc = "Dock: term 2" },
      { "<leader>3`", function() require("user.dock").switch(3) end,        desc = "Dock: term 3" },
      { "<leader>4`", function() require("user.dock").switch(4) end,        desc = "Dock: output" },
      { "<leader>5`", function() require("user.dock").switch(5) end,        desc = "Dock: tasks" },
      { "<leader>6`", function() require("user.dock").switch(6) end,        desc = "Dock: notifications" },

      -- ═════ PROJECTS ═════
      { "<leader>oo", function() require("user.projects").show() end,       desc = "Projects: pick" },
      { "<leader>oP", function() require("user.projects").pin() end,        desc = "Projects: pin cwd" },

      -- ═════ RECALL ═════
      { "<leader>z",  function() require("user.recall").pop() end,           desc = "Recall: undo last context shift" },

      -- ═════ PEEK ═════
      { "gp",  function() require("user.peek").definition()      end, desc = "Peek: definition" },
      { "gP",  function() require("user.peek").references()      end, desc = "Peek: references" },
      { "gT",  function() require("user.peek").type_definition() end, desc = "Peek: type" },
      { "gI",  function() require("user.peek").implementation()  end, desc = "Peek: implementation" },

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
