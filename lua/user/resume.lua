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

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  _load()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("user_resume_persist", { clear = true }),
    callback = function() _save() end,
  })
  -- TODO(task-7+): _autocmds()
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
function M.brief()    vim.notify("resume: brief (not yet implemented)",   vim.log.levels.INFO) end
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
