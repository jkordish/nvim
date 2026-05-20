return {
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        hide_during_completion = true,
        debounce = 75,
        keymap = {
          accept = "<M-l>",
          accept_word = "<M-w>",
          accept_line = "<M-j>",
          next = "<M-]>",
          prev = "<M-[>",
          dismiss = "<C-]>",
        },
      },
      panel = { enabled = false },
      filetypes = {
        ["*"] = true,
        gitcommit = false,
        gitrebase = false,
        TelescopePrompt = false,
        ["copilot-chat"] = false,
      },
    },
  },

  -- CopilotChat REMOVED — Avante (lua/plugins/avante.lua) is the canonical
  -- AI chat surface. CopilotChat duplicated the conversation/explain/refactor
  -- workflow with a heavier deps tree (tiktoken build, etc.). Use :Avante.
}
