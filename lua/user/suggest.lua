-- Suggest: a contextual action panel that LIVES.
--
-- Opens with <Space><Space>. As you work — fix a diagnostic, save a buffer,
-- stage a hunk — the panel re-ranks in place. Picks are remembered: actions
-- you take in a given context get a bonus next time that context appears.
-- Two-action sequences (you fix → then commit) get a "next-step" bonus
-- when the second condition arrives.
local M = {}

-- ─── persistent learning store ─────────────────────────────────────────────
local STATE_FILE = vim.fn.stdpath("state") .. "/suggest_state.json"
local state = {
  usage     = {}, -- id -> { count, last_ts }
  ctx_picks = {}, -- fingerprint -> { id -> count }
  sequences = {}, -- prev_id -> { next_id -> count }  (within 2 min)
}
local last_pick = { id = nil, ts = 0 }

local function load_state()
  local f = io.open(STATE_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if ok and type(parsed) == "table" then state = vim.tbl_deep_extend("force", state, parsed) end
end

local function save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  local f = io.open(STATE_FILE, "w")
  if f then f:write(vim.json.encode(state)); f:close() end
end

-- ─── context probe ─────────────────────────────────────────────────────────
local _git_cache = { t = 0, dirty = nil, in_git = false }

local function git_state(cwd)
  local now = vim.uv.now()
  if now - _git_cache.t < 3000 then return _git_cache.in_git, _git_cache.dirty end
  if vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --is-inside-work-tree 2>/dev/null")[1] == "true" then
    _git_cache.in_git = true
    _git_cache.dirty = #vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " status --porcelain 2>/dev/null")
  else
    _git_cache.in_git = false
    _git_cache.dirty = 0
  end
  _git_cache.t = now
  return _git_cache.in_git, _git_cache.dirty
end

-- ─── extra detectors used by some actions ────────────────────────────────
local function find_test_pair(name, ft)
  -- For a given source file, look up the obvious test counterpart.
  if name == "" then return nil end
  local dir  = vim.fn.fnamemodify(name, ":h")
  local base = vim.fn.fnamemodify(name, ":t:r")
  local ext  = vim.fn.fnamemodify(name, ":e")
  local candidates = {}
  if base:match("_test$") or base:match("%.test$") or base:match("%.spec$") then
    -- We're in a test file — point at the implementation
    local stem = base:gsub("_test$", ""):gsub("%.test$", ""):gsub("%.spec$", "")
    table.insert(candidates, dir .. "/" .. stem .. "." .. ext)
    table.insert(candidates, dir:gsub("/tests?$", "/src") .. "/" .. stem .. "." .. ext)
  else
    -- Source file — find the test
    table.insert(candidates, dir .. "/" .. base .. "_test." .. ext)         -- go
    table.insert(candidates, dir .. "/" .. base .. ".test." .. ext)         -- js/ts
    table.insert(candidates, dir .. "/" .. base .. ".spec." .. ext)         -- ruby/some js
    table.insert(candidates, dir .. "/test_" .. base .. "." .. ext)         -- python convention
    table.insert(candidates, dir:gsub("/src", "/tests") .. "/test_" .. base .. "." .. ext)
    table.insert(candidates, dir:gsub("/src", "/test") .. "/" .. base .. "." .. ext)
  end
  for _, c in ipairs(candidates) do
    if vim.uv.fs_stat(c) then return c end
  end
end

local function find_readme(cwd)
  for _, n in ipairs({ "README.md", "Readme.md", "readme.md", "README.rst", "README.txt", "README" }) do
    if vim.uv.fs_stat(cwd .. "/" .. n) then return cwd .. "/" .. n end
  end
end

local function find_env_file(cwd)
  for _, n in ipairs({ ".env", ".env.local", ".envrc" }) do
    if vim.uv.fs_stat(cwd .. "/" .. n) then return cwd .. "/" .. n end
  end
end

local function url_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  -- Walk outward from cursor to find http(s) URL containing it
  local s, e = 1, #line
  while s <= e do
    local match_s, match_e = line:find("https?://[%w_%-./?#&=%%~+:!,;@$()*]+", s)
    if not match_s then return nil end
    if match_s <= col + 1 and match_e >= col then return line:sub(match_s, match_e) end
    s = match_e + 1
  end
end

local function last_other_file()
  -- Most-recently-used buffer that isn't the current one (top of jumplist isn't quite right).
  local cur = vim.api.nvim_get_current_buf()
  local best, best_mt = nil, 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= cur and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" then
        local stat = vim.uv.fs_stat(name)
        local mt = stat and stat.mtime.sec or 0
        if mt > best_mt then best, best_mt = b, mt end
      end
    end
  end
  return best
end

local function has_workspace_snapshot(cwd)
  local snap = vim.fn.stdpath("state") .. "/workspaces/" .. cwd:gsub("/", "%%") .. ".json"
  return vim.uv.fs_stat(snap) ~= nil
end

local function pomo_active()
  local ok, pomo = pcall(require, "pomo")
  if not ok then return false end
  local t = pomo.get_first_to_finish()
  return t ~= nil
end

local function ctx()
  local bufnr = vim.api.nvim_get_current_buf()
  local diags = vim.diagnostic.get(bufnr)
  local cwd = vim.fn.getcwd()
  local in_git, dirty = git_state(cwd)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return {
    bufnr        = bufnr,
    ft           = vim.bo[bufnr].filetype,
    name         = name,
    short_name   = vim.fn.fnamemodify(name, ":t"),
    modified     = vim.bo[bufnr].modified,
    diags        = diags,
    err_count    = #vim.tbl_filter(function(d) return d.severity == 1 end, diags),
    hour         = tonumber(os.date("%H")),
    line         = vim.api.nvim_win_get_cursor(0)[1],
    cwd          = cwd,
    in_git       = in_git,
    git_dirty    = dirty,
    -- enriched signals
    test_pair    = (name ~= "" and find_test_pair(name, vim.bo[bufnr].filetype)) or nil,
    readme       = find_readme(cwd),
    env_file     = find_env_file(cwd),
    cursor_url   = url_under_cursor(),
    last_other   = last_other_file(),
    has_session  = has_workspace_snapshot(cwd),
    pomo_active  = pomo_active(),
    tab_count    = vim.fn.tabpagenr("$"),
  }
end

-- Forward declarations — definitions live further down (lines ~540, ~551).
-- Lua locals declared via `local function` aren't visible to earlier code in
-- the same scope, so without these, `fingerprint()` resolves project_name
-- as a global (nil) and crashes on first :Suggest call.
local find_project_root, project_name

