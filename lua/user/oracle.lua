-- Oracle: ask a yes/no question. Watch an animated coin spin until it lands.
-- :Oracle <question>  — coin lands on AI's actual answer (or pure chance).
local M = {}

local FACES = { "(◐)", "(◓)", "(◑)", "(◒)" }  -- spinning circle
local MODEL = "claude-haiku-4-5-20251001"
local ENDPOINT = "https://api.anthropic.com/v1/messages"

local state = { win = nil, buf = nil, timer = nil }

local function key() return vim.env.ANTHROPIC_API_KEY end

local function close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

local function render(content, color)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local lines = vim.split(content, "\n")
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  if color then
    vim.api.nvim_set_hl(0, "OracleFx", { fg = color, bold = true })
    vim.wo[state.win].winhighlight = "Normal:OracleFx,FloatBorder:OracleFx,FloatTitle:OracleFx"
  end
end

local function open_window(title)
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  local W, H = 36, 7
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", focusable = false, noautocmd = true,
    border = "double", title = " ☉ " .. (title or "oracle") .. " ", title_pos = "center",
    width = W, height = H,
    row = math.floor((vim.o.lines - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
end

local function spin_animation(duration_ms, on_done)
  local start = vim.uv.now()
  local idx = 1
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 90, vim.schedule_wrap(function()
    if vim.uv.now() - start >= duration_ms then
      state.timer:stop(); state.timer:close(); state.timer = nil
      on_done()
      return
    end
    idx = (idx % #FACES) + 1
    render(string.format("\n\n           %s\n\n        spinning…", FACES[idx]), "#b4befe")
  end))
end

local function reveal(answer, color)
  local ascii = {
    yes = "          ✓\n         ━━━\n          YES",
    no  = "          ✗\n         ━━━\n           NO",
    huh = "          ?\n         ━━━\n        UNCLEAR",
  }
  render("\n\n" .. (ascii[answer] or ascii.huh) .. "\n", color or "#cba6f7")
  vim.defer_fn(close, 4500)
end

local function ask_claude(question, cb)
  local k = key(); if not k then cb(nil); return end
  vim.system({
    "curl", "-sS",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. k,
    "-H", "anthropic-version: 2023-06-01",
    "-d", vim.json.encode({
      model = MODEL, max_tokens = 10,
      messages = { { role = "user", content =
        "Answer this yes/no question with EXACTLY one word: 'yes', 'no', or 'unclear'. "
        .. "No punctuation, no explanation.\n\nQuestion: " .. question } },
    }),
    ENDPOINT,
  }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then cb(nil); return end
      local ok, parsed = pcall(vim.json.decode, res.stdout or "")
      local txt = (ok and parsed.content and parsed.content[1] and parsed.content[1].text or ""):lower():gsub("[%p%s]+", "")
      if txt:find("^yes") then cb("yes")
      elseif txt:find("^no") then cb("no")
      else cb("huh") end
    end)
  end)
end

function M.ask(args)
  local q = (args.args or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if q == "" then
    vim.ui.input({ prompt = "Ask the oracle (yes/no): " }, function(input)
      if input and input ~= "" then M.ask({ args = input }) end
    end)
    return
  end
  open_window(q:sub(1, 30))
  spin_animation(2400, function()
    if key() then
      ask_claude(q, function(answer)
        local colors = { yes = "#a6e3a1", no = "#f38ba8", huh = "#f9e2af" }
        reveal(answer or "huh", colors[answer or "huh"])
      end)
    else
      -- No API key: pure coin flip
      local r = math.random(3)
      local answer = r == 1 and "yes" or r == 2 and "no" or "huh"
      reveal(answer, ({ yes = "#a6e3a1", no = "#f38ba8", huh = "#f9e2af" })[answer])
    end
  end)
end

function M.setup() vim.api.nvim_create_user_command("Oracle", M.ask, { nargs = "?", desc = "Ask the AI oracle a yes/no" }) end
return M
