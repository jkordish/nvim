-- Resume: capture task intent per project; surface a Resume Brief with
-- evidence ("what changed while you were away") on return. Conservative
-- switch detection — zero prompts during a steady-state focused hour.
-- Inspired by vscode-tacos; cited principle: Calm Tech (Weiser, 1995).
local M = {}

-- ─── config (defaults; overridden by setup{} merge) ───────────────────────
M.opts = {
  idle_capture_ms      = 15 * 60 * 1000,
  idle_hint_ms         =  5 * 60 * 1000,
  hint_dwell_ms        = 10 * 1000,
  hint_rate_limit_ms   =  5 * 60 * 1000,
  hint_enabled         = true,
  branch_change_prompt = true,
  auto_resume_buffers  = true,
  confirm_overwrite    = true,
  excluded_filetypes   = { "neo-tree", "lazy", "mason", "qf", "help", "TelescopePrompt" },
  excluded_paths       = { vim.fn.stdpath("config") },
}

-- ─── internal state + constants ───────────────────────────────────────────
local STATE_FILE = vim.fn.stdpath("state") .. "/resume_tasks.json"
local SCHEMA_VERSION = 1

-- in-memory mirror of resume_tasks.json
local _state = { version = SCHEMA_VERSION, tasks = {} }

-- transient (in-memory, not persisted)
local _last_focus_lost     = 0     -- uv.now() at last FocusLost
local _project_active_since = {}   -- { [project_key] = uv.now() } when we first saw activity
local _hint_queue          = {}    -- { [project_key] = true } — emit on next BufEnter
local _last_hint           = {}    -- { [project_key] = uv.now() } — rate limit
local _last_cwd            = nil   -- previous cwd; DirChanged on this nvim
                                   -- delivers the *new* cwd in args.file, so
                                   -- we track the prior one ourselves.

-- ─── project key ──────────────────────────────────────────────────────────
-- Canonical project root. Synchronous on purpose (called from autocmds);
-- git is fast, and we cache via _project_key_cache below.
local _project_key_cache = nil
local _project_key_cwd   = nil

local function _project_key(cwd)
  cwd = cwd or vim.uv.cwd()
  if _project_key_cwd == cwd and _project_key_cache then return _project_key_cache end
  _project_key_cwd = cwd
  local out = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and out[1] and out[1] ~= "" then
    _project_key_cache = out[1]
  else
    _project_key_cache = cwd
  end
  return _project_key_cache
end