-- A short string identifying the situation. Same situation = same fingerprint.
-- Project name is the leading segment so learning stays project-scoped:
-- a `fix → commit` sequence in repo A doesn't bleed into repo B's suggestions.
local function fingerprint(c)
  return table.concat({
    project_name(c.cwd),
    c.err_count > 0 and "E" or "_",
    c.modified  and "M" or "_",
    c.in_git and ((c.git_dirty > 0) and "D" or "C") or "_",
    c.ft ~= "" and c.ft or "?",
    math.floor((c.hour or 0) / 6),
  }, ":")
end

-- ─── learning helpers ──────────────────────────────────────────────────────
local function bump_usage(id)
  state.usage[id] = state.usage[id] or { count = 0, last_ts = 0 }
  state.usage[id].count = state.usage[id].count + 1
  state.usage[id].last_ts = os.time()
end
local function bump_ctx(fp, id)
  state.ctx_picks[fp] = state.ctx_picks[fp] or {}
  state.ctx_picks[fp][id] = (state.ctx_picks[fp][id] or 0) + 1
  -- A pick is an implicit endorsement — reset any skips against this id in
  -- this context so it doesn't stay suppressed after the user came around.
  if state.ctx_skips and state.ctx_skips[fp] then
    state.ctx_skips[fp][id] = nil
  end
end

local function bump_skip(fp, id)
  state.ctx_skips = state.ctx_skips or {}
  state.ctx_skips[fp] = state.ctx_skips[fp] or {}
  state.ctx_skips[fp][id] = (state.ctx_skips[fp][id] or 0) + 1
end
local function bump_seq(from, to)
  state.sequences[from] = state.sequences[from] or {}
  state.sequences[from][to] = (state.sequences[from][to] or 0) + 1
end

local function recency_bonus(id)
  local u = state.usage[id]; if not u then return 0 end
  local age_min = (os.time() - u.last_ts) / 60
  if age_min < 60 then return 10 - (age_min / 6) end
  return 0
end

