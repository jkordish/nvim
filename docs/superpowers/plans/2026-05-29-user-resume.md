# `user.resume` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `lua/user/resume.lua` module that captures task intent (objective / next-step / verify-first / notes) per project, surfaces a Resume Brief panel with live "what changed while you were away" evidence, and conservatively prompts on context switches.

**Architecture:** Single first-party module under `lua/user/`, project-keyed task state in `~/.local/state/nvim/resume_tasks.json`, three surfaces (capture form + ambient virtual-text hint + Resume Brief panel). Composes with existing `brand.win`, `toast`, `blackbox` modules. No new plugins.

**Tech Stack:** Neovim 0.12+ Lua, `vim.system` for async git probes, `vim.json` for persistence, `vim.api.nvim_*` extmarks for the virtual-text hint.

**Spec:** `docs/superpowers/specs/2026-05-29-resume-lua-design.md` — read it before starting any task.

**Repo conventions** (from `CLAUDE.md`):

- No test suite. "Tests" in this plan are headless `nvim --headless -c "lua ..." -c "qa"` smoke checks plus interactive validation.
- `./scripts/doctor.sh` is the healthcheck. Run after each task that touches a `keys =` table or adds a require.
- All user modules export `M.setup()`. Lazy-loaded by `lua/plugins/user-modules.lua`.
- Commits use `-c commit.gpgsign=false` for this session (GPG key not present).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `lua/user/resume.lua` | **new** | Module — state, surfaces, autocmds |
| `lua/user/blackbox.lua` | modify | Add `M.since(epoch_seconds)` helper |
| `lua/user/state.lua` | modify | Add one `registry()` entry |
| `lua/plugins/user-modules.lua` | modify | Add `require("user.resume").setup()` + 4 `<leader>K*` keymaps |
| `README.md` | modify (last task) | Document the new feature |
| `~/.local/state/nvim/resume_tasks.json` | runtime data | Persisted task state |

---

## Task 1: Scaffold module + wiring + blackbox helper + state registry

Goal: get a no-op `user.resume` loaded by nvim, wired into `state.lua` and `user-modules.lua`, with `blackbox.since()` available. Validates the wiring with zero new behavior so a startup regression here is impossible to confuse with a logic bug later.

**Files:**

- Create: `lua/user/resume.lua`
- Modify: `lua/user/blackbox.lua` (add `M.since`)
- Modify: `lua/user/state.lua` (add registry entry)
- Modify: `lua/plugins/user-modules.lua` (add setup call + 4 keymaps stubbed to a notify)

- [ ] **Step 1: Create `lua/user/resume.lua` with no-op `setup()`**

```lua
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

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  -- TODO(task-2): _load()
  -- TODO(task-7+): _autocmds()
end

-- Public API (stubs; filled in later tasks)
function M.capture()  vim.notify("resume: capture (not yet implemented)", vim.log.levels.INFO) end
function M.brief()    vim.notify("resume: brief (not yet implemented)",   vim.log.levels.INFO) end
function M.resolve()  vim.notify("resume: resolve (not yet implemented)", vim.log.levels.INFO) end
function M.list()     vim.notify("resume: list (not yet implemented)",    vim.log.levels.INFO) end

return M
```

- [ ] **Step 2: Add `M.since()` helper to `lua/user/blackbox.lua`**

Append above the `return M` line at the bottom of the file:

```lua
-- Return blackbox entries newer than the given epoch-seconds timestamp.
-- Returns a list (most recent first; matches internal `log` ordering).
function M.since(epoch_seconds)
  local out = {}
  for _, e in ipairs(log) do
    if e.t >= epoch_seconds then table.insert(out, e) else break end
  end
  return out
end
```

(The internal `log` table is already populated by `push()` in insertion order, most-recent-first per `table.insert(log, 1, …)` — so we can break on the first entry older than the cutoff.)

- [ ] **Step 3: Register state file in `lua/user/state.lua`**