-- ─── persistence (atomic save, corruption-recovering load) ────────────────
local function _save()
  local tmp = STATE_FILE .. ".tmp." .. vim.fn.getpid()
  local ok, encoded = pcall(vim.json.encode, _state)
  if not ok then
    vim.notify("resume: failed to encode state: " .. tostring(encoded), vim.log.levels.ERROR)
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  local f, err = io.open(tmp, "w")
  if not f then
    vim.notify("resume: failed to open " .. tmp .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  f:write(encoded); f:close()
  local ok_rename, err_rename = os.rename(tmp, STATE_FILE)
  if not ok_rename then
    vim.notify("resume: failed to rename " .. tmp .. " → " .. STATE_FILE .. ": " .. tostring(err_rename),
      vim.log.levels.ERROR)
    os.remove(tmp)  -- best-effort cleanup; don't propagate further
  end
end

local function _load()
  local f = io.open(STATE_FILE, "r")
  if not f then return end                       -- first run, no file yet
  local raw = f:read("*a"); f:close()
  if raw == "" then return end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" or type(decoded.tasks) ~= "table" then
    local archive = STATE_FILE .. ".broken." .. os.time()
    local ok_rename = os.rename(STATE_FILE, archive)
    if not ok_rename then
      os.remove(STATE_FILE)   -- can't archive; at least don't keep failing on it
    end
    local ok_toast, toast = pcall(require, "user.toast")
    if ok_toast then
      toast.warn("resume state corrupted · archived → " .. vim.fn.fnamemodify(archive, ":t"))
    end
    return
  end
  -- Mutate in place so M._internal.state stays the live mirror
  _state.version = SCHEMA_VERSION
  _state.tasks = {}
  for k, v in pairs(decoded.tasks or {}) do _state.tasks[k] = v end
end

-- ─── lifecycle helpers ────────────────────────────────────────────────────
-- Lifecycle states: "uncaptured" (no task), "active" (paused_at == nil),
-- "paused" (paused_at is a timestamp). See spec for transitions.

local function _task(key) return _state.tasks[key] end

local function _state_of(key)
  local t = _task(key)
  if not t then return "uncaptured" end
  if t.paused_at == vim.NIL or t.paused_at == nil then return "active" end
  return "paused"
end

local function _is_excluded(path)
  if not path then return false end
  for _, pfx in ipairs(M.opts.excluded_paths or {}) do
    if path:sub(1, #pfx) == pfx then return true end
  end
  return false
end

-- Snapshot the currently-open file buffers (cwd-relative) and the cursor
-- in the active buffer. Used at capture time and pause time.
local function _snapshot_files()
  local cwd = vim.uv.cwd()
  local files = {}
  local seen = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and vim.uv.fs_stat(name) then
        local rel = vim.fn.fnamemodify(name, ":."):gsub("^" .. vim.pesc(cwd) .. "/", "")
        if not seen[rel] then table.insert(files, rel); seen[rel] = true end
      end
    end
  end
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  local cursor = nil
  if name ~= "" then
    local pos = vim.api.nvim_win_get_cursor(win)
    cursor = { file = vim.fn.fnamemodify(name, ":."), line = pos[1], col = pos[2] + 1 }
  end
  return files, cursor
end

local function _current_branch(cwd)
  cwd = cwd or vim.uv.cwd()
  local out = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD" })
  if vim.v.shell_error == 0 and out[1] then return out[1] end
  return nil
end

local function _humanize_age(seconds)
  if seconds < 60 then return seconds .. "s ago" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
  return math.floor(seconds / 86400) .. "d ago"
end

-- ─── capture form ─────────────────────────────────────────────────────────
-- Render the capture form as a brand.win float. Single modifiable buffer
-- with read-only label rows (extmarks), one editable row per field.
local function _form(existing, snapshot)
  local brand = require("user.brand")
  local key = _project_key()
  local branch = _current_branch() or "(no branch)"
  local title = existing and "edit this task" or "capture this task"
  local proj_basename = vim.fn.fnamemodify(key, ":t")

  local lines = {
    "",
    "  OBJECTIVE",
    "  " .. (existing and existing.objective or ""),
    "",
    "  NEXT STEP",
    "  " .. (existing and existing.next_step or ""),
    "",
    "  VERIFY FIRST  (what to check before resuming)",
    "  " .. (existing and existing.verify_first or ""),
    "",
    "  NOTES  (optional)",
    "  " .. (existing and (existing.notes or ""):gsub("\n", " ⏎ ") or ""),
    "",
    "  [⏎/^s] save   [tab] next field   [esc] cancel",
  }
  -- 0-indexed line numbers of the editable rows:
  local editable_lines = { 2, 5, 8, 11 }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- visually mark label + footer lines with Comment hl. Not strictly
  -- read-only — field() reads by hard-coded indices so accidental edits
  -- on label rows don't corrupt state, but a user-inserted newline could
  -- shift subsequent rows. Acceptable for v1; revisit if it bites.
  local ns = vim.api.nvim_create_namespace("user_resume_form")
  for i = 0, #lines - 1 do
    local is_editable = false
    for _, el in ipairs(editable_lines) do if i == el then is_editable = true; break end end
    if not is_editable then
      vim.api.nvim_buf_set_extmark(buf, ns, i, 0, { end_line = i + 1, hl_group = "Comment" })
    end
  end

  local panel = brand.win({
    title = title .. " · " .. proj_basename .. " · " .. branch,
    width = 76,
    height = #lines + 2,
    anchor = "center",
    buf = buf,
    close_keys = { "<Esc>" },
  })

  vim.bo[buf].modifiable = true

  -- Jump cursor to first editable line, column 4 (after "  " prefix)
  vim.api.nvim_win_set_cursor(panel.win, { editable_lines[1] + 1, 4 })

  -- Tab / Shift-Tab cycles through editable rows
  local function jump(dir)
    local cur = vim.api.nvim_win_get_cursor(panel.win)[1] - 1
    local nxt = nil
    if dir > 0 then
      for _, el in ipairs(editable_lines) do if el > cur then nxt = el; break end end
      nxt = nxt or editable_lines[1]
    else
      for i = #editable_lines, 1, -1 do if editable_lines[i] < cur then nxt = editable_lines[i]; break end end
      nxt = nxt or editable_lines[#editable_lines]
    end
    vim.api.nvim_win_set_cursor(panel.win, { nxt + 1, 4 })
  end
  vim.keymap.set({ "n", "i" }, "<Tab>",   function() jump( 1) end, { buffer = buf, silent = true })
  vim.keymap.set({ "n", "i" }, "<S-Tab>", function() jump(-1) end, { buffer = buf, silent = true })

  -- Save: read editable rows, persist
  local function save()
    local rows = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local function field(line_idx)
      local s = rows[line_idx + 1] or ""
      return (s:gsub("^%s*", ""):gsub("%s+$", ""))
    end
    local objective    = field(editable_lines[1])
    local next_step    = field(editable_lines[2])
    local verify_first = field(editable_lines[3])
    local notes        = field(editable_lines[4]):gsub(" ⏎ ", "\n")

    if objective == "" then
      vim.notify("resume: objective is required", vim.log.levels.WARN)
      return
    end

    local now = os.time()
    local files, cursor = snapshot.files, snapshot.cursor
    local existing_task = _task(key)
    local task = existing_task or {}
    task.objective    = objective
    task.next_step    = next_step
    task.verify_first = verify_first
    task.notes        = notes
    task.blockers     = task.blockers or {}
    task.branch       = _current_branch()
    task.started      = task.started or now
    task.paused_at    = nil      -- capture = activate
    task.files        = files
    task.cursor       = cursor
    task.resumed_count = task.resumed_count or 0
    _state.tasks[key] = task
    _save()
    panel.close()
    local ok_toast, toast = pcall(require, "user.toast")
    if ok_toast then toast.ok("task captured · " .. proj_basename) end
  end

  vim.keymap.set("n", "<CR>", save, { buffer = buf, silent = true })
  vim.keymap.set("i", "<C-CR>", function() vim.cmd("stopinsert"); save() end, { buffer = buf, silent = true })
  vim.keymap.set("i", "<C-s>", function() vim.cmd("stopinsert"); save() end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<C-s>", save, { buffer = buf, silent = true })

  -- Enter insert at the cursor when entering the buffer
  vim.cmd("startinsert!")
end

-- ─── brief panel ──────────────────────────────────────────────────────────
local function _resume_buffers(task)
  if not M.opts.auto_resume_buffers or not task.files then return end
  for _, rel in ipairs(task.files) do
    local abs = rel:sub(1, 1) == "/" and rel or (vim.uv.cwd() .. "/" .. rel)
    if vim.uv.fs_stat(abs) then
      pcall(vim.cmd, "badd " .. vim.fn.fnameescape(abs))
    end
  end
  if task.cursor and task.cursor.file then
    local abs = task.cursor.file:sub(1, 1) == "/" and task.cursor.file
                or (vim.uv.cwd() .. "/" .. task.cursor.file)
    if vim.uv.fs_stat(abs) then
      pcall(vim.cmd, "edit " .. vim.fn.fnameescape(abs))
      pcall(vim.api.nvim_win_set_cursor, 0, { task.cursor.line or 1, (task.cursor.col or 1) - 1 })
    end
  end
end

-- Replace the "WHAT CHANGED" placeholder line (1-based) in a panel buffer
-- with the computed evidence lines. Falls back to "(no data)" if every
-- probe yields nothing.
local function _what_changed(buf, line_idx, key, task)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local paused_at = task.paused_at or os.time()
  local since_iso = os.date("!%Y-%m-%dT%H:%M:%SZ", paused_at)
  local cwd = key   -- key IS the git toplevel (or cwd) per _project_key

  local results = {}
  local pending = 0

  local function done()
    pending = pending - 1
    if pending > 0 then return end
    if not vim.api.nvim_buf_is_valid(buf) then return end

    local out = {}
    for _, r in ipairs(results) do if r and r ~= "" then table.insert(out, "  " .. r) end end
    if #out == 0 then table.insert(out, "  (nothing notable)") end

    vim.bo[buf].modifiable = true
    -- replace the single placeholder line at line_idx (1-based)
    vim.api.nvim_buf_set_lines(buf, line_idx - 1, line_idx, false, out)
    vim.bo[buf].modifiable = false
  end

  local function run(cmd, on_result)
    pending = pending + 1
    local timed_out, completed = false, false
    local timer = vim.uv.new_timer()
    timer:start(3000, 0, vim.schedule_wrap(function()
      if completed then return end       -- system already settled; bail
      timed_out = true
      on_result(nil, true)
      done()
      pcall(function() timer:stop(); timer:close() end)
    end))
    vim.system(cmd, { text = true, cwd = cwd }, function(res)
      if timed_out then return end       -- timer already settled; bail
      completed = true
      pcall(function() timer:stop(); timer:close() end)
      vim.schedule(function()
        on_result(res.code == 0 and res.stdout or nil, false)
        done()
      end)
    end)
  end

  -- Probe 1: commits since paused_at
  run({ "git", "log", "--since=" .. since_iso, "--oneline" }, function(stdout, timed_out)
    if timed_out then table.insert(results, "git timed out") return end
    if not stdout or stdout == "" then return end
    local n = 0; for _ in stdout:gmatch("\n") do n = n + 1 end
    if n == 0 then n = 1 end
    table.insert(results, "• " .. n .. " commit(s) since pause")
  end)

  -- Probe 2: file-level churn (diff stat from paused-at-ish anchor)
  -- approximation: diff against HEAD~N where N = commit count since paused_at
  run({ "git", "log", "--since=" .. since_iso, "--oneline" }, function(stdout)
    local n = 0
    if stdout then for _ in stdout:gmatch("\n") do n = n + 1 end end
    if n == 0 then return end
    run({ "git", "diff", "--stat", "HEAD~" .. n .. "..HEAD" }, function(diff_out)
      if not diff_out or diff_out == "" then return end
      local last = ""
      for line in diff_out:gmatch("[^\n]+") do last = line end
      if last ~= "" then table.insert(results, "• " .. last:gsub("^%s+", "")) end
    end)
  end)

  -- Probe 3: branch divergence (only if we know captured branch)
  if task.branch then
    run({ "git", "log", "--oneline", task.branch .. "..HEAD" }, function(stdout)
      if not stdout or stdout == "" then return end
      local n = 0; for _ in stdout:gmatch("\n") do n = n + 1 end
      if n > 0 then
        table.insert(results, "• " .. n .. " commit(s) ahead of captured branch (" .. task.branch .. ")")
      end
    end)
  end

  -- Probe 4: missing-files check
  pending = pending + 1
  vim.schedule(function()
    if task.files then
      local missing = 0
      for _, rel in ipairs(task.files) do
        local abs = rel:sub(1, 1) == "/" and rel or (cwd .. "/" .. rel)
        if not vim.uv.fs_stat(abs) then missing = missing + 1 end
      end
      if missing > 0 then
        table.insert(results, "• " .. missing .. " captured file(s) no longer exist")
      end
    end
    done()
  end)

  -- Probe 5: blackbox slice (synchronous, in-memory — cheap)
  pending = pending + 1
  vim.schedule(function()
    local ok, blackbox = pcall(require, "user.blackbox")
    if ok and blackbox.since then
      local events = blackbox.since(paused_at)
      if #events > 0 then
        local last = events[1]
        local fmt = os.date("%H:%M", last.t)
        table.insert(results, "• blackbox: " .. #events ..
          " event(s), last: " .. (last.kind or "?") .. " at " .. fmt)
      end
    end
    done()
  end)
end

local function _panel(key, task)
  local brand = require("user.brand")
  local basename = vim.fn.fnamemodify(key, ":t")
  local prev_win = vim.api.nvim_get_current_win()
  local age = task.paused_at and _humanize_age(os.time() - task.paused_at) or "active"
  local branch = task.branch or "(no branch)"

  local lines = { "" }
  local function row(text) table.insert(lines, "  " .. text) end
  local function section(label) table.insert(lines, ""); row(label); end

  section("VERIFY FIRST")
  row("  → " .. (task.verify_first and task.verify_first ~= "" and task.verify_first or "(none specified)"))

  section("WHAT YOU WERE DOING")
  row("  objective: " .. (task.objective or ""))
  if task.next_step and task.next_step ~= "" then
    row("  next step: " .. task.next_step)
  end

  section("WHAT CHANGED WHILE YOU WERE AWAY")
  row("  ⠋ computing…")     -- placeholder; Task 6 swaps in real probes
  local changed_section_line = #lines    -- 1-based; remember row to update

  if task.notes and task.notes ~= "" then
    section("OPEN THREADS")
    for _, ln in ipairs(vim.split(task.notes, "\n")) do row("  " .. ln) end
  end
  if task.blockers and #task.blockers > 0 then
    if not (task.notes and task.notes ~= "") then section("OPEN THREADS") end
    for _, b in ipairs(task.blockers) do row("  blocker: " .. b) end
  end

  table.insert(lines, "")
  row("[r]esume  [e]dit  [x]resolve  [q]close")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Section-label highlighting via extmarks
  local ns = vim.api.nvim_create_namespace("user_resume_panel")
  for i, ln in ipairs(lines) do
    if ln:match("^  [A-Z][A-Z][A-Z]") then
      vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0,
        { end_line = i, hl_group = "BrandChipAccent" })
    end
  end

  local panel = brand.win({
    title = "paused " .. age .. " · " .. branch .. " · " .. basename,
    width = 78,
    height = math.min(#lines + 2, 28),
    anchor = "center",
    buf = buf,
    close_keys = { "q", "<Esc>" },
  })

  -- Footer actions
  vim.keymap.set("n", "r", function()
    task.paused_at = nil
    task.resumed_count = (task.resumed_count or 0) + 1
    _state.tasks[key] = task
    _save()
    panel.close()
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
    _resume_buffers(task)
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "e", function()
    panel.close()
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
    M.capture()
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "x", function()
    panel.close()
    if vim.api.nvim_win_is_valid(prev_win) then
      vim.api.nvim_set_current_win(prev_win)
    end
    M.resolve()
  end, { buffer = buf, silent = true })

  return panel, changed_section_line
end

local function _capture_toast(project_basename)
  -- Tiny brand.win float in top-right, two-key (y/n), 4-sec auto-dismiss.
  -- We don't use user.toast because it's passive (no input keymaps); we
  -- want a single-tap accept that doesn't steal focus.
  local brand = require("user.brand")
  local text = " capture work in " .. project_basename .. "?  [y]es  [n]o "
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })

  local panel = brand.win({
    title = "resume",
    width = math.max(40, #text + 4),
    height = 1,
    anchor = "tr",
    focusable = false,
    animate = false,
    buf = buf,
    close_keys = {},
  })

  -- Use buffer-local keymaps on the CURRENT buffer (where focus actually is),
  -- not on the toast's buffer (which we made non-focusable).
  local target_buf = vim.api.nvim_get_current_buf()

  local function teardown()
    pcall(vim.keymap.del, "n", "y", { buffer = target_buf })
    pcall(vim.keymap.del, "n", "n", { buffer = target_buf })
    if panel and panel.close then panel.close() end
  end

  vim.keymap.set("n", "y", function() teardown(); M.capture() end,
    { buffer = target_buf, silent = true, nowait = true })
  vim.keymap.set("n", "n", teardown,
    { buffer = target_buf, silent = true, nowait = true })

  -- Auto-dismiss after 4s
  vim.defer_fn(function()
    pcall(vim.keymap.del, "n", "y", { buffer = target_buf })
    pcall(vim.keymap.del, "n", "n", { buffer = target_buf })
    if panel and panel.close then panel.close() end
  end, 4000)
end

local HINT_NS = vim.api.nvim_create_namespace("user_resume_hint")

local function _hint(buf, key, task)
  if not M.opts.hint_enabled then
    -- TODO(future): fall back to lualine chip
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  for _, ft in ipairs(M.opts.excluded_filetypes or {}) do
    if vim.bo[buf].filetype == ft then return end
  end

  local age = task.paused_at and _humanize_age(os.time() - task.paused_at) or "now"
  local objective = task.objective or "(no objective)"
  if #objective > 50 then objective = objective:sub(1, 47) .. "…" end
  local text = "⟳ paused " .. age .. ": " .. objective .. " — <leader>Kr to resume"

  local id = vim.api.nvim_buf_set_extmark(buf, HINT_NS, 0, 0, {
    virt_text = { { text, "BrandChipAccent" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })

  -- Fade timer
  local cleared = false
  local function clear()
    if cleared then return end
    cleared = true
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_del_extmark, buf, HINT_NS, id)
    end
  end

  vim.defer_fn(clear, M.opts.hint_dwell_ms)

  -- Also clear on first cursor move in this buffer
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    once = true,
    callback = clear,
  })

  _last_hint[key] = vim.uv.now()
end

local function _autocmds()
  local grp = vim.api.nvim_create_augroup("user_resume", { clear = true })

  -- Seed _last_cwd so the very first DirChanged after setup() has a
  -- prior cwd to compare against.
  _last_cwd = vim.uv.cwd()

  -- DirChanged (scope=global): project switch. On this nvim, args.file
  -- carries the *new* cwd (not the previous), so we maintain our own
  -- _last_cwd as recall.lua does.
  vim.api.nvim_create_autocmd("DirChanged", {
    group = grp,
    pattern = "global",
    callback = function()
      local new_cwd = vim.uv.cwd()
      local old_cwd = _last_cwd
      _last_cwd = new_cwd

      -- _project_key has a single-entry cache; force re-resolve by
      -- invalidating before asking for the new key.
      _project_key_cache = nil
      _project_key_cwd   = nil
      local new_key = _project_key(new_cwd)
      local old_key = old_cwd and old_cwd ~= "" and _project_key(old_cwd) or nil
      if old_key == new_key then return end

      -- pause the outgoing task if active
      if old_key and _state_of(old_key) == "active" then
        local t = _task(old_key)
        if t then
          t.paused_at = os.time()
          t.files, t.cursor = _snapshot_files()
          _save()
        end
      end

      -- enqueue hint if incoming project has a paused task (BufEnter
      -- consumer + render arrive in tasks 8 + 9)
      if _state_of(new_key) == "paused" then
        _hint_queue[new_key] = true
      end
    end,
  })

  vim.api.nvim_create_autocmd("FocusLost", {
    group = grp,
    callback = function()
      _last_focus_lost = vim.uv.now()
      local key = _project_key()
      if not _project_active_since[key] then
        _project_active_since[key] = _last_focus_lost
      end
    end,
  })

  vim.api.nvim_create_autocmd("FocusGained", {
    group = grp,
    callback = function()
      local now = vim.uv.now()
      local away = now - _last_focus_lost
      local key = _project_key()
      local state = _state_of(key)

      if state == "uncaptured" then
        local active_since = _project_active_since[key]
        if away > M.opts.idle_capture_ms
            and active_since
            and (now - active_since) > M.opts.idle_capture_ms
            and not _is_excluded(key) then
          _capture_toast(vim.fn.fnamemodify(key, ":t"))
        end
      elseif state == "paused" then
        if away > M.opts.idle_hint_ms then
          _hint_queue[key] = true
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = grp,
    callback = function(args)
      local key = _project_key()
      if not _hint_queue[key] then return end
      local now = vim.uv.now()
      local last = _last_hint[key] or 0
      if (now - last) < M.opts.hint_rate_limit_ms then return end
      -- skip special filetypes
      for _, ft in ipairs(M.opts.excluded_filetypes or {}) do
        if vim.bo[args.buf].filetype == ft then return end
      end
      local task = _task(key)
      if task then _hint(args.buf, key, task); _hint_queue[key] = nil end
    end,
  })

  -- Track activity inside a project: any text change updates active_since
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = grp,
    callback = function()
      local key = _project_key()
      if not _is_excluded(key) then
        _project_active_since[key] = _project_active_since[key] or vim.uv.now()
      end
    end,
  })
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  _load()
  _autocmds()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("user_resume_persist", { clear = true }),
    callback = function() _save() end,
  })