-- ─── action catalog ────────────────────────────────────────────────────────
local ACTIONS = {
  {
    id = "fix_error",
    when = function(c) return c.err_count > 0 and 100 or nil end,
    label = function(c)
      local first = vim.tbl_filter(function(d) return d.severity == 1 end, c.diags)[1]
      local msg = (first and first.message or ""):gsub("\n.*", ""):sub(1, 50)
      return ("fix · %s"):format(msg)
    end,
    run = function(c)
      local first = vim.tbl_filter(function(d) return d.severity == 1 end, c.diags)[1]
      if first then pcall(vim.api.nvim_win_set_cursor, 0, { first.lnum + 1, first.col }) end
      vim.cmd("Explain")
    end,
  },
  {
    id = "next_diag",
    when = function(c) return #c.diags > 1 and 70 or nil end,
    label = function(c) return ("walk diagnostics · %d remaining"):format(#c.diags) end,
    run = function() vim.diagnostic.jump({ count = 1, float = true }) end,
  },
  {
    id = "save",
    when = function(c) return c.modified and 85 or nil end,
    label = function() return "save this buffer" end,
    run = function() vim.cmd("write") end,
  },
  {
    id = "commit",
    when = function(c) return c.git_dirty > 0 and 75 or nil end,
    label = function(c) return ("commit · %d file%s changed"):format(c.git_dirty, c.git_dirty == 1 and "" or "s") end,
    run = function() pcall(vim.cmd, "Neogit commit") end,
  },
  {
    id = "git_overview",
    when = function(c) return c.git_dirty > 0 and 55 or nil end,
    label = function() return "open lazygit" end,
    run = function() pcall(vim.cmd, "LazyGit") end,
  },
  {
    id = "run_test",
    when = function(c)
      if c.ft == "python" or c.ft == "go" or c.ft == "rust" or c.ft == "javascript" or c.ft == "typescript" then return 65 end
    end,
    label = function() return "run nearest test" end,
    run = function() pcall(vim.cmd, "Neotest run") end,
  },
  {
    id = "open_repl",
    when = function(c)
      if c.ft == "python" or c.ft == "lua" or c.ft == "javascript" or c.ft == "typescript"
         or c.ft == "ruby" or c.ft == "clojure" then return 50 end
    end,
    label = function(c) return "open " .. c.ft .. " repl" end,
    run = function() require("user.repl").toggle() end,
  },
  {
    id = "venv",
    when = function(c) return c.ft == "python" and 45 or nil end,
    label = function() return "select python venv" end,
    run = function() pcall(vim.cmd, "VenvSelect") end,
  },
  {
    id = "preview_md",
    when = function(c) return c.ft == "markdown" and 60 or nil end,
    label = function() return "preview markdown in browser" end,
    run = function() pcall(vim.cmd, "MarkdownPreviewToggle") end,
  },
  {
    id = "present_md",
    when = function(c) return c.ft == "markdown" and #vim.api.nvim_buf_get_lines(0, 0, -1, false) > 5 and 40 or nil end,
    label = function() return "present this as slides" end,
    run = function() require("user.present").start() end,
  },
  {
    id = "ai_explain",
    when = function(c) return c.line and 35 or nil end,
    label = function() return "ask AI about this code" end,
    run = function() vim.cmd("AI explain this") end,
  },
  {
    id = "find_file",
    when = function() return 30 end,
    label = function() return "find a file" end,
    run = function() pcall(vim.cmd, "Telescope find_files") end,
  },
  {
    id = "grep",
    when = function() return 28 end,
    label = function() return "grep the project" end,
    run = function() pcall(vim.cmd, "Telescope live_grep") end,
  },
  {
    id = "spotlight",
    when = function() return 25 end,
    label = function() return "spotlight (everything)" end,
    run = function() require("user.spotlight").open() end,
  },
  {
    id = "today",
    when = function(c) return c.hour >= 17 and 40 or 20 end,
    label = function() return "what did I do today" end,
    run = function() require("user.today").show() end,
  },
  {
    id = "wind_down",
    when = function(c) return (c.hour >= 22 or c.hour < 5) and 50 or nil end,
    label = function() return "save workspace · wind down" end,
    run = function() pcall(function() require("user.workspace").save() end) end,
  },
  {
    id = "homunculus",
    when = function(c) return c.hour >= 18 and c.git_dirty > 0 and 35 or nil end,
    label = function() return "write today's journal entry" end,
    run = function() require("user.homunculus").wake() end,
  },

  -- ─── new wave: enriched-context actions ─────────────────────────────────
  {
    id = "tabs_pick",
    -- Surfaces once you have enough tabs that scanning the tabline is slower
    -- than picking by name. Scales with count so a 6-tab session beats a
    -- 4-tab one for priority.
    when = function(c) return c.tab_count >= 4 and (30 + c.tab_count) or nil end,
    label = function(c) return ("pick a tab · %d open"):format(c.tab_count) end,
    run = function() require("user.tabs").pick() end,
  },
  {
    id = "open_test_pair",
    when = function(c) return c.test_pair and 58 or nil end,
    label = function(c)
      local is_test = c.short_name:match("_test") or c.short_name:match("%.test") or c.short_name:match("%.spec") or c.short_name:match("^test_")
      return (is_test and "jump to implementation · " or "open paired test · ") .. vim.fn.fnamemodify(c.test_pair, ":t")
    end,
    run = function(c) vim.cmd("edit " .. vim.fn.fnameescape(c.test_pair)) end,
  },
  {
    id = "swap_other",
    when = function(c) return c.last_other and 32 or nil end,
    label = function(c) return "switch to " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(c.last_other), ":t") end,
    run = function(c) vim.cmd("buffer " .. c.last_other) end,
  },
  {
    id = "open_readme",
    when = function(c) return c.readme and (c.short_name == "" or c.short_name:match("^README") == nil) and 22 or nil end,
    label = function() return "open project README" end,
    run = function(c) vim.cmd("edit " .. vim.fn.fnameescape(c.readme)) end,
  },
  {
    id = "open_env",
    when = function(c) return c.env_file and 18 or nil end,
    label = function(c) return "edit " .. vim.fn.fnamemodify(c.env_file, ":t") end,
    run = function(c) vim.cmd("edit " .. vim.fn.fnameescape(c.env_file)) end,
  },
  {
    id = "open_url",
    when = function(c) return c.cursor_url and 80 or nil end,
    label = function(c) return "open " .. c.cursor_url:sub(1, 50) .. " in browser" end,
    run = function(c) vim.ui.open(c.cursor_url) end,
  },
  {
    id = "restore_session",
    when = function(c)
      -- Only at start of a session (no other buffers loaded yet, line 1 col 0, empty buf)
      local n = 0
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then n = n + 1 end
      end
      return c.has_session and n <= 1 and 92 or nil
    end,
    label = function() return "restore last session here" end,
    run = function() require("user.workspace").load() end,
  },
  {
    id = "focus_block",
    when = function(c) return not c.pomo_active and 18 or nil end,
    label = function() return "start a 25-min focus block" end,
    run = function() pcall(vim.cmd, "TimerStart 25m focus") end,
  },
  {
    id = "browse_todos",
    when = function() return 24 end,
    label = function() return "browse project TODOs" end,
    run = function() pcall(vim.cmd, "TodoTelescope") end,
  },
  {
    id = "format_buffer",
    when = function(c) return c.modified and 30 or nil end,
    label = function() return "format this buffer" end,
    run = function() pcall(vim.lsp.buf.format) end,
  },
  {
    id = "code_action",
    when = function(c) return c.line and 28 or nil end,
    label = function() return "show code actions here" end,
    run = function() pcall(vim.lsp.buf.code_action) end,
  },
  {
    id = "rest_send",
    when = function(c) return (c.ft == "http" or c.ft == "rest") and 80 or nil end,
    label = function() return "send this REST request" end,
    run = function() pcall(function() require("kulala").run() end) end,
  },
  {
    id = "yank_ring",
    when = function() return 22 end,
    label = function() return "browse yank ring" end,
    run = function() require("user.yankring").pick() end,
  },

  -- ─── self-aware: actions that surface our own user.* modules ────────────
  {
    id = "take_tour",
    when = function(c)
      -- Only when tour hasn't been seen AND buffer is empty (likely fresh launch)
      if vim.uv.fs_stat(vim.fn.stdpath("state") .. "/.toured") then return nil end
      return c.name == "" and 90 or nil
    end,
    label = function() return "take the 2-min tour" end,
    run = function() require("user.tour").start() end,
  },
  {
    id = "name_playbook",
    when = function()
      -- Are there strong, unnamed sequences we could name?
      local seqs = state.sequences or {}
      local strong = 0
      for _, trans in pairs(seqs) do
        for _, count in pairs(trans) do if count >= 5 then strong = strong + 1 end end
      end
      if strong == 0 then return nil end
      local f = io.open(vim.fn.stdpath("state") .. "/playbooks.json", "r")
      local named = 0
      if f then
        local ok, parsed = pcall(vim.json.decode, f:read("*a")); f:close()
        if ok and parsed then named = vim.tbl_count(parsed.names or {}) end
      end
      return strong > named and 40 or nil
    end,
    label = function() return "name your top playbook (you have strong unnamed chains)" end,
    run = function() require("user.playbooks").show() end,
  },
  {
    id = "playbooks_panel",
    when = function()
      local seqs = state.sequences or {}
      local n = 0
      for _, trans in pairs(seqs) do
        for _, c in pairs(trans) do if c >= 3 then n = n + 1 end end
      end
      return n >= 3 and 26 or nil
    end,
    label = function() return "browse learned playbooks" end,
    run = function() require("user.playbooks").show() end,
  },
  {
    id = "open_journal",
    when = function()
      local p = vim.fn.expand("~/notes/journal/" .. os.date("%Y-%m-%d") .. ".md")
      return vim.uv.fs_stat(p) and 30 or nil
    end,
    label = function() return "open today's journal entry" end,
    run = function()
      local p = vim.fn.expand("~/notes/journal/" .. os.date("%Y-%m-%d") .. ".md")
      vim.cmd("edit " .. vim.fn.fnameescape(p))
    end,
  },
  {
    id = "open_yesterday_journal",
    when = function()
      local today = vim.fn.expand("~/notes/journal/" .. os.date("%Y-%m-%d") .. ".md")
      if vim.uv.fs_stat(today) then return nil end   -- prefer today's if it exists
      local yesterday = vim.fn.expand("~/notes/journal/" .. os.date("%Y-%m-%d", os.time() - 86400) .. ".md")
      return vim.uv.fs_stat(yesterday) and 16 or nil
    end,
    label = function() return "open yesterday's journal entry" end,
    run = function()
      vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.expand("~/notes/journal/" .. os.date("%Y-%m-%d", os.time() - 86400) .. ".md")))
    end,
  },
  {
    id = "run_macro",
    when = function()
      local f = io.open(vim.fn.stdpath("state") .. "/macros.json", "r"); if not f then return nil end
      local ok, parsed = pcall(vim.json.decode, f:read("*a")); f:close()
      local n = (ok and parsed) and vim.tbl_count(parsed) or 0
      return n > 0 and 20 or nil
    end,
    label = function()
      local f = io.open(vim.fn.stdpath("state") .. "/macros.json", "r")
      local n = 0
      if f then local ok, p = pcall(vim.json.decode, f:read("*a")); f:close(); n = (ok and p) and vim.tbl_count(p) or 0 end
      return ("run a saved macro · %d available"):format(n)
    end,
    run = function() require("user.macroreg").pick() end,
  },
  {
    id = "engage_cockpit",
    when = function()
      local ok, cockpit = pcall(require, "user.cockpit")
      if not ok then return nil end
      if cockpit.status and cockpit.status() then return nil end  -- already engaged
      return 16
    end,
    label = function() return "engage cockpit (full HUD layout)" end,
    run = function() require("user.cockpit").engage() end,
  },
  {
    id = "review_state",
    when = function()
      local total = 0
      local dir = vim.fn.stdpath("state")
      for _, n in ipairs({ "suggest_state.json", "playbooks.json", "yankring.json",
                           "macros.json", "tiny_world.json", "commandeer_state.json", "lsp.log" }) do
        local s = vim.uv.fs_stat(dir .. "/" .. n)
        if s then total = total + s.size end
      end
      local mb = math.floor(total / 1024 / 1024)
      return mb >= 50 and 24 or nil
    end,
    label = function()
      local total = 0
      local dir = vim.fn.stdpath("state")
      for _, n in ipairs({ "suggest_state.json", "playbooks.json", "yankring.json",
                           "macros.json", "tiny_world.json", "commandeer_state.json", "lsp.log" }) do
        local s = vim.uv.fs_stat(dir .. "/" .. n); if s then total = total + s.size end
      end
      return ("review user state · %dMB total"):format(math.floor(total / 1024 / 1024))
    end,
    run = function() require("user.state").show() end,
  },
  {
    id = "jira_branch_issue",
    when = function()
      local ok, jira = pcall(require, "user.jira"); if not ok then return nil end
      return jira.current_ticket() and 78 or nil
    end,
    label = function()
      local jira = require("user.jira")
      return "jira · open " .. jira.current_ticket() .. " (this branch)"
    end,
    run = function()
      local jira = require("user.jira")
      jira.show_issue(jira.current_ticket())
    end,
  },
  {
    id = "jira_branch_comment",
    when = function()
      local ok, jira = pcall(require, "user.jira"); if not ok then return nil end
      return jira.current_ticket() and 36 or nil
    end,
    label = function()
      return "jira · comment on " .. require("user.jira").current_ticket()
    end,
    run = function()
      local jira = require("user.jira")
      jira.prompt_comment(jira.current_ticket())
    end,
  },
  {
    id = "jira_mine",
    when = function() return (vim.env.JIRA_BASE_URL or "") ~= "" and 22 or nil end,
    label = function() return "jira · my open issues" end,
    run = function() require("user.jira").show_mine() end,
  },
  {
    id = "jira_peek",
    when = function()
      if (vim.env.JIRA_BASE_URL or "") == "" then return nil end
      local cword = vim.fn.expand("<cword>")
      if cword:match("^[A-Z][A-Z0-9]+%-%d+$") then return 84 end
      local line = vim.api.nvim_get_current_line() or ""
      return line:match("[A-Z][A-Z0-9]+%-%d+") and 40 or nil
    end,
    label = function()
      local cword = vim.fn.expand("<cword>")
      local k = cword:match("^[A-Z][A-Z0-9]+%-%d+$")
        or (vim.api.nvim_get_current_line() or ""):match("[A-Z][A-Z0-9]+%-%d+")
      return "jira · peek " .. (k or "?")
    end,
    run = function() require("user.jira").peek_under_cursor() end,
  },
  {
    id = "jira_recent",
    when = function()
      if (vim.env.JIRA_BASE_URL or "") == "" then return nil end
      -- jira._cache is module-private; fall back to checking the persisted
      -- cache file for a non-trivial size (empty caches are < 80B).
      local st = vim.uv.fs_stat(vim.fn.stdpath("state") .. "/jira_cache.json")
      return (st and st.size > 80) and 20 or nil
    end,
    label = function() return "jira · recently viewed" end,
    run = function() require("user.jira").show_recent() end,
  },
  {
    id = "confluence_cword",
    when = function(c)
      if (vim.env.JIRA_BASE_URL or "") == "" then return nil end
      local w = vim.fn.expand("<cword>")
      return (w and #w >= 3 and c.name ~= "") and 18 or nil
    end,
    label = function()
      local w = vim.fn.expand("<cword>")
      return "confluence · search for `" .. w .. "`"
    end,
    run = function() require("user.confluence").show_search(vim.fn.expand("<cword>")) end,
  },
  {
    id = "quick_shell",
    when = function() return 14 end,
    label = function() return "run a quick shell command" end,
    run = function()
      vim.ui.input({ prompt = "shell> " }, function(cmd)
        if not cmd or cmd == "" then return end
        require("toggleterm.terminal").Terminal:new({
          cmd = cmd, direction = "float", close_on_exit = false,
        }):toggle()
      end)
    end,
  },
}

