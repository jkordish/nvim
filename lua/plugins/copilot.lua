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

  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "main",
    cmd = { "CopilotChat", "CopilotChatToggle", "CopilotChatOpen", "CopilotChatClose", "CopilotChatExplain", "CopilotChatReview", "CopilotChatFix", "CopilotChatOptimize", "CopilotChatDocs", "CopilotChatTests", "CopilotChatCommit" },
    dependencies = {
      "zbirenbaum/copilot.lua",
      "nvim-lua/plenary.nvim",
    },
    build = "make tiktoken",
    opts = {
      model = "claude-sonnet-4.5",
      window = { layout = "vertical", width = 0.4, border = "rounded" },
      auto_insert_mode = true,
      mappings = {
        reset = { normal = "<C-x>", insert = "<C-x>" },
        close = { normal = "q", insert = "<C-c>" },
        submit_prompt = { normal = "<CR>", insert = "<C-s>" },
      },
    },
    keys = {
      { "<leader>aa", "<cmd>CopilotChatToggle<CR>", desc = "Copilot Chat toggle" },
      { "<leader>ae", "<cmd>CopilotChatExplain<CR>", mode = { "n", "v" }, desc = "Explain code" },
      { "<leader>ar", "<cmd>CopilotChatReview<CR>", mode = { "n", "v" }, desc = "Review code" },
      { "<leader>af", "<cmd>CopilotChatFix<CR>", mode = { "n", "v" }, desc = "Fix code" },
      { "<leader>ao", "<cmd>CopilotChatOptimize<CR>", mode = { "n", "v" }, desc = "Optimize code" },
      { "<leader>ad", "<cmd>CopilotChatDocs<CR>", mode = { "n", "v" }, desc = "Generate docs" },
      { "<leader>at", "<cmd>CopilotChatTests<CR>", mode = { "n", "v" }, desc = "Generate tests" },
      { "<leader>am", "<cmd>CopilotChatCommit<CR>", desc = "Commit message" },
      { "<leader>ap", function()
          local actions = require("CopilotChat.actions")
          require("CopilotChat.integrations.telescope").pick(actions.prompt_actions())
        end, mode = { "n", "v" }, desc = "Prompt actions" },
    },
  },
}
