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
  local tmp = STATE_FILE .. ".tmp"
  local ok, encoded = pcall(vim.json.encode, _state)
  if not ok then
    vim.notify("resume: failed to encode state: " .. tostring(encoded), vim.log.levels.ERROR)
    return
  end
  local f, err = io.open(tmp, "w")
  if not f then
    vim.notify("resume: failed to open " .. tmp .. ": " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  f:write(encoded); f:close()
  os.rename(tmp, STATE_FILE)
end

local function _load()
  local f = io.open(STATE_FILE, "r")
  if not f then return end                       -- first run, no file yet
  local raw = f:read("*a"); f:close()
  if raw == "" then return end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" or type(decoded.tasks) ~= "table" then
    local archive = STATE_FILE .. ".broken." .. os.time()
    os.rename(STATE_FILE, archive)
    local ok_toast, toast = pcall(require, "user.toast")
    if ok_toast then
      toast.warn("resume state corrupted · archived → " .. vim.fn.fnamemodify(archive, ":t"))
    end
    return
  end
  _state = decoded
  if _state.version ~= SCHEMA_VERSION then
    -- future: migration hook
    _state.version = SCHEMA_VERSION
  end
  _state.tasks = _state.tasks or {}
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
function M.capture()  vim.notify("resume: capture (not yet implemented)", vim.log.levels.INFO) end
function M.brief()    vim.notify("resume: brief (not yet implemented)",   vim.log.levels.INFO) end
function M.resolve()  vim.notify("resume: resolve (not yet implemented)", vim.log.levels.INFO) end
function M.list()     vim.notify("resume: list (not yet implemented)",    vim.log.levels.INFO) end

-- Internals exposed for use by surfaces (capture/brief/list/resolve) below.
M._internal = {
  load = _load, save = _save,
  project_key = _project_key, state_of = _state_of, task = _task,
  snapshot_files = _snapshot_files, current_branch = _current_branch,
  is_excluded = _is_excluded,
  state = _state,
}

return M
