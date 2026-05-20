-- Hints: a tiny floating chip in the bottom-right that teaches you the
-- environment as you encounter new contexts. Each hint fires at most N
-- times (default 3) per install — once you've seen "first markdown file →
-- try :MarkdownPreviewToggle" a few times, it stops nagging.
--
-- Hint registry — anyone can add hints via M.add({ id, when, text, key }).
-- The fired count is persisted in hints_seen.json so it survives restarts.
local M = {}

local brand = require("user.brand")

local STATE_FILE = vim.fn.stdpath("state") .. "/hints_seen.json"
local SHOW_MS    = 6000     -- on-screen lifetime
local FADE_MS    = 700
local MAX_PER_HINT_DEFAULT = 3
local _seen = {}            -- { [id] = shown_count }

local function load_state()
  local f = io.open(STATE_FILE, "r"); if not f then return end
  local ok, p = pcall(vim.json.decode, f:read("*a"), { luanil = { object = true, array = true } })
  f:close()
  if ok and type(p) == "table" then _seen = p end
end

local function save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  local f = io.open(STATE_FILE, "w")
  if f then f:write(vim.json.encode(_seen)); f:close() end
end

-- ─── registry ────────────────────────────────────────────────────────────
-- A hint:
--   id        : stable string, used for the seen counter
--   when(ctx) : returns true when the hint applies right now
--   text      : short message; "try {{key}}" is interpolated
--   key       : the keymap/cmd to highlight in the chip
--   max_shows : override (default 3)
M._registry = {}

function M.add(hint)
  table.insert(M._registry, hint)
end

-- Built-in hints — added at setup(). Anything project-specific can call
-- M.add() from .nvim/init.lua or similar.
local function _builtins()
  M.add({ id = "first_markdown",
    when = function() return vim.bo.filetype == "markdown" end,
    text = "this is a markdown file · preview or present",
    key  = "<leader>P · :MarkdownPreviewToggle" })

  M.add({ id = "first_python",
    when = function() return vim.bo.filetype == "python" end,
    text = "python REPL open",
    key  = "<leader>rt · :REPL" })

  M.add({ id = "first_rust",
    when = function() return vim.bo.filetype == "rust" end,
    text = "rust project — task runner or cargo",
    key  = "<leader>Tr · :Task" })

  M.add({ id = "first_http",
    when = function() return vim.bo.filetype == "http" or vim.bo.filetype == "rest" end,
    text = "send the request under cursor",
    key  = "<leader><space> (suggest) · :KulalaRun" })

  M.add({ id = "first_conflict",
    when = function()
      local line = vim.api.nvim_get_current_line() or ""
      return line:sub(1, 7) == "<<<<<<<"
    end,
    text = "merge conflict · time-machine your way back",
    key  = "<leader>gT" })

  M.add({ id = "first_jira_key",
    when = function()
      local cword = vim.fn.expand("<cword>") or ""
      return cword:match("^[A-Z][A-Z0-9]+%-%d+$") ~= nil
    end,
    text = "jira key under cursor — peek the ticket",
    key  = "<leader>jK" })

  M.add({ id = "first_huge_file",
    when = function() return vim.api.nvim_buf_line_count(0) > 5000 end,
    text = "big file · :SymTree gives you an outline",
    key  = "<leader>uo" })

  M.add({ id = "first_dock_tab",
    when = function() return vim.fn.tabpagenr("$") > 1 end,
    text = "you have tabs · :TabRename labels them",
    key  = "<leader><tab>r" })

  M.add({ id = "first_lsp",
    when = function() return #vim.lsp.get_clients({ bufnr = 0 }) > 0 end,
    text = "LSP attached · peek a definition without jumping",
    key  = "gp" })

  M.add({ id = "first_focus_block",
    when = function()
      local h = tonumber(os.date("%H")) or 0
      return h >= 8 and h <= 18 and vim.bo.filetype ~= ""
    end,
    text = "workday — what should I do?",
    key  = "<leader><space>" })
end

-- ─── floating chip render ────────────────────────────────────────────────
local _current  = nil   -- { buf, win, timer }
local function apply_hl()
  local c = brand.c
  local set = vim.api.nvim_set_hl
  set(0, "UserHintsBorder", { fg = c.accent, bg = "NONE" })
  set(0, "UserHintsBody",   { fg = c.text,   bg = c.surface })
  set(0, "UserHintsKey",    { fg = c.bg,     bg = c.accent, bold = true })
  set(0, "UserHintsFade",   { fg = c.muted,  bg = c.surface })