-- ─── per-project actions (.suggest.lua) ───────────────────────────────────
-- A project can drop a file at its root that returns an array of action
-- specs in the same shape as the catalog. They're merged in at rank time.
-- Re-read on mtime change. Tied to cwd, so switching projects swaps them.
local _project = { cwd = nil, mtime = 0, path = nil, actions = {} }

-- Definitions assign into the forward-declared locals (no `local` keyword).
function find_project_root(cwd)
  local dir = cwd
  for _ = 1, 8 do
    if vim.uv.fs_stat(dir .. "/.git") or vim.uv.fs_stat(dir .. "/.suggest.lua") then return dir end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then return nil end
    dir = parent
  end
  return cwd
end

function project_name(cwd)
  local root = find_project_root(cwd) or cwd
  return vim.fn.fnamemodify(root, ":t")
end

local function validate_action(entry, src)
  if type(entry) ~= "table" then return false, "not a table" end
  if type(entry.id) ~= "string" or entry.id == "" then return false, "missing id" end
  if type(entry.run) ~= "function" then return false, "missing run function" end
  if entry.when and type(entry.when) ~= "function" then return false, "when must be function" end
  if entry.label and type(entry.label) ~= "function" and type(entry.label) ~= "string" then return false, "label must be string or function" end
  return true