end

-- Public API (stubs; filled in later tasks)
function M.capture()
  local key = _project_key()
  if _is_excluded(key) then
    vim.notify("resume: this path is excluded", vim.log.levels.INFO)
    return
  end
  local files, cursor = _snapshot_files()
  local snapshot = { files = files, cursor = cursor }
  local existing = _task(key)
  if existing and existing.objective and M.opts.confirm_overwrite then
    vim.ui.select({ "edit existing", "overwrite (start fresh)", "cancel" }, {
      prompt = "task already exists for " .. vim.fn.fnamemodify(key, ":t") .. ":",
    }, function(choice)
      if choice == "edit existing"      then _form(existing, snapshot)
      elseif choice == "overwrite (start fresh)" then _form(nil, snapshot)
      end
    end)
  else
    _form(existing, snapshot)
  end
end
function M.brief()
  local key = _project_key()
  local task = _task(key)
  if not task then
    vim.notify("resume: no paused task here · <leader>Kc to capture", vim.log.levels.INFO)
    return
  end
  local panel, changed_line = _panel(key, task)
  _what_changed(panel.buf, changed_line, key, task)
end
function M.resolve()
  local key = _project_key()
  local t = _task(key)
  if not t then
    vim.notify("resume: no captured task in this project", vim.log.levels.INFO)
    return
  end
  vim.ui.select({ "yes — resolve and delete", "cancel" }, {
    prompt = "resolve task: " .. (t.objective or "(no objective)") .. "?",
  }, function(choice)
    if choice ~= "yes — resolve and delete" then return end
    _state.tasks[key] = nil
    _save()
    local ok_toast, toast = pcall(require, "user.toast")
    if ok_toast then toast.ok("task resolved · " .. vim.fn.fnamemodify(key, ":t")) end
  end)
