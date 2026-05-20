-- Dreams: when nvim sits idle for 90s in a code buffer, asks Claude to
-- generate a surreal paragraph "inspired by" the last edited region. Types
-- it character by character into a floating sidebar. Vanishes when you
-- touch any key. Quiet, optional, dreamlike.
local M = {}

local IDLE_MS = 90 * 1000      -- 90s of idleness
local TYPING_INTERVAL = 35     -- ms per character

local state = { win = nil, buf = nil, timer = nil, typing = nil, enabled = false, idle_start = 0, last_edit_buf = nil }
local MODEL = "claude-haiku-4-5-20251001"
local ENDPOINT = "https://api.anthropic.com/v1/messages"

local function get_key()
  return vim.env.ANTHROPIC_API_KEY
end

local function close_window()
  if state.typing then state.typing:stop(); state.typing:close(); state.typing = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

local function open_window()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  local w = 40
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", focusable = false, noautocmd = true,
    border = "rounded", title = " ✦ a dream ", title_pos = "center",
    width = w, height = 14,
    row = 2, col = vim.o.columns - w - 4,
  })
  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
end

local function type_into_window(text)
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then open_window() end
  local i = 0
  state.typing = vim.uv.new_timer()
  state.typing:start(0, TYPING_INTERVAL, vim.schedule_wrap(function()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      if state.typing then state.typing:stop(); state.typing:close(); state.typing = nil end
      return
    end
    i = i + 1
    if i > #text then
      state.typing:stop(); state.typing:close(); state.typing = nil
      return
    end
    local partial = text:sub(1, i)
    local lines = vim.split(partial, "\n", { plain = true })
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
  end))
end

local function dream()
  local k = get_key(); if not k then return end
  local bufnr = state.last_edit_buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 40, false)
  local ft = vim.bo[bufnr].filetype

  local prompt = ([[The user has been editing a %s file. Compose a short surreal paragraph (4-6 sentences) "inspired by" this code — not describing it, but dreaming around it. The vibe of fragments, koans, and night thoughts. Strange and quiet. No markdown, no preamble, just the dream itself.

```%s
%s
```]]):format(ft, ft, table.concat(lines, "\n"))

  vim.system({
    "curl", "-sS",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. k,
    "-H", "anthropic-version: 2023-06-01",
    "-d", vim.json.encode({ model = MODEL, max_tokens = 350, messages = { { role = "user", content = prompt } } }),
    ENDPOINT,
  }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then return end
      local ok, parsed = pcall(vim.json.decode, res.stdout or "")
      if not ok or not parsed.content then return end
      local text = (parsed.content[1] and parsed.content[1].text or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if text ~= "" then type_into_window(text) end
    end)
  end)
end

local function on_activity()
  state.idle_start = vim.uv.now()
  close_window()  -- any keystroke dismisses an active dream
end

function M.enable()
  if state.enabled then return end
  state.enabled = true
  state.idle_start = vim.uv.now()

  local grp = vim.api.nvim_create_augroup("user_dreams", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "InsertEnter" }, {
    group = grp,
    callback = function()
      state.last_edit_buf = vim.api.nvim_get_current_buf()
      on_activity()
    end,
  })

  state.timer = vim.uv.new_timer()
  state.timer:start(IDLE_MS, IDLE_MS, vim.schedule_wrap(function()
    if not state.enabled then return end
    local idle = vim.uv.now() - state.idle_start
    if idle >= IDLE_MS and not state.win then
      -- Only dream in code buffers, not on dashboards/terminals
      local ft = vim.bo.filetype
      if ft == "" or ft == "snacks_dashboard" or ft == "alpha" or ft == "TelescopePrompt" then return end
      dream()
    end
  end))
  vim.notify("dreams enabled (will surface after 90s idle)")
end

function M.disable()
  state.enabled = false
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  close_window()
  pcall(vim.api.nvim_del_augroup_by_name, "user_dreams")
  vim.notify("dreams disabled")
end

function M.toggle() if state.enabled then M.disable() else M.enable() end end
function M.now() dream() end  -- force a dream right now, no waiting

function M.setup()
  vim.api.nvim_create_user_command("Dreams",    M.toggle, { desc = "Toggle idle-time dream generation" })
  vim.api.nvim_create_user_command("DreamNow",  M.now,    { desc = "Force a dream now" })
end

return M