end

local function load_project_actions(cwd)
  local root = find_project_root(cwd)
  if not root then return {} end
  local path = root .. "/.suggest.lua"
  local stat = vim.uv.fs_stat(path)
  if not stat then
    _project = { cwd = cwd, mtime = 0, path = nil, actions = {} }
    return {}
  end
  -- Cache hit
  if _project.cwd == cwd and _project.path == path and _project.mtime == stat.mtime.sec then
    return _project.actions
  end
  -- Reload
  local ok, result = pcall(dofile, path)
  if not ok then
    pcall(function()
      require("user.brand").notify(".suggest.lua failed: " .. tostring(result), vim.log.levels.ERROR, { title = "suggest" })
    end)
    _project = { cwd = cwd, mtime = stat.mtime.sec, path = path, actions = {} }
    return {}
  end
  if type(result) ~= "table" then
    pcall(function()
      require("user.brand").notify(".suggest.lua must return a table", vim.log.levels.WARN, { title = "suggest" })
    end)
    _project = { cwd = cwd, mtime = stat.mtime.sec, path = path, actions = {} }
    return {}
  end
  -- Validate each entry; namespace IDs with "proj." so they don't collide.
  local valid = {}
  for _, entry in ipairs(result) do
    local ok2, err = validate_action(entry)
    if ok2 then
      local copy = vim.tbl_deep_extend("force", {}, entry)
      copy.id = "proj." .. entry.id           -- namespace so learning state stays distinct
      copy._is_project = true
      -- Default `when` if not supplied: always show, low priority
      if not copy.when then copy.when = function() return 20 end end
      -- Default label if string
      if type(copy.label) == "string" then
        local lbl = copy.label
        copy.label = function() return lbl end
      elseif not copy.label then
        copy.label = function() return entry.id end
      end
      table.insert(valid, copy)
    else
      pcall(function()
        require("user.brand").notify((".suggest.lua entry skipped (id=%s): %s"):format(tostring(entry.id), err),
          vim.log.levels.WARN, { title = "suggest" })
      end)
    end
  end
  _project = { cwd = cwd, mtime = stat.mtime.sec, path = path, actions = valid }
  return valid
end

-- ─── ranking with learning + playbooks ────────────────────────────────────
-- Look up the strongest next-step learned from sequences. If user picked
-- action X in the past and within 2 minutes consistently picked Y, surface
-- Y as the "next" hint after X is highlighted as suggestion.
local function predicted_next_for(action_id)
  local trans = state.sequences[action_id]
  if not trans then return nil, 0 end
  local best, best_count = nil, 0
  for next_id, count in pairs(trans) do
    if count > best_count then best, best_count = next_id, count end
  end
  -- Only surface if confidence is meaningful (≥3 historical occurrences)
  if best and best_count >= 3 then return best, best_count end
end

-- Look up label for an action id (for hint rendering)
local function action_label(id, c)
  for _, a in ipairs(ACTIONS) do
    if a.id == id then
      local ok, label = pcall(a.label, c)
      if ok then return label end
    end
  end
  return id
end

local function rank(c)
  local fp = fingerprint(c)
  local out = {}
  -- Built-in catalog + per-project additions, evaluated together.
  local project_actions = load_project_actions(c.cwd)
  local all = {}
  for _, a in ipairs(ACTIONS) do table.insert(all, a) end
  for _, a in ipairs(project_actions) do table.insert(all, a) end

  for _, a in ipairs(all) do
    local ok_when, base = pcall(a.when, c)
    if ok_when and base then
      local ok_label, label = pcall(a.label, c)
      if ok_label and label and label ~= "" then
        -- Adaptive suppression: drop actions you've skipped 3+ times in this
        -- context. Cleared per-action by a real pick (see bump_ctx).
        local skip_count = ((state.ctx_skips or {})[fp] or {})[a.id] or 0
        if skip_count < 3 then
        local p = base + recency_bonus(a.id)
        -- Project-scoped: ctx_picks is keyed by full fingerprint including project name
        local ctx_count = (state.ctx_picks[fp] or {})[a.id] or 0
        p = p + math.min(20, ctx_count * 4)
        if last_pick.id and (os.time() - last_pick.ts) < 120 then
          local seq_count = (state.sequences[last_pick.id] or {})[a.id] or 0
          p = p + math.min(18, seq_count * 3)
        end
        -- Project actions get a small visibility boost so they don't drown
        if a._is_project then p = p + 5 end
        local next_id, next_count = predicted_next_for(a.id)
        local next_hint
        if next_id then next_hint = { id = next_id, count = next_count } end
        table.insert(out, {
          action = a, label = label, priority = p,
          learned = (ctx_count > 0),
          next_hint = next_hint,
          is_project = a._is_project or false,
        })
        end   -- skip_count < 3
      end
    end
  end
  table.sort(out, function(x, y) return x.priority > y.priority end)
  while #out > 6 do table.remove(out) end
  return out
end

-- ─── live panel ────────────────────────────────────────────────────────────
local panel = { win = nil, buf = nil, items = {}, augroup = nil, debounce = nil, last_fp = nil }
local NS = vim.api.nvim_create_namespace("user_suggest")
local PREVIEW_NS = vim.api.nvim_create_namespace("user_suggest_preview")

-- Per-action preview generator. Returns a string snippet that describes WHAT
-- the action would target right now, given the live context. Cheap — must
-- never block (no shell-outs, no LSP requests). Unknown action ids return
-- nil so no preview virt_line renders.
local function compute_preview(item, c)
  local id = item.action and item.action.id or ""
  if id == "fix_error" or id == "next_diag" then
    local diags = c.diags or {}
    if #diags == 0 then return nil end
    local first = vim.tbl_filter(function(d) return d.severity == 1 end, diags)[1] or diags[1]
    if not first then return nil end
    local short = (first.message or ""):gsub("\n.*", ""):sub(1, 48)
    return string.format("→ %s:%d  %s", c.short_name or "?", (first.lnum or 0) + 1, short)
  elseif id == "save" then
    local lines = vim.api.nvim_buf_line_count(0)
    return string.format("→ %s  ·  %d line%s", c.short_name or "?", lines, lines == 1 and "" or "s")
  elseif id == "commit" or id == "lazygit" then
    if not c.in_git then return nil end
    -- List up to 3 dirty filenames (cwd-relative, basenames only for fit)
    local files = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.getcwd()) .. " diff --name-only HEAD 2>/dev/null")
    if #files == 0 then files = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.getcwd()) .. " ls-files --others --exclude-standard 2>/dev/null") end
    if #files == 0 then return nil end
    local short = {}
    for i, f in ipairs(files) do
      if i > 3 then break end
      table.insert(short, vim.fn.fnamemodify(f, ":t"))
    end
    local suffix = #files > 3 and (" +" .. (#files - 3) .. " more") or ""
    return "→ " .. table.concat(short, ", ") .. suffix
  elseif id == "test_nearest" or id == "test_file" then
    return string.format("→ neotest will run against %s", c.short_name or "?")
  elseif id == "open_readme" then
    return "→ README in project root"
  elseif id == "open_env" then
    return "→ .env / .envrc in project root"
  elseif id == "browse_url" then
    return "→ open URL under cursor in browser"
  elseif id == "swap_other_file" then
    return "→ jump to test ↔ source pair"
  elseif id == "snap_workspace" then
    return "→ save current layout to session snapshot"
  elseif id == "pomo_break" then
    return "→ pause / take a break"
  end
  return nil  -- no preview for this action