end

function M.list()
  local items = {}
  for k, t in pairs(_state.tasks) do
    table.insert(items, { key = k, task = t })
  end
  table.sort(items, function(a, b)
    -- nil paused_at (active) → math.huge, so active sorts to top; among
    -- paused entries, most-recently-paused sorts above older ones.
    local pa = a.task.paused_at or math.huge
    local pb = b.task.paused_at or math.huge
    return pa > pb
  end)
  if #items == 0 then
    vim.notify("resume: no captured tasks yet · <leader>Kc to capture one", vim.log.levels.INFO)
    return
  end
  local labels = {}
  for _, it in ipairs(items) do
    local basename = vim.fn.fnamemodify(it.key, ":t")
    local state = it.task.paused_at and ("paused " .. _humanize_age(os.time() - it.task.paused_at)) or "active"
    labels[#labels + 1] = string.format("[%s] %s — %s", state, basename, it.task.objective or "(no objective)")
  end
  vim.ui.select(labels, { prompt = "resume — paused tasks:" }, function(_, idx)
    if not idx then return end
    local choice = items[idx]
    if not vim.uv.fs_stat(choice.key) then
      vim.notify("resume: project root no longer exists: " .. choice.key, vim.log.levels.WARN)
      return
    end
    -- tcd matches projects.lua convention (tab-local); fires DirChanged
    -- which task 7's auto-pause/resume listener will react to.
    vim.cmd("tcd " .. vim.fn.fnameescape(choice.key))
    M.brief()
  end)
end

-- Internals exposed for use by surfaces (capture/brief/list/resolve) below.
M._internal = {
  load = _load, save = _save,
  project_key = _project_key, state_of = _state_of, task = _task,
  snapshot_files = _snapshot_files, current_branch = _current_branch,
  is_excluded = _is_excluded,
  state = _state,
}

return M
