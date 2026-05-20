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

local function ctx()
  local bufnr = vim.api.nvim_get_current_buf()
  local diags = vim.diagnostic.get(bufnr)
  local cwd = vim.fn.getcwd()
  local in_git, dirty = git_state(cwd)
  return {
    bufnr      = bufnr,
    ft         = vim.bo[bufnr].filetype,
    name       = vim.api.nvim_buf_get_name(bufnr),
    short_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"),
    modified   = vim.bo[bufnr].modified,
    diags      = diags,
    err_count  = #vim.tbl_filter(function(d) return d.severity == 1 end, diags),
    hour       = tonumber(os.date("%H")),
    line       = vim.api.nvim_win_get_cursor(0)[1],
    cwd        = cwd,
    in_git     = in_git,
    git_dirty  = dirty,
  }
end

-- A short string identifying the situation. Same situation = same fingerprint.
local function fingerprint(c)
  return table.concat({
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
}

-- ─── ranking with learning ─────────────────────────────────────────────────
local function rank(c)
  local fp = fingerprint(c)
  local out = {}
  for _, a in ipairs(ACTIONS) do
    local base = a.when(c)
    if base then
      local label = a.label(c)
      if label and label ~= "" then
        local p = base + recency_bonus(a.id)
        -- learning: this fingerprint historically picked this action
        local ctx_count = (state.ctx_picks[fp] or {})[a.id] or 0
        p = p + math.min(20, ctx_count * 4)
        -- learning: short-window sequence — did this action often follow our last pick?
        if last_pick.id and (os.time() - last_pick.ts) < 120 then
          local seq_count = (state.sequences[last_pick.id] or {})[a.id] or 0
          p = p + math.min(18, seq_count * 3)
        end
        table.insert(out, { action = a, label = label, priority = p, learned = (ctx_count > 0) })
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

local function close()
  teardown_autocmds()
  if panel.win and vim.api.nvim_win_is_valid(panel.win) then
    vim.api.nvim_win_close(panel.win, true)
  end
  panel.win, panel.buf, panel.items, panel.last_fp = nil, nil, {}, nil
end

local function render(c, items)
  if not (panel.buf and vim.api.nvim_buf_is_valid(panel.buf)) then return end
  panel.items = items
  vim.api.nvim_buf_clear_namespace(panel.buf, NS, 0, -1)

  local lines = { "" }
  for i, it in ipairs(items) do
    local marker = it.learned and "●" or " "
    table.insert(lines, string.format("    %d  %s  %s", i, marker, it.label))
  end
  table.insert(lines, "")
  table.insert(lines, "    " .. string.rep("─", 44))
  local sub = c.short_name ~= "" and c.short_name or "[no name]"
  if c.ft ~= "" then sub = sub .. "  ·  " .. c.ft end
  if c.in_git and c.git_dirty > 0 then sub = sub .. "  ·  " .. c.git_dirty .. " dirty" end
  if c.err_count > 0 then sub = sub .. "  ·  " .. c.err_count .. " err" end
  table.insert(lines, "    " .. sub)
  table.insert(lines, "")
  table.insert(lines, "    " .. "● = learned in this context     ? = show all     q = close")

  vim.bo[panel.buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
  vim.bo[panel.buf].modifiable = false

  -- Highlights: number key in accent, learned marker, subtitle muted
  for i = 1, #items do
    pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, i, 4, {
      end_col = 5, hl_group = "BrandAccent",
    })
    if items[i].learned then
      pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, i, 7, {
        end_col = 8, hl_group = "BrandOk",
      })
    end
  end
  -- Divider + subtitle + footer
  for r = #items + 2, #items + 4 do
    pcall(vim.api.nvim_buf_set_extmark, panel.buf, NS, r, 0,
      { end_line = r + 1, hl_group = "BrandMuted" })
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

function M.setup()
  load_state()
  vim.api.nvim_create_user_command("Suggest",      M.show,   { desc = "Open the contextual suggest panel" })
  vim.api.nvim_create_user_command("SuggestStats", M.stats,  { desc = "Show what Suggest has learned" })
  vim.api.nvim_create_user_command("SuggestForget", M.forget, { desc = "Wipe Suggest's learned state" })
end

return M