In the `registry()` function, after the existing `confluence` entry and before the `tabs` entry (or wherever fits the file's section ordering), add:

```lua
    { id = "resume",     path = STATE_DIR .. "/resume_tasks.json",
      desc = "Resume · paused tasks per project + verify-first cues", json = true },
```

- [ ] **Step 4: Wire `user.resume` into `lua/plugins/user-modules.lua`**

In the `config = function()` block, in the "daily-driver tools" phase, after `require("user.jobs").setup()` and before `require("user.spotlight").setup()`, add:

```lua
      require("user.resume").setup()
```

Then in the `keys = { … }` table, in the `-- ═════ DAILY ═════` section (after the yankring/ai_cmd lines is a sensible spot), add four new bindings:

```lua
      -- ═════ RESUME (task intent + brief) ═════
      { "<leader>Kc", function() require("user.resume").capture() end, desc = "Resume: capture task" },
      { "<leader>Kr", function() require("user.resume").brief()   end, desc = "Resume: show brief" },
      { "<leader>Kx", function() require("user.resume").resolve() end, desc = "Resume: resolve task" },
      { "<leader>Kl", function() require("user.resume").list()    end, desc = "Resume: list paused tasks" },
```

- [ ] **Step 5: Smoke check — nvim starts clean and the module loads**

Run:

```bash
nvim --headless -c "lua require('user.resume').setup()" -c "lua print('ok: ' .. type(require('user.resume').capture))" -c "qa" 2>&1
```

Expected output:

```
ok: function
```

- [ ] **Step 6: Smoke check — keymap collision sweep**

Run:

```bash
./scripts/doctor.sh keymaps
```

Expected: no errors mentioning `<leader>K{c,r,x,l}`. (Doctor sweep during the initial Task 1 attempt revealed the original `<leader>t*` prefix collides with treesitter-context and Rust runnables; switched to `R` per the keymap-collision-risk memory. `R` is verified clean here.)

- [ ] **Step 7: Smoke check — `:UserState` lists resume**

Run:

```bash
nvim --headless -c "lua local s=require('user.state'); s.setup() ; for _,e in ipairs(s.registry and s.registry() or {}) do if e.id=='resume' then print('registered: '..e.path); end end" -c "qa" 2>&1
```

If `state.lua` keeps `registry()` local (not exposed on M), instead invoke `:UserState` interactively to confirm `resume` appears in the listing. Either path verifies the registration took.

- [ ] **Step 8: Smoke check — `M.since` returns a list**

Run:

```bash
nvim --headless -c "lua local b=require('user.blackbox'); b.setup(); local r=b.since(0); print('blackbox.since ok, count='..#r)" -c "qa" 2>&1
```

Expected: `blackbox.since ok, count=0` (or a small positive count if blackbox has captured anything during nvim startup).

- [ ] **Step 9: Commit**

```bash
git add lua/user/resume.lua lua/user/blackbox.lua lua/user/state.lua lua/plugins/user-modules.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: scaffold module + wiring + blackbox.since helper

Empty user.resume with no-op M.setup() and four notify-only public
functions. Registered in state.lua, wired into user-modules.lua phase 3
with <leader>K{c,r,x,l} keymaps. Adds blackbox.since(epoch_seconds) for
the later "what changed" evidence section.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: State layer — load, save, project key, lifecycle helpers

Goal: persistent task state with atomic writes, corruption recovery, and the helper functions that later tasks compose on. Pure data layer — no UI yet.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add internal state + constants**

Below the `M.opts` block in `lua/user/resume.lua`, add:

```lua
local STATE_FILE = vim.fn.stdpath("state") .. "/resume_tasks.json"
local SCHEMA_VERSION = 1

-- in-memory mirror of resume_tasks.json
local _state = { version = SCHEMA_VERSION, tasks = {} }

-- transient (in-memory, not persisted)
local _last_focus_lost     = 0     -- uv.now() at last FocusLost
local _project_active_since = {}   -- { [project_key] = uv.now() } when we first saw activity
local _hint_queue          = {}    -- { [project_key] = true } — emit on next BufEnter
local _last_hint           = {}    -- { [project_key] = uv.now() } — rate limit
```

- [ ] **Step 2: Add `_project_key()`**

```lua
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
```

- [ ] **Step 3: Add `_save()` with atomic write**

```lua
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
```

- [ ] **Step 4: Add `_load()` with corruption recovery**

```lua
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
```

- [ ] **Step 5: Add lifecycle helpers**

```lua
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
```

- [ ] **Step 6: Update `M.setup()` to call `_load()` and `VimLeavePre` save**

Replace the existing `M.setup` body with:

```lua
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  _load()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("user_resume_persist", { clear = true }),
    callback = function() _save() end,
  })
end
```

- [ ] **Step 7: Expose helpers for next-task wiring**

At the bottom of the file, above `return M`, add a private namespace for the next tasks to import:

```lua
-- Internals exposed for use by surfaces (capture/brief/list/resolve) below.
M._internal = {
  load = _load, save = _save,
  project_key = _project_key, state_of = _state_of, task = _task,
  snapshot_files = _snapshot_files, current_branch = _current_branch,
  is_excluded = _is_excluded,
  state = _state,
}
```

(Note: `M._internal.state` references the table — mutations from later tasks will be visible. We expose this only for in-file use; nothing outside `user.resume` should reach in.)

- [ ] **Step 8: Smoke check — load/save round-trip**

```bash
nvim --headless -c "lua
  local r=require('user.resume'); r.setup()
  r._internal.state.tasks['/tmp/proj-a'] = { objective='test', paused_at=nil }
  r._internal.save()
  local r2=require('user.resume'); r2._internal.load()
  print('round-trip:', r2._internal.task('/tmp/proj-a') and r2._internal.task('/tmp/proj-a').objective or 'MISSING')
