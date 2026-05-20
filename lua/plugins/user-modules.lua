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
      require("user.compass").setup()
      require("user.radar").setup()
      require("user.throttle").setup()
      require("user.checklist").setup()
      require("user.blackbox").setup()
      require("user.warnings").setup()
      require("user.eject").setup()
      require("user.cockpit").setup()
      require("user.starship").setup()
      -- ─── artistic ───
      require("user.aurora").setup()
      require("user.matrix").setup()
      require("user.contribcal").setup()
      require("user.constellation").setup()
      require("user.synesthesia").setup()
      require("user.zen").setup()
      require("user.haiku").setup()
      -- ─── weirder still ───
      require("user.dreams").setup()
      require("user.synth").setup()
      require("user.tarot").setup()
      require("user.tiny_world").setup()
      require("user.rift").setup()
      -- ─── occult ───
      require("user.glyph").setup()
      require("user.cipher").setup()
      require("user.seance").setup()
      require("user.homunculus").setup()
      require("user.quill").setup()
      require("user.summon").setup()
      require("user.oracle").setup()
      require("user.mirror").setup()
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
      -- ─── COCKPIT ─────────────────────────────────────────
      { "<leader>!!", function() require("user.cockpit").toggle() end, desc = "Cockpit: engage/disengage HUD" },
      { "<leader>!c", function() require("user.compass").toggle() end, desc = "Compass" },
      { "<leader>!r", function() require("user.radar").toggle() end, desc = "Radar" },
      { "<leader>!t", function() require("user.throttle").open() end, desc = "Throttle: action launcher" },
      { "<F1>",       function() require("user.throttle").open() end, desc = "Throttle: action launcher", mode = { "n", "i" } },
      { "<leader>!p", function() require("user.checklist").run() end, desc = "Pre-flight checklist" },
      { "<leader>!b", function() require("user.blackbox").show() end, desc = "Black box: timeline" },
      { "<leader>!e", function() require("user.eject").go() end, desc = "Eject: panic reset" },
      -- ─── ART ─── (under <leader>A namespace — capital A for artistic)
      { "<leader>Aa", function() require("user.aurora").toggle() end,    desc = "Aurora animation" },
      { "<leader>Am", function() require("user.matrix").toggle() end,    desc = "Matrix rain side column" },
      { "<leader>Ac", function() require("user.contribcal").show() end,  desc = "Contribution calendar" },
      { "<leader>An", function() require("user.constellation").open() end, desc = "Constellation: codebase as star map" },
      { "<leader>As", function() require("user.synesthesia").toggle() end, desc = "Synesthesia: hash-color identifiers" },
      { "<leader>Az", function() require("user.zen").open() end,         desc = "Zen breathing exercise" },
      { "<leader>Ah", function() require("user.haiku").compose() end,    desc = "Haiku for function under cursor" },
      { "<leader>Ad", function() require("user.dreams").toggle() end,    desc = "Dreams: idle-time AI sidebar" },
      { "<leader>AD", function() require("user.dreams").now() end,       desc = "Dream now" },
      { "<leader>Ay", function() require("user.synth").toggle() end,     desc = "Synth: chord-on-save" },
      { "<leader>At", function() require("user.tarot").today() end,      desc = "Tarot: today's card" },
      { "<leader>AT", function() require("user.tarot").draw() end,       desc = "Tarot: draw random" },
      { "<leader>Aw", function() require("user.tiny_world").show() end,  desc = "Tiny World: ASCII garden" },
      { "<leader>Ar", function() require("user.rift").open() end,        desc = "Dimensional Rift (visual)", mode = "v" },
      -- ─── occult sub-namespace ───
      { "<leader>Ag", function() require("user.glyph").toggle() end,     desc = "Glyph: cursor-word sigils" },
      { "<leader>AG", function() require("user.glyph").draw_once() end,  desc = "Glyph: draw sigil once" },
      { "<leader>AC", function() require("user.cipher").open() end,      desc = "Cipher: encrypted scratchpad" },
      { "<leader>AS", function() require("user.seance").toggle() end,    desc = "Seance: line blame whispers" },
      { "<leader>AH", function() require("user.homunculus").wake() end,  desc = "Homunculus: write today's journal" },
      { "<leader>AJ", function() require("user.homunculus").read() end,  desc = "Homunculus: read today's journal" },
      -- ─── more weird ───
      { "<leader>Aq", function() require("user.quill").toggle() end,     desc = "Quill: keystroke steno" },
      { "<leader>AQ", function() require("user.quill").replay() end,     desc = "Quill: replay session" },
      { "<leader>Au", function() require("user.summon").show() end,      desc = "Summon: recall closed window" },
      { "<leader>Ao", function() vim.cmd("Oracle") end,                  desc = "Oracle: ask yes/no" },
      { "<leader>AM", function() require("user.mirror").toggle() end,    desc = "Mirror: reversed reflection" },
    },
  },
}
