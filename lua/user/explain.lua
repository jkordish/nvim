-- AI explain diagnostic: streams Anthropic API reply token-by-token, renders
-- as virtual lines under the line with the diagnostic. Uses SSE streaming
-- via curl --no-buffer.
local M = {}

local NS = vim.api.nvim_create_namespace("user_explain")
local MODEL = "claude-haiku-4-5-20251001"
local ENDPOINT = "https://api.anthropic.com/v1/messages"

local function key()
  local k = vim.env.ANTHROPIC_API_KEY
  if not k or k == "" then vim.notify("ANTHROPIC_API_KEY not set", vim.log.levels.ERROR); return nil end
  return k
end

local function diag_at_cursor()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local diags = vim.diagnostic.get(0, { lnum = line })
  return diags[1]
end

local function render(bufnr, lnum, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, lnum, lnum + 1)
  if #lines == 0 then return end
  local virt = {}
  for _, ln in ipairs(lines) do
    table.insert(virt, { { "  ✦  " .. ln, "Comment" } })
  end
  pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum, 0, {
    virt_lines = virt,
    virt_lines_above = false,
  })
end

function M.explain()
  local diag = diag_at_cursor()
  if not diag then vim.notify("explain: no diagnostic at cursor"); return end
  local k = key(); if not k then return end

  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = diag.lnum
  local ft = vim.bo[bufnr].filetype
  local snippet = vim.api.nvim_buf_get_lines(bufnr, math.max(0, lnum - 5), lnum + 6, false)

  local prompt = string.format([[You are helping debug a %s file. The user has this diagnostic from their LSP:

  Source: %s
  Severity: %s
  Message: %s

Context (around line %d):
```%s
%s
```

In 3-4 short lines, explain *why* this diagnostic fires and *how to fix it*. Be concrete. No fluff. No preamble.]],
    ft, diag.source or "?", ({"ERROR","WARN","INFO","HINT"})[diag.severity] or "?",
    diag.message, lnum + 1, ft, table.concat(snippet, "\n"))

  local body = vim.json.encode({
    model = MODEL, max_tokens = 400, stream = true,
    messages = { { role = "user", content = prompt } },
  })

  -- Show placeholder while waiting
  render(bufnr, lnum, { "thinking…" })

  local buffer = ""
  local accumulated = ""
  local sys = vim.system({
    "curl", "-sS", "--no-buffer",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. k,
    "-H", "anthropic-version: 2023-06-01",
    "-d", body,
    ENDPOINT,
  }, {
    text = true,
    stdout = function(_, chunk)
      if not chunk then return end
      buffer = buffer .. chunk
      -- Split on \n and dispatch each SSE event line
      while true do
        local nl = buffer:find("\n", 1, true)
        if not nl then break end
        local line = buffer:sub(1, nl - 1); buffer = buffer:sub(nl + 1)
        if line:sub(1, 6) == "data: " then
          local payload = line:sub(7)
          local ok, evt = pcall(vim.json.decode, payload)
          if ok and evt.type == "content_block_delta" and evt.delta and evt.delta.text then
            accumulated = accumulated .. evt.delta.text
            -- Re-render with each token (debounced via vim.schedule batches)
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(bufnr) then
                render(bufnr, lnum, vim.split(accumulated, "\n", { plain = true }))
              end
            end)
          end
        end
      end
    end,
    stderr = function(_, data) if data and data ~= "" then vim.schedule(function() vim.notify("explain stderr: " .. data, vim.log.levels.WARN) end) end end,
  }, function(res)
    if res.code ~= 0 then
      vim.schedule(function() vim.notify("explain: curl exit " .. res.code, vim.log.levels.ERROR) end)
    end
  end)
end

function M.clear()
  vim.api.nvim_buf_clear_namespace(0, NS, 0, -1)
end

function M.setup()
  vim.api.nvim_create_user_command("Explain", M.explain, { desc = "AI-explain the diagnostic at cursor (streaming)" })
  vim.api.nvim_create_user_command("ExplainClear", M.clear, { desc = "Clear AI-explain virtual lines" })
end

return M