" -c "qa" 2>&1
```

Expected output:

```
round-trip:    test
```

(Leading whitespace from `print` separator is fine.)

- [ ] **Step 9: Smoke check — corruption recovery**

```bash
echo 'garbage{not json' > ~/.local/state/nvim/resume_tasks.json
nvim --headless -c "lua require('user.resume').setup(); print('loaded ok')" -c "qa" 2>&1
ls ~/.local/state/nvim/resume_tasks.json.broken.* 2>&1 | head -1
```

Expected: prints `loaded ok` and lists a `.broken.<timestamp>` archive file. Clean up afterward: `rm ~/.local/state/nvim/resume_tasks.json*` so later tasks start fresh.

- [ ] **Step 10: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: state layer — atomic save, corruption recovery, lifecycle helpers

In-memory _state mirrors resume_tasks.json. _save() writes via tmp+rename
(POSIX-atomic). _load() recovers from corruption by archiving the bad
file as .broken.<ts> and starting fresh, matching suggest.lua precedent.
_project_key() canonicalizes via git toplevel with cwd fallback (cached).
Helpers for snapshotting open buffers + cursor and resolving the current
git branch. VimLeavePre saves on exit. No surfaces yet — those land in
the next tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Capture form (`<leader>Kc`)

Goal: working `<leader>Kc` that opens a `brand.win` form, lets the user fill four fields, persists on save. First user-facing milestone.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add `_form()` builder**

Above `M._internal = ...` near the bottom, add:

```lua
-- Render the capture form as a brand.win float. Single modifiable buffer
-- with read-only label rows (extmarks), one editable row per field.
local function _form(existing)
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
    "  [⏎] save   [tab] next field   [esc] cancel",
  }
  -- 0-indexed line numbers of the editable rows:
  local editable_lines = { 2, 5, 8, 11 }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- mark label + footer lines read-only via a CursorMoved guard
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
      return (s:sub(3):gsub("^%s+", ""):gsub("%s+$", ""))
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
    local files, cursor = _snapshot_files()
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

  -- Enter insert at the cursor when entering the buffer
  vim.cmd("startinsert!")
end
```

- [ ] **Step 2: Replace the `M.capture()` stub**

Replace the existing one-line stub with:

```lua
function M.capture()
  local key = _project_key()
  if _is_excluded(key) then
    vim.notify("resume: this path is excluded", vim.log.levels.INFO)
    return
  end
  local existing = _task(key)
  if existing and existing.objective and M.opts.confirm_overwrite then
    vim.ui.select({ "edit existing", "overwrite (start fresh)", "cancel" }, {
      prompt = "task already exists for " .. vim.fn.fnamemodify(key, ":t") .. ":",
    }, function(choice)
      if choice == "edit existing"      then _form(existing)
      elseif choice == "overwrite (start fresh)" then _form(nil)
      end
    end)
  else
    _form(existing)
  end
end
```

- [ ] **Step 3: Smoke check — form opens, save round-trips**

Launch nvim interactively:

```bash
nvim
```

Then in nvim:

1. `<leader>Kc` — form should open.
2. Type an objective on the OBJECTIVE row.
3. `<Tab>` should jump to NEXT STEP.
4. Add a next step, `<CR>` to save.
5. `:UserState` (or `<leader>us`) — confirm `resume` shows non-zero size.
6. `<leader>Kc` again — should prompt "task already exists" and offer edit/overwrite/cancel.
7. Pick `edit existing` — form should reopen pre-filled with your values.

Quit nvim. Re-open nvim. `<leader>Kc` again — should still show the pre-fill (persistence works).

Cleanup: `rm ~/.local/state/nvim/resume_tasks.json` for a clean slate before the next task.

- [ ] **Step 4: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: capture form — <leader>Kc opens brand.win, persists on save

Three structured fields (objective / next_step / verify_first) + freeform
notes, all visible at once via a single brand.win buffer. Tab cycles
editable rows; <CR> saves. Existing-task path offers edit/overwrite/cancel
via vim.ui.select. Auto-captures open buffers + cursor at save time.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: List (`<leader>Kl`) + Resolve (`<leader>Kx`)

Goal: two small surfaces that make the data layer inspectable and testable from the keyboard. List shows all captured tasks across projects; resolve deletes the current project's task.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Implement `M.list()`**

Replace the stub:

```lua
function M.list()
  local items = {}
  for k, t in pairs(_state.tasks) do
    table.insert(items, { key = k, task = t })
  end
  table.sort(items, function(a, b)
    local pa = a.task.paused_at or math.huge   -- active sorts last (most recent)
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
    -- cd to project root then open its brief
    vim.cmd("cd " .. vim.fn.fnameescape(choice.key))
    M.brief()
  end)