end

local function _close_current()
  if not _current then return end
  if _current.timer then
    pcall(function() _current.timer:stop() end)
    pcall(function() if not _current.timer:is_closing() then _current.timer:close() end end)
  end
  if _current.win and vim.api.nvim_win_is_valid(_current.win) then
    pcall(vim.api.nvim_win_close, _current.win, true)
  end
  _current = nil
end

local function _show(hint)
  _close_current()
  apply_hl()
  local body = hint.text
  local key  = hint.key or ""
  -- Layout: " ◆ <body>   <key> "
  local lead = " ◆ "
  local line = lead .. body .. "   " .. key .. " "
  local width = math.max(30, vim.api.nvim_strwidth(line) + 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  local ns = vim.api.nvim_create_namespace("user_hints")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_line = 1, hl_group = "UserHintsBody" })
  -- Key chip highlight (everything after the 3-space separator)
  if key ~= "" then
    local sep_at = line:find("   ", 1, true)
    if sep_at then
      vim.api.nvim_buf_set_extmark(buf, ns, 0, sep_at + 2, { end_col = #line, hl_group = "UserHintsKey" })
    end
  end

  local row = vim.o.lines - 4   -- above the status line + a margin
  local col = vim.o.columns - width - 2
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor", style = "minimal", border = "rounded",
    row = row, col = col, width = width, height = 1,
    focusable = false, zindex = 220, noautocmd = true,
  })
  pcall(function()
    vim.wo[win].winhighlight = "FloatBorder:UserHintsBorder,Normal:UserHintsBody"
    vim.wo[win].winblend = 0
  end)

  _current = { buf = buf, win = win }
  _current.timer = vim.uv.new_timer()
  _current.timer:start(SHOW_MS - FADE_MS, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_line = 1, hl_group = "UserHintsFade" })
    end
    local close_timer = vim.uv.new_timer()
    close_timer:start(FADE_MS, 0, vim.schedule_wrap(function()
      pcall(function() close_timer:stop(); close_timer:close() end)
      _close_current()
    end))
  end))
end

-- ─── trigger ─────────────────────────────────────────────────────────────
-- Walk the registry, fire the first hint whose `when` returns true and
-- whose seen count is below its max. Quiet on errors.
local _checking = false   -- reentrancy guard
local function _maybe_hint()
  if _checking or _current then return end   -- one at a time
  _checking = true
  for _, h in ipairs(M._registry) do
    local cap = h.max_shows or MAX_PER_HINT_DEFAULT
    local count = _seen[h.id] or 0
    if count < cap then
      local ok, fired = pcall(h.when)
      if ok and fired then
        _seen[h.id] = count + 1; save_state()
        _show(h)
        break
      end
    end
  end
  _checking = false
end

function M.reset(id)
  if id then _seen[id] = nil else _seen = {} end
  save_state()
  brand.notify(id and ("reset hint · " .. id) or "all hints reset", nil, { title = "hints" })
end

function M.list()
  local items = {}
  for _, h in ipairs(M._registry) do
    local count = _seen[h.id] or 0
    local cap = h.max_shows or MAX_PER_HINT_DEFAULT
    table.insert(items, ("  %-22s  %d/%d  %s"):format(h.id, count, cap, h.text))
  end
  vim.notify(table.concat(items, "\n"), vim.log.levels.INFO, { title = "hints registry" })
end

-- ─── setup ───────────────────────────────────────────────────────────────
function M.setup()
  load_state()
  _builtins()

  local grp = vim.api.nvim_create_augroup("user_hints", { clear = true })
  -- Throttle: at most one check per 800ms across all the firing events
  local last_check = 0
  local function _throttled()
    local now = vim.uv.now()
    if now - last_check < 800 then return end
    last_check = now
    vim.schedule(_maybe_hint)
  end
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType", "CursorHold", "TabEnter" }, {
    group = grp, callback = _throttled,
  })

  vim.api.nvim_create_user_command("HintsReset",
    function(a) M.reset(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Reset a hint by id (or all if no arg)" })
  vim.api.nvim_create_user_command("HintsList", M.list,
    { desc = "Show all registered hints and their shown count" })
  vim.api.nvim_create_user_command("HintsDismiss", _close_current,
    { desc = "Hide the current hint, if any" })
end

return M