end

local function teardown_autocmds()
  if panel.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, panel.augroup)
    panel.augroup = nil
  end
  if panel.debounce then
    pcall(function() panel.debounce:stop(); panel.debounce:close() end)
    panel.debounce = nil
  end
end

-- When the panel closes WITHOUT a pick, mark the shown actions as "skipped"
-- in the current context. A flag on panel (set by the pick handler) tells us
-- a pick happened so we don't penalize the right answer.
local function close()
  teardown_autocmds()
  -- Record skips for every shown item that wasn't picked.
  if not panel._picked and panel.last_fp and panel.items then
    for _, item in ipairs(panel.items) do
      if item.action and item.action.id then
        bump_skip(panel.last_fp, item.action.id)
      end
    end
    save_state()
  end
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_win_close(panel.win, true)
  end
  panel.win, panel.buf, panel.items, panel.last_fp, panel._picked =
    nil, nil, {}, nil, nil
end

-- Render the focused item's preview as a virt_line below it. Cursor-driven;
-- called on render() and on CursorMoved. Cheap idempotent — clears the
-- previous virt_line every call, then sets at most one new one.
local function render_preview()
  if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then return end
  vim.api.nvim_buf_clear_namespace(panel.buf, PREVIEW_NS, 0, -1)
  if not (panel.item_rows and panel.last_ctx) then return end
  -- Map cursor row → focused item index. Cursor is 1-based; item_rows is 0-based.
  local cur = (panel.win and vim.api.nvim_win_is_valid(panel.win))
    and vim.api.nvim_win_get_cursor(panel.win)[1] - 1
    or panel.item_rows[1]
  local focused_idx
  for i, row in ipairs(panel.item_rows) do
    if row <= cur then focused_idx = i else break end
  end
  if not focused_idx then focused_idx = 1 end
  local item = panel.items[focused_idx]
  if not item then return end
  local preview = compute_preview(item, panel.last_ctx)
  if not preview or preview == "" then return end
  pcall(vim.api.nvim_buf_set_extmark, panel.buf, PREVIEW_NS, panel.item_rows[focused_idx], 0, {
    virt_lines = { { { "           " .. preview, "BrandSubtext" } } },
    virt_lines_above = false,
  })
end

local function render(c, items)
  if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then return end
  panel.items = items
  panel.last_ctx = c
  panel.item_rows = {}
  vim.api.nvim_buf_clear_namespace(panel.buf, NS, 0, -1)
  vim.api.nvim_buf_clear_namespace(panel.buf, PREVIEW_NS, 0, -1)

  -- The top item's predicted-next gets a hint line directly under it.
  -- Each row layout: "  [ N ] [ ● ] [▸] [icon] label"
  --   ` N ` digit chip (3 cols: space + digit + space)  — accent for top, surface for rest
  --   ` ● ` learned chip (3 cols)                       — ok-green, omitted if not learned
  --   `▸`  project-action marker                        — info-blue, omitted if not project
  --   icon — category glyph inferred from the action id
  local _icons = require("user.icons")
  local function _cat_for(id)
    if not id then return "default" end
    if id:find("^jira_")       then return "jira" end
    if id:find("^confluence_") then return "confluence" end
    if id:find("test")         then return "test" end
    if id:find("repl")         then return "repl" end
    if id:find("commit") or id:find("git_") or id:find("hunk") then return "git" end
    if id:find("ai_")          then return "ai" end
    if id:find("save") or id:find("format_") or id:find("open_test_pair")
       or id:find("open_readme") or id:find("open_env") or id:find("swap_other") then return "file" end
    if id:find("find_") or id:find("grep") or id == "spotlight" or id == "browse_todos" then return "search" end
    if id:find("diag") or id:find("fix_error") or id == "code_action" then return "diag" end
    if id:find("shell") or id == "rest_send" then return "shell" end
    if id == "run_macro"        then return "macro" end
    if id:find("journal") or id == "homunculus" then return "journal" end
    if id:find("workspace") or id:find("playbook") or id == "restore_session"
       or id == "wind_down" or id == "engage_cockpit" or id == "review_state" then return "workspace" end
    return "default"
  end
  local lines = { "" }
  for i, it in ipairs(items) do
    local digit = (" %d "):format(i)
    local learned = it.learned     and " ● " or "   "
    local origin  = it.is_project  and "▸ "  or "  "
    local cat_icon = _icons.cat(_cat_for(it.id)).icon
    table.insert(lines, string.format("  %s %s %s%s  %s", digit, learned, origin, cat_icon, it.label))
    panel.item_rows[i] = #lines - 1  -- record 0-indexed row of this item for preview targeting
    -- Only show the playbook hint on the #1 ranked suggestion to avoid noise
    if i == 1 and it.next_hint then
      local hint_label = action_label(it.next_hint.id, c)
      table.insert(lines, string.format("           ↳ then usually: %s   (×%d)", hint_label, it.next_hint.count))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "    " .. string.rep("─", 44))
  local sub = c.short_name ~= "" and c.short_name or "[no name]"
  if c.ft ~= "" then sub = sub .. "  ·  " .. c.ft end
  if c.in_git and c.git_dirty > 0 then sub = sub .. "  ·  " .. c.git_dirty .. " dirty" end
  if c.err_count > 0 then sub = sub .. "  ·  " .. c.err_count .. " err" end
  if c.pomo_active then sub = sub .. "  ·   in focus" end
  table.insert(lines, "    " .. sub)
  table.insert(lines, "")
  table.insert(lines, "    " .. "● = learned     ↳ = predicted next     ? = show all     q = close")

  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false

  -- Walk the rendered lines and apply chip-style highlights via extmarks.
  -- New row layout: "  [ N ] [ ● ] [▸] label"
  --   chars 2..4   : digit chip ` N ` (BrandChipAccent on top, BrandChipSurface otherwise)
  --   chars 6..8   : learned chip ` ● ` (BrandChipOk) — only when learned
  --   project marker `▸` if present (BrandInfo)
  --   `↳ then usually...` hint line dimmed via BrandSubtext
  --   divider/legend/subtitle dimmed via BrandMuted
  local digit_row = 0  -- counts which item row we're on (for top-item detection)
  for r, line in ipairs(lines) do
    local row = r - 1  -- 0-indexed
    local digit_match = line:match("^%s%s(%s%d%s)%s")  -- " 1 " at cols 3-5 (0-indexed: 2..4)
    if digit_match then
      digit_row = digit_row + 1
      local is_top = (digit_row == 1)
      -- Digit chip: cols 2..5 (3-col block)
      pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, 2, {
        end_col = 5, hl_group = is_top and "BrandChipAccent" or "BrandChipSurface",
      })
      -- Learned chip: cols 6..9 (3-col block). Only paint when the marker exists.
      if line:find("●", 6, true) then
        pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, 6, {
          end_col = 9, hl_group = "BrandChipOk",
        })
      end
      -- Project marker `▸` after the chips
      local proj_col = line:find("▸", 9, true)
      if proj_col then
        pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, proj_col - 1, {
          end_col = proj_col + 2, hl_group = "BrandInfo",
        })
      end
      -- Top item gets a bold accent label so the eye lands on it first
      if is_top then
        local label_start = line:find("%S", 11) or 11
        pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, label_start - 1, {
          end_line = row + 1, hl_group = "BrandAccent",
        })
      end
    end
    -- "         ↳ then usually: ..."  → dim the whole line
    if line:find("↳", 1, true) then
      pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, 0, {
        end_line = row + 1, hl_group = "BrandSubtext",
      })
    end
    -- Divider and footer (rule lines, file/ctx subtitle, legend)
    if line:find("^%s+─") or line:find("●%s*=%s*learned") or line:find("^%s+[%a%.]+%s+·") then
      pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, row, 0, {
        end_line = row + 1, hl_group = "BrandMuted",
      })
    end
  end

  -- Resize window to match content
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    local h = #lines
    local cfg = vim.api.nvim_win_get_config(panel.win)
    if cfg.height ~= h then
      pcall(vim.api.nvim_win_set_config, panel.win, {
        relative = "editor",
        row = cfg.row, col = cfg.col,
        width = cfg.width, height = h,
      })
    end
  end

  -- Rebind number keys to the (possibly new) items
  for i = 1, 9 do
    pcall(vim.keymap.del, "n", tostring(i), { buffer = panel.buf })
  end
  for i, it in ipairs(items) do
    vim.keymap.set("n", tostring(i), function() M.pick(i) end,
      { buffer = panel.buf, silent = true, nowait = true })
  end