end
```

- [ ] **Step 2: Add `_humanize_age()` helper**

Just above `_form()`, add:

```lua
local function _humanize_age(seconds)
  if seconds < 60 then return seconds .. "s ago" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
  return math.floor(seconds / 86400) .. "d ago"
end
```

- [ ] **Step 3: Implement `M.resolve()`**

Replace the stub:

```lua
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
```

- [ ] **Step 4: Smoke check — list shows captured task, resolve deletes it**

Interactive:

```bash
nvim
```

1. `<leader>Kc` — capture a task (any objective). Save.
2. `<leader>Kl` — should show one entry: `[active] <project> — <objective>`.
3. `<Esc>` to dismiss the picker.
4. `<leader>Kx` — should prompt to resolve. Pick `yes`.
5. `<leader>Kl` — should now show "no captured tasks yet".

Cleanup: `rm -f ~/.local/state/nvim/resume_tasks.json` between runs.

- [ ] **Step 5: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: list (<leader>Kl) + resolve (<leader>Kx)

list shows all tasks across projects via vim.ui.select, sorted by
paused_at desc; selecting one cd's into the project root and opens its
brief. resolve deletes the current project's task with a confirm prompt.
Adds _humanize_age helper used by list labels.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Resume Brief panel — static (`<leader>Kr`)

Goal: `<leader>Kr` opens the four-section brand.win panel showing **captured** data only. The async "what changed" probes land in Task 6. Footer actions (resume / edit / resolve / close) all wired.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add `_panel()` builder**

Above `M._internal = ...`, add:

```lua
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

local function _panel(key, task)
  local brand = require("user.brand")
  local basename = vim.fn.fnamemodify(key, ":t")
  local age = task.paused_at and _humanize_age(os.time() - task.paused_at) or "active"
  local branch = task.branch or "(no branch)"

  local lines = { "" }
  local function row(text) table.insert(lines, "  " .. text) end
  local function section(label) table.insert(lines, ""); row(label); end

  section("VERIFY FIRST")
  row("  → " .. (task.verify_first ~= "" and task.verify_first or "(none specified)"))

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
    _resume_buffers(task)
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "e", function()
    panel.close()
    M.capture()
  end, { buffer = buf, silent = true })

  vim.keymap.set("n", "x", function()
    panel.close()
    M.resolve()
  end, { buffer = buf, silent = true })

  return panel, changed_section_line
end
```

- [ ] **Step 2: Replace `M.brief()` stub**

```lua
function M.brief()
  local key = _project_key()
  local task = _task(key)
  if not task then
    vim.notify("resume: no paused task here · <leader>Kc to capture", vim.log.levels.INFO)
    return
  end
  _panel(key, task)
  -- Task 6 will start async probes here and update the panel buffer in-place
