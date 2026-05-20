-- Haiku: ask Claude haiku to write a 5-7-5 about the function the cursor is
-- inside. Renders as a quiet floating poem next to the function header.
local M = {}

local MODEL = "claude-haiku-4-5-20251001"
local ENDPOINT = "https://api.anthropic.com/v1/messages"

local function key()
  local k = vim.env.ANTHROPIC_API_KEY
  if not k or k == "" then vim.notify("ANTHROPIC_API_KEY not set", vim.log.levels.ERROR); return nil end
  return k
end

local function function_at_cursor(bufnr)
  local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
  if not lang then return nil end
  local parser = vim.treesitter.get_parser(bufnr, lang)
  local tree = parser:parse()[1]
  local pos = vim.api.nvim_win_get_cursor(0)
  local node = tree:root():descendant_for_range(pos[1] - 1, pos[2], pos[1] - 1, pos[2])
  while node do
    local t = node:type()
    if t:find("function") or t:find("method") or t == "func_def" or t == "function_declaration" then
      return node, vim.treesitter.get_node_text(node, bufnr)
    end
    node = node:parent()
  end
end

function M.compose()
  local k = key(); if not k then return end
  local bufnr = vim.api.nvim_get_current_buf()
  local node, text = function_at_cursor(bufnr)
  if not node then
    -- Fall back to a window of lines around the cursor
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local s, e = math.max(0, row - 10), row + 10
    text = table.concat(vim.api.nvim_buf_get_lines(bufnr, s, e, false), "\n")
  end

  local prompt = string.format([[Write a haiku (5-7-5 syllables, three lines) inspired by this code.
Capture its purpose or feeling, not its mechanics. Be evocative, brief.

Reply with ONLY the three lines of the haiku. No preamble, no title, no explanation.

```%s
%s
```]], vim.bo[bufnr].filetype, text)

  local body = vim.json.encode({
    model = MODEL, max_tokens = 200,
    messages = { { role = "user", content = prompt } },
  })

  vim.notify("✦ composing haiku…")
  vim.system({
    "curl", "-sS",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. k,
    "-H", "anthropic-version: 2023-06-01",
    "-d", body,
    ENDPOINT,
  }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then vim.notify("haiku: curl failed", vim.log.levels.ERROR); return end
      local ok, parsed = pcall(vim.json.decode, res.stdout or "")
      if not ok or not parsed.content then vim.notify("haiku: bad response", vim.log.levels.ERROR); return end
      local haiku_text = parsed.content[1] and parsed.content[1].text or ""
      M.show(haiku_text)
    end)
  end)
end

function M.show(text)
  local lines = vim.split(vim.trim(text), "\n")
  -- Top + bottom decorative lines
  local out = { "", "  ✦  " .. (lines[1] or ""), "  ✧  " .. (lines[2] or ""), "  ✦  " .. (lines[3] or ""), "" }
  local width = 0
  for _, l in ipairs(out) do width = math.max(width, vim.api.nvim_strwidth(l)) end
  width = width + 4

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor", style = "minimal", border = "rounded",
    title = " ✦  haiku ", title_pos = "center",
    width = width, height = #out,
    row = 1, col = 2,
  })
  -- Italicize all lines via a buffer-wide highlight
  vim.api.nvim_set_hl(0, "HaikuLine", { italic = true, fg = "#b4befe" })
  local ns = vim.api.nvim_create_namespace("user_haiku")
  for i = 0, #out - 1 do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, i, 0, {
      end_line = i + 1, hl_group = "HaikuLine",
    })
  end
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "y", function() vim.fn.setreg("+", text); vim.notify("haiku copied") end, { buffer = buf })
end

function M.setup() vim.api.nvim_create_user_command("Haiku", M.compose, { desc = "AI haiku about function under cursor" }) end
return M