end

local function schedule_rerender()
  if not (panel.win and vim.api.nvim_win_is_valid(panel.win)) then teardown_autocmds(); return end
  if panel.debounce then return end  -- already pending
  panel.debounce = vim.uv.new_timer()
  panel.debounce:start(220, 0, vim.schedule_wrap(function()
    if panel.debounce then panel.debounce:close(); panel.debounce = nil end
    if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then return end
    local c = ctx()
    local items = rank(c)
    if #items == 0 then close() return end
    -- Only re-render if something materially changed (fingerprint or item set)
    local fp = fingerprint(c) .. "|" .. table.concat(vim.tbl_map(function(it) return it.action.id end, items), ",")
    if fp ~= panel.last_fp then
      panel.last_fp = fp
      render(c, items)
    end
  end))
end

function M.pick(idx)
  local it = panel.items[idx]
  if not it then return end
  panel._picked = true   -- suppress skip-bookkeeping in close()
  local c = ctx()
  local fp = fingerprint(c)
  bump_usage(it.action.id)
  bump_ctx(fp, it.action.id)
  if last_pick.id and (os.time() - last_pick.ts) < 120 then
    bump_seq(last_pick.id, it.action.id)
  end
  last_pick = { id = it.action.id, ts = os.time() }
  save_state()
  -- Fire the action — its side effects (jumping to a line, opening a panel,
  -- writing the buffer) often change context, which triggers our autocmds
  -- and re-ranks the panel automatically. Panel stays open.
  vim.schedule(function() pcall(it.action.run, c) end)
end

function M.show()
  load_state()
  -- Toggle: if already open, close
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then close(); return end

  local c = ctx()
  local items = rank(c)
  if #items == 0 then
    require("user.brand").notify("nothing pressing right now ·  try " .. require("user.brand").kbd("ff") .. " or " .. require("user.brand").kbd("uS"),
      vim.log.levels.INFO, { title = "suggest" })
    return
  end

  -- Compute dimensions from items
  local W = 56
  local H = #items + 6   -- blank + items + blank + divider + subtitle + blank + footer

  local r = require("user.brand").win({
    title = "what next",
    width = W, height = H,
    anchor = "center",
    close_keys = { "q", "<Esc>" },
    animate = true,
  })
  panel.win, panel.buf = r.win, r.buf
  panel.last_fp = nil

  -- Help: `?` opens commandeer-all (full reference of every binding)
  vim.keymap.set("n", "?", function()
    close()
    vim.schedule(function() pcall(function() require("user.commandeer").show_all() end) end)
  end, { buffer = panel.buf, silent = true, nowait = true })

  render(c, items)
  panel.last_fp = fingerprint(c) .. "|" .. table.concat(vim.tbl_map(function(it) return it.action.id end, items), ",")

  -- Live updates: re-rank on context changes
  panel.augroup = vim.api.nvim_create_augroup("user_suggest_live", { clear = true })
  for _, ev in ipairs({
    "DiagnosticChanged", "BufWritePost", "BufEnter", "FocusGained",
    "BufModifiedSet", "InsertLeave", "LspAttach",
  }) do
    vim.api.nvim_create_autocmd(ev, {
      group = panel.augroup,
      callback = schedule_rerender,
    })
  end
  -- Preview-on-hover: re-render the per-item preview every time the cursor
  -- moves within the panel buffer. Scoped via `buffer = panel.buf` so the
  -- autocmd doesn't fire for cursor moves in other windows.
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = panel.augroup,
    buffer = panel.buf,
    callback = render_preview,
  })
  -- Initial preview for the top item — fires before the cursor has moved
  vim.schedule(render_preview)