end
```

- [ ] **Step 3: Smoke check — panel renders, actions work**

Interactive:

```bash
nvim
```

1. `<leader>Kc` — capture a task with `objective`, `next_step`, `verify_first`, `notes`. Save.
2. `<leader>Kr` — panel opens; verify it shows all four sections, VERIFY FIRST at top, "⠋ computing…" placeholder in WHAT CHANGED.
3. Press `q` — panel closes, task still exists (`<leader>Kl` shows it).
4. `<leader>Kr` again, press `r` — panel closes, file from the captured buffer set is reopened, `<leader>Kl` shows task as `[active]` (no `paused_at`).
5. `<leader>Kr` again, press `e` — capture form reopens pre-filled.
6. Save the form, then `<leader>Kr` + `x` — confirm resolve, task gone.
7. `<leader>Kr` with no task — should notify "no paused task here".

- [ ] **Step 4: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: brief panel — <leader>Kr renders captured data + footer actions

Four-section brand.win panel: VERIFY FIRST → WHAT YOU WERE DOING →
WHAT CHANGED (placeholder until task 6) → OPEN THREADS. Footer keys:
r resume (nils paused_at, increments resumed_count, reopens captured
file set + cursor), e edit (re-enters capture form), x resolve, q close.
Section labels styled via BrandChipAccent extmarks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `_what_changed` async probes

Goal: replace the `⠋ computing…` placeholder in the brief with live git + blackbox evidence. All async (`vim.system`), 3-second timeout per probe, never blocks the panel render.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add the probe orchestrator**

Above `_panel`, add:

```lua
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
    local timed_out = false
    local timer = vim.uv.new_timer()
    timer:start(3000, 0, vim.schedule_wrap(function()
      timed_out = true
      on_result(nil, true)
      done()
      pcall(function() timer:stop(); timer:close() end)
    end))
    vim.system(cmd, { text = true, cwd = cwd }, function(res)
      if timed_out then return end
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
```

- [ ] **Step 2: Wire the probes into `M.brief()`**

Replace `M.brief()`:

```lua
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
```

- [ ] **Step 3: Smoke check — probes return real data**

Interactive (in a git repo with recent commits):

```bash
cd ~/.config/nvim     # or any repo with recent commits
nvim
```

1. `<leader>Kc` — capture a task. Save.
2. **Outside nvim** (in another shell): make a trivial commit (e.g. `touch /tmp/dummy && cp /tmp/dummy . && git add . && git -c commit.gpgsign=false commit -m "test"`). Then `git rm dummy && git -c commit.gpgsign=false commit -m "undo"` so the repo is clean again.
3. Back in nvim: `<leader>Kr` — the WHAT CHANGED section should within ~3 seconds show one or more `• N commit(s) since pause` style lines.
4. Repeat with **no** intervening commit — section should show `(nothing notable)`.
5. Test the timeout path: temporarily edit the `run({ "git", "log", ...` line and replace with `run({ "sleep", "5" }, ...)`. Open brief — section should after 3s show `git timed out`. **Revert the change** before committing.

- [ ] **Step 4: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: live "what changed" probes in brief panel

Five parallel probes via vim.system: commits since pause, diff --stat
of the same window, branch divergence vs captured branch, missing-file
count, and a blackbox slice. 3-second timeout per git probe; on timeout
the row shows "git timed out" and panel render is never blocked.
Replaces the static "⠋ computing…" placeholder in-place once probes
finish.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: DirChanged auto-pause + auto-resume hint enqueue

Goal: switching projects auto-pauses the outgoing project's active task; landing in a project with a paused task queues a hint for the next `BufEnter` (the hint *render* lands in Task 9).

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add `_autocmds()`**

Above `M._internal = ...`, add:

```lua
local function _autocmds()
  local grp = vim.api.nvim_create_augroup("user_resume", { clear = true })

  -- DirChanged: project switch
  vim.api.nvim_create_autocmd("DirChanged", {
    group = grp,
    pattern = "global",
    callback = function(args)
      local old_cwd = args.file       -- previous cwd is in args.file per :h DirChanged
      -- _project_key has a single-entry cache; force re-resolve by invalidating
      _project_key_cache = nil
      local new_key = _project_key()
      local old_key = old_cwd and _project_key(old_cwd) or nil
      if old_key == new_key then return end

      -- pause the outgoing task if active
      if old_key and _state_of(old_key) == "active" then
        local t = _task(old_key)
        t.paused_at = os.time()
        t.files, t.cursor = _snapshot_files()
        _save()
      end

      -- enqueue hint if incoming project has a paused task
      if _state_of(new_key) == "paused" then
        _hint_queue[new_key] = true
      end
    end,
  })
end
```

(Note: per `:h DirChanged`, `args.file` carries the *previous* cwd. Verify this in step 4 — if it doesn't behave as documented on your nvim version, fall back to tracking `_last_cwd` in module state, the way `recall.lua` does.)

- [ ] **Step 2: Call `_autocmds()` from `M.setup()`**

Update `M.setup()`:

```lua
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  _load()
  _autocmds()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("user_resume_persist", { clear = true }),
    callback = function() _save() end,
  })
end
```

- [ ] **Step 3: Make `_project_key_cache` module-mutable**

The `_autocmds()` callback invalidates the cache by writing `_project_key_cache = nil`. That works only if `_project_key_cache` is declared at file scope (it is per Task 2 step 2). Verify by reading the file — no change should be needed, just confirm.

- [ ] **Step 4: Smoke check — DirChanged pauses the outgoing task**

Interactive:

```bash
mkdir -p /tmp/proj-a /tmp/proj-b
cd /tmp/proj-a && git init -q
nvim
```

1. `<leader>Kc` — capture a task. Save.
2. `<leader>Kl` — verify it shows `[active]`.
3. `:cd /tmp/proj-b` — triggers DirChanged.
4. `<leader>Kl` — verify the proj-a task is now `[paused]`.
5. `:cd /tmp/proj-a` — should re-mark for hint (we can't yet see it; verify by inspecting `_hint_queue` from `:lua`):

```vim
:lua print(vim.inspect(require('user.resume')._internal_hint_queue))
```

If that returns nil (we didn't expose `_hint_queue`), check via direct file access — add a one-shot debug print inside the autocmd if needed and revert it before commit. Or expose `_hint_queue` on `M._internal` temporarily:

```lua
-- temporarily add to M._internal table:
hint_queue = _hint_queue,
```

Verify `_hint_queue["/private/tmp/proj-a"]` (or whatever the canonical key is) is `true`. Then remove the debug exposure before commit if you don't want it permanent — but keeping it is harmless and useful for the next tasks' debugging, so I'd leave it in.

Cleanup: `rm -rf /tmp/proj-a /tmp/proj-b ~/.local/state/nvim/resume_tasks.json`.

- [ ] **Step 5: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: DirChanged auto-pause + paused-task hint enqueue

Switching projects (DirChanged scope=global) pauses the outgoing
project's active task — stamps paused_at, refreshes files+cursor
snapshot, persists. Switching INTO a project with a paused task queues
the project_key in _hint_queue; the BufEnter consumer + render layer
land in tasks 8 and 9.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: FocusGained capture-toast + paused-task hint enqueue

Goal: the conservative triggers — `FocusGained` after long-enough idle either offers capture (project is Uncaptured but actively edited) or enqueues a hint (project is Paused). Branch change prompt lands in Task 10.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add capture-toast helper**

Above `_autocmds()`, add:

```lua
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

  -- Global one-shot keymaps that survive the non-focusable float.
  local function teardown()
    pcall(vim.keymap.del, "n", "<Plug>(resume-toast-y)")
    pcall(vim.keymap.del, "n", "<Plug>(resume-toast-n)")
    if panel and panel.close then panel.close() end
  end

  -- Use buffer-local keymaps on the CURRENT buffer (where focus actually is),
  -- not on the toast's buffer (which we made non-focusable).
  local target_buf = vim.api.nvim_get_current_buf()
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
```

(Heads-up: the global `y`/`n` keymaps during the 4-sec window are intentionally aggressive — they shadow built-ins (`yank` and reverse-find-prev). That's the cost of one-tap accept. If you find it bites you, change the keys to `<C-y>`/`<C-n>` or scope to only certain modes. Either way: 4 seconds is short enough that the risk is bounded.)

- [ ] **Step 2: Extend `_autocmds()` with FocusLost/FocusGained**

Add inside `_autocmds()`, after the DirChanged block:

```lua
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
```

- [ ] **Step 3: Smoke check — FocusGained logic**

Interactive — fully manual since FocusGained needs an actual window-manager focus event:

```bash
cd /tmp/proj-a   # or any uncaptured git repo
nvim
```

1. Type some text in a buffer (triggers TextChanged → `_project_active_since` gets set).
2. **Manually fake the idle:** `:lua require('user.resume')._internal.fake_idle()` — needs a temporary helper. Add this to `M._internal` for the duration of testing:

   ```lua
   fake_idle = function() _last_focus_lost = vim.uv.now() - (16 * 60 * 1000) end,
   ```

3. Switch to another app (FocusLost fires). Switch back (FocusGained fires).
4. Toast should appear in top-right asking to capture.
5. Press `y` — capture form opens.
6. Repeat the experiment but press `n` — toast dismisses, no form.
7. Repeat once more, don't press anything for 4s — toast auto-dismisses.

Now test the paused-task path:

1. `<leader>Kc` capture a task and save.
2. `:cd /tmp` (DirChanged pauses it).
3. `:cd /tmp/proj-a` (back; new key matches paused — `_hint_queue` gets set).
4. **Fake the idle** as above. Defocus + refocus.
5. `:lua print(vim.inspect(require('user.resume')._internal.hint_queue))` — should still show the key. (Render happens in Task 9.)

Remove the `fake_idle` helper before commit, or keep it as a permanent debug aid. I'd remove it.

- [ ] **Step 4: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: FocusGained capture-toast + paused-task hint enqueue

FocusGained after idle > idle_capture_ms fires a tiny brand.win toast
in the top-right with one-shot y/n keymaps (4-sec auto-dismiss) — but
only for Uncaptured projects you've actively been editing (tracked via
TextChanged → _project_active_since). For Paused projects after
idle_hint_ms, the project key is queued in _hint_queue for the next
BufEnter (render in task 9). Calm Tech: zero prompts in steady state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Ambient virtual-text hint render

Goal: `BufEnter` consumer for `_hint_queue`. Renders one line of virtual text at the top of the buffer, accent-styled, fades after `hint_dwell_ms` or on `CursorMoved`. Respects `excluded_filetypes` and `hint_rate_limit_ms`.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add `_hint()` render**

Above `_autocmds`, add:

```lua
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
```

- [ ] **Step 2: Extend `_autocmds()` with BufEnter consumer**

Add inside `_autocmds()`, after the FocusGained block:

```lua
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
```

- [ ] **Step 3: Smoke check — hint renders, fades, doesn't repeat**

Interactive:

```bash
cd /tmp/proj-a    # or any git repo with a captured task
nvim
```

1. `<leader>Kc` capture, save.
2. `:cd /tmp` (DirChanged pauses).
3. `:cd /tmp/proj-a` (queues hint).
4. `:e some_file.txt` (creates new buffer; BufEnter fires; hint should render).
5. Wait 10 seconds — virtual text should disappear.
6. `:e another_file.txt` — within the rate limit window, hint should NOT re-appear.
7. Manually clear rate limit: `:lua require('user.resume')._internal.last_hint = {}` then `:e third_file.txt` — but `_hint_queue` was already drained, so still no hint. Re-trigger via `:cd /tmp && :cd /tmp/proj-a && :e fourth.txt` — hint should re-appear.
8. Cursor-move test: re-trigger, then immediately move cursor — hint should clear instantly.

For step 7's `_internal.last_hint` access, expose it temporarily on `M._internal` if not already, then remove. Or leave exposed permanently — it's debug-useful.

Cleanup: `rm -f ~/.local/state/nvim/resume_tasks.json`.

- [ ] **Step 4: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: ambient virtual-text hint on BufEnter

Renders one line of virt_text at the top of the buffer styled with
BrandChipAccent: "⟳ paused 47m: <objective> — <leader>Kr to resume".
Fades after hint_dwell_ms (default 10s) or on first CursorMoved.
BufEnter consumer drains _hint_queue, respects hint_rate_limit_ms
per-project and excluded_filetypes. hint_enabled=false short-circuits
(lualine chip fallback noted as TODO; out of scope for v1).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Branch change prompt

Goal: when the current branch changes (e.g. `git checkout other`), if there's an active task whose captured `branch` differs from the new one, offer (don't force) pausing the task.

**Files:**

- Modify: `lua/user/resume.lua`

- [ ] **Step 1: Add a lightweight branch watcher**

Inside `_autocmds()`, after the BufEnter block:

```lua
  -- Branch-change detection: poll on common git-affecting events. Cheap
  -- because _current_branch shells out once per event, not on a timer.
  local _last_branch = _current_branch()
  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "DirChanged" }, {
    group = grp,
    callback = function()
      if not M.opts.branch_change_prompt then return end
      local new_branch = _current_branch()
      if not new_branch or new_branch == _last_branch then return end
      local prev_branch = _last_branch
      _last_branch = new_branch
      local key = _project_key()
      local task = _task(key)
      if not task or _state_of(key) ~= "active" then return end
      if task.branch == new_branch then return end       -- already aligned
      _branch_change_toast(prev_branch or "?", new_branch, key, task)
    end,
  })
