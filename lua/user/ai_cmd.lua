-- :AI <intent>  — call Claude with your intent + surrounding context.
-- Returns suggestions in a floating window. Press <CR> on a suggestion to
-- apply it, or 'q' to dismiss.
--
-- Uses $ANTHROPIC_API_KEY directly (vim.uv async HTTP via curl). No SDK.
local M = {}

local MODEL = "claude-haiku-4-5-20251001"  -- fast + cheap for cmdline intent
local ANTHROPIC_URL = "https://api.anthropic.com/v1/messages"

local function get_key()
  local k = vim.env.ANTHROPIC_API_KEY
  if not k or k == "" then
    vim.notify("ANTHROPIC_API_KEY not set", vim.log.levels.ERROR)
    return nil
  end
  return k
end

local function context_block()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  local fname = vim.fn.expand("%:t")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local total = vim.api.nvim_buf_line_count(bufnr)
  local s = math.max(1, cursor[1] - 40)
  local e = math.min(total, cursor[1] + 40)
  local lines = vim.api.nvim_buf_get_lines(bufnr, s - 1, e, false)
  return string.format(
    "File: %s  (filetype: %s)\nCursor at line %d. Showing lines %d-%d:\n```%s\n%s\n```",
    fname, ft, cursor[1], s, e, ft, table.concat(lines, "\n")
  )
end

local function call_claude(intent, callback)
  local key = get_key(); if not key then return end

  local prompt = string.format([[
You are a Neovim assistant. The user is editing a file and asks for help.
Their intent: %s

Context (file region around cursor):
%s

Reply with up to 3 numbered suggestions. Each suggestion is either:
  A) A short code edit to apply, formatted as ```%s\n<the code>\n```
  B) A Vim ex command to run, formatted as `:<command>`
  C) A one-line explanation if the user asked a question (no code block)

Keep suggestions concrete and minimal. No prose framing.]], intent, context_block(), vim.bo.filetype)

  local body = vim.json.encode({
    model = MODEL,
    max_tokens = 2048,
    messages = { { role = "user", content = prompt } },
  })

  vim.notify("AI: thinking…", vim.log.levels.INFO)
  local stdout, stderr = {}, {}
  vim.system({
    "curl", "-sS", "--no-buffer",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. key,
    "-H", "anthropic-version: 2023-06-01",
    "-d", body,
    ANTHROPIC_URL,
  }, {
    text = true,
    stdout = function(_, data) if data then table.insert(stdout, data) end end,
    stderr = function(_, data) if data then table.insert(stderr, data) end end,
  }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify("AI: curl failed (" .. res.code .. ")\n" .. table.concat(stderr), vim.log.levels.ERROR)
        return
      end
      local raw = table.concat(stdout)
      local ok, parsed = pcall(vim.json.decode, raw)
      if not ok or not parsed.content then
        vim.notify("AI: bad response:\n" .. raw:sub(1, 500), vim.log.levels.ERROR)
        return
      end
      local text = parsed.content[1] and parsed.content[1].text or ""
      callback(text)
    end)
  end)
end

local function show_result(text)
  local lines = vim.split(text, "\n")
  local width = math.min(100, math.floor(vim.o.columns * 0.7))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = " ✦ AI suggestion ", title_pos = "center",
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2

  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, silent = true })
  vim.keymap.set("n", "y", function()
    vim.fn.setreg("+", text); vim.notify("AI: full reply copied to clipboard")
  end, { buffer = buf, silent = true, desc = "Yank full reply" })
end

function M.ask(args)
  local intent = args.args
  if intent == "" then
    vim.ui.input({ prompt = "AI intent: " }, function(input)
      if input and input ~= "" then call_claude(input, show_result) end
    end)
    return
  end
  call_claude(intent, show_result)
end

function M.setup()
  vim.api.nvim_create_user_command("AI", M.ask, { nargs = "?", desc = "Ask Claude about cursor context" })
end

return M