end

function M.stats()
  load_state()
  local lines = { "## suggest learning state", "" }
  local total = 0
  for id, u in pairs(state.usage) do total = total + u.count end
  table.insert(lines, ("total picks: %d"):format(total))
  table.insert(lines, ("contexts learned: %d"):format(vim.tbl_count(state.ctx_picks)))
  local seq_total = 0
  for _, t in pairs(state.sequences) do for _, c in pairs(t) do seq_total = seq_total + c end end
  table.insert(lines, ("sequences observed: %d"):format(seq_total))
  table.insert(lines, "")
  table.insert(lines, "top picks (all-time):")
  local sorted = {}
  for id, u in pairs(state.usage) do table.insert(sorted, { id = id, count = u.count }) end
  table.sort(sorted, function(a, b) return a.count > b.count end)
  for i = 1, math.min(10, #sorted) do
    table.insert(lines, ("  %2d × %s"):format(sorted[i].count, sorted[i].id))
  end
  require("user.brand").notify(table.concat(lines, "\n"), nil, { title = "suggest" })
end

function M.forget()
  state = { usage = {}, ctx_picks = {}, sequences = {} }
  save_state()
  require("user.brand").notify("learning state reset", nil, { title = "suggest" })
end

local PROJECT_TEMPLATE = [[
-- .suggest.lua  ·  per-project actions for nvim's Suggest panel
--
-- Each action is { id, when(ctx)->priority|nil, label(ctx)->string, run(ctx) }
-- - id:    unique short string (gets prefixed with "proj." internally)
-- - when:  return a number (priority) to surface, or nil to hide
-- - label: text shown in the panel (or a function returning text)
-- - run:   what happens when the user presses its number
--
-- ctx exposes: bufnr, ft, name, short_name, modified, diags, err_count, hour,
--   line, cwd, in_git, git_dirty, readme, env_file, cursor_url, last_other,
--   has_session, pomo_active

return {
  {
    id    = "deploy",
    label = "deploy to staging",
    when  = function(c) return c.in_git and c.git_dirty == 0 and 65 or nil end,
    run   = function() vim.cmd("Job deploy  make deploy-staging") end,
  },
  {
    id    = "e2e",
    label = "run e2e suite",
    when  = function() return 45 end,
    run   = function() vim.cmd("Job e2e  npm run e2e") end,
  },
  -- Add as many as you want.
}
]]

function M.project_info()
  load_project_actions(vim.fn.getcwd())
  local lines = { "" }
  if not _project.path then
    table.insert(lines, "    no .suggest.lua in this project tree")
    table.insert(lines, "")
    table.insert(lines, "    run  :SuggestProjectEdit  to create one")
  else
    table.insert(lines, "    " .. _project.path)
    table.insert(lines, "    last modified " .. os.date("%Y-%m-%d %H:%M", _project.mtime))
    table.insert(lines, "")
    if #_project.actions == 0 then
      table.insert(lines, "    file loaded but has 0 actions")
    else
      table.insert(lines, "    " .. #_project.actions .. " project action" .. (#_project.actions == 1 and "" or "s") .. ":")
      table.insert(lines, "")
      for _, a in ipairs(_project.actions) do
        local label = (type(a.label) == "function" and (pcall(a.label) and select(2, pcall(a.label)) or a.id)) or a.id
        table.insert(lines, string.format("    ▸  %-30s   %s", a.id:gsub("^proj%.", ""), label))
      end
    end
  end
  table.insert(lines, "")
  table.insert(lines, "    project: " .. project_name(vim.fn.getcwd()))
  table.insert(lines, "")
  require("user.brand").win({
    title = "project suggestions",
    width = 70, height = #lines + 2,
    anchor = "center",
  })
  vim.schedule(function()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
  end)
end

function M.project_reload()
  _project = { cwd = nil, mtime = 0, path = nil, actions = {} }
  local n = #load_project_actions(vim.fn.getcwd())
  require("user.brand").notify("project actions reloaded · " .. n .. " loaded", nil, { title = "suggest" })
end

function M.project_edit()
  local root = find_project_root(vim.fn.getcwd()) or vim.fn.getcwd()
  local path = root .. "/.suggest.lua"
  local exists = vim.uv.fs_stat(path) ~= nil
  if not exists then
    local f = io.open(path, "w")
    if f then f:write(PROJECT_TEMPLATE); f:close() end
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if not exists then
    require("user.brand").notify("created " .. path .. " with a template", nil, { title = "suggest" })
  end
end

-- ─── public surface for cross-module access (used by user.playbooks) ──────
function M.find_action(id)
  for _, a in ipairs(ACTIONS) do
    if a.id == id then return a end
  end
  -- Project actions live in the cache; refresh + scan
  for _, a in ipairs(load_project_actions(vim.fn.getcwd())) do
    if a.id == id then return a end
  end
end

function M.context() return ctx() end
function M.sequences() load_state(); return state.sequences end

function M.setup()
  load_state()
  vim.api.nvim_create_user_command("Suggest",              M.show,            { desc = "Open the contextual suggest panel" })
  vim.api.nvim_create_user_command("SuggestStats",         M.stats,           { desc = "Show what Suggest has learned" })
  vim.api.nvim_create_user_command("SuggestForget",        M.forget,          { desc = "Wipe Suggest's learned state" })
  vim.api.nvim_create_user_command("SuggestProject",       M.project_info,    { desc = "Inspect the .suggest.lua loaded for this project" })
  vim.api.nvim_create_user_command("SuggestProjectReload", M.project_reload,  { desc = "Force re-read of .suggest.lua" })
  vim.api.nvim_create_user_command("SuggestProjectEdit",   M.project_edit,    { desc = "Edit (or create) .suggest.lua for this project" })
  vim.api.nvim_create_user_command("SuggestUnhide", function()
    state.ctx_skips = {}; save_state()
    require("user.brand").notify("suggest · all skip-counters cleared", nil, { title = "suggest" })
  end, { desc = "Clear adaptive skip-suppression (un-hide actions)" })

  -- Re-evaluate project actions when the working directory changes.
  vim.api.nvim_create_autocmd("DirChanged", {
    group = vim.api.nvim_create_augroup("user_suggest_dir", { clear = true }),
    callback = function() M.project_reload_quiet() end,
  })
end

function M.project_reload_quiet()
  _project = { cwd = nil, mtime = 0, path = nil, actions = {} }
  load_project_actions(vim.fn.getcwd())
end

return M