```

- [ ] **Step 2: Add `_branch_change_toast()` helper**

Above `_capture_toast`, add:

```lua
local function _branch_change_toast(from, to, key, task)
  local brand = require("user.brand")
  local text = " branch " .. from .. " → " .. to .. " · pause task?  [y]es  [n]o "
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  local panel = brand.win({
    title = "resume",
    width = math.max(50, #text + 4),
    height = 1,
    anchor = "tr",
    focusable = false,
    animate = false,
    buf = buf,
    close_keys = {},
  })
  local target_buf = vim.api.nvim_get_current_buf()
  local function teardown()
    pcall(vim.keymap.del, "n", "y", { buffer = target_buf })
    pcall(vim.keymap.del, "n", "n", { buffer = target_buf })
    if panel and panel.close then panel.close() end
  end
  vim.keymap.set("n", "y", function()
    teardown()
    task.paused_at = os.time()
    task.files, task.cursor = _snapshot_files()
    _save()
  end, { buffer = target_buf, silent = true, nowait = true })
  vim.keymap.set("n", "n", teardown,
    { buffer = target_buf, silent = true, nowait = true })
  vim.defer_fn(teardown, 4000)
end
```

- [ ] **Step 3: Smoke check — branch change offers pause**

Interactive in any git repo:

```bash
cd /tmp/proj-a
git branch other 2>/dev/null
nvim
```

1. `<leader>Kc` capture a task (captured branch will be `main` or whatever HEAD is at). Save.
2. `:!git checkout other` — outside nvim semantics: switch branches. Triggers BufEnter (or DirChanged on some setups). Toast should appear within a second or two.
3. Press `y` — task gets paused.
4. `<leader>Kl` confirms `[paused]`.

If the toast doesn't fire on `:!git checkout`, that's because `:!` doesn't auto-fire BufEnter for the same buffer. Workaround: `:e` to re-enter the buffer after the checkout, or rely on the next real BufEnter. Acceptable — branch detection is best-effort.

- [ ] **Step 4: Commit**

```bash
git add lua/user/resume.lua
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
resume: branch change prompt (optional, 4-sec toast)

When _current_branch() drifts from the captured task's branch, fire a
brand.win y/n toast offering to pause. Polled on FocusGained / BufEnter
/ DirChanged — no extra timer. Disabled via branch_change_prompt=false;
default y/n auto-dismisses after 4 sec.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Final verification + README update

Goal: run the full smoke matrix from the spec, the doctor sweep, the async-only enforcement check, then document the feature in `README.md`.

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Doctor sweep — keymaps + actionable issues**

```bash
./scripts/doctor.sh keymaps
./scripts/doctor.sh
```

Expected: no errors / warnings attributable to `user.resume`. If anything fires, fix before continuing.

- [ ] **Step 2: Async-only enforcement**

```bash
rg "vim\.fn\.system\b" lua/user/resume.lua
```

Expected: a small number of hits ONLY in `_project_key` and `_current_branch` (these are called synchronously from autocmds and are documented as fast). Any other hit should be moved to `vim.system{}` async. Specifically: no `vim.fn.system` inside `_what_changed`, `_form`, `_panel`, or render paths.

- [ ] **Step 3: Run the full smoke matrix from the spec**

Walk through `docs/superpowers/specs/2026-05-29-resume-lua-design.md` § "Manual smoke matrix (run after impl)" — all 9 cases. Note any deviation; fix anything that doesn't match the spec. If something only partially works, file a follow-up note in the commit message rather than declaring done.

- [ ] **Step 4: Update `README.md`**

Find the section that documents user modules (search for `## Headline features` or similar). Add a new subsection. Match the surrounding tone — terse, command-oriented, references to leader keys.

Example block to add (adapt to the file's structure once you read it):

```markdown
### `user.resume` — task intent across interruptions

`<leader>Kc` captures the current task (objective, next step, what to
verify first, freeform notes). `<leader>Kr` opens the **Resume Brief**
— a four-section panel showing what you were doing, what changed in
the repo while you were away (commits, file churn, branch divergence),
and any open threads. `<leader>Kl` lists paused tasks across all
projects; `<leader>Kx` resolves the current project's task.

State is project-keyed (git toplevel) and stored at
`~/.local/state/nvim/resume_tasks.json`. Switching directories
auto-pauses the outgoing task; returning to a project with a paused
task surfaces a subtle virtual-text hint on the next BufEnter.

Inspired by [vscode-tacos](https://github.com/jkordish/vscode-tacos);
adapted to nvim and scoped to the genuine novelty. Design grounded in
Calm Tech (Weiser 1995) — zero prompts during a steady-state focused
hour.
```

- [ ] **Step 5: Final commit**

```bash
git add README.md
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
docs: README — document user.resume (capture / brief / list / resolve)

Adds a subsection in the headline-features area covering the four
leader keys, the state file location, the auto-pause-on-DirChanged
behavior, and the design lineage from vscode-tacos. Cites Calm Tech
inline per the project's HCI-grounded-design convention.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Confirm the branch is shippable**

```bash
git log --oneline main..HEAD
./scripts/doctor.sh
```

Expected: 11 commits (one per task) on the working branch. Doctor clean. Ready for PR (or direct merge to main per user preference).

---

## Self-Review Notes

Spec requirements → task coverage:

- ✅ Task object with `objective` / `next_step` / `verify_first` / `notes` / `blockers` / `files` / `cursor` / `branch` / `started` / `paused_at` / `resumed_count` → Task 2 (data model), Task 3 (capture).
- ✅ Project-keyed storage with version + atomic write + corruption recovery → Task 2.
- ✅ Capture form (Tab cycling, brand.win, three structured + notes) → Task 3.
- ✅ Resume Brief (four sections, VERIFY FIRST first, footer actions r/e/x/q) → Task 5.
- ✅ Live "what changed" (git probes + blackbox slice, 3s timeout, async) → Task 6.
- ✅ Cross-project list → Task 4.
- ✅ Resolve → Task 4.
- ✅ DirChanged auto-pause + hint enqueue → Task 7.
- ✅ FocusGained capture-toast (with `_project_active_since` guard) → Task 8.
- ✅ FocusGained paused-task hint enqueue → Task 8.
- ✅ Ambient virtual-text hint render with rate limit + fade → Task 9.
- ✅ Branch change prompt → Task 10.
- ✅ Excluded filetypes / paths → enforced in Task 3 (`_is_excluded` in `M.capture`), Task 8 (TextChanged guard), Task 9 (BufEnter + hint).
- ✅ State registry integration → Task 1.
- ✅ `blackbox.since()` helper → Task 1.
- ✅ `<leader>K{c,r,x,l}` wiring → Task 1.
- ✅ VimLeavePre force-save → Task 2.
- ✅ Calm Tech citation in module header → Task 1.
- ✅ Smoke matrix + doctor sweep + README → Task 11.
- ✅ Out-of-scope items (suggest action, provenance chip, debrief, archive, AI hookup, per-branch tasks, deep tier) — none of them appear as tasks. Correct.

No placeholders, no "TBD", no "similar to Task N" — every step has its code.

Type consistency: `_state.tasks[key]` table shape is identical across capture (Task 3), brief (Task 5), what-changed (Task 6), dir-changed (Task 7), branch-change (Task 10). `_hint_queue` and `_last_hint` keyed by `project_key` everywhere. `_project_active_since` keyed the same. `panel.close()` returned by `brand.win` is used identically in every surface.
