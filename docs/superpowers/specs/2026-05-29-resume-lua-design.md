# `user.resume` — design spec

**Date:** 2026-05-29
**Status:** Approved for planning
**Inspiration:** [`vscode-tacos`](https://github.com/jkordish/vscode-tacos) — adapted to nvim, scoped to the genuine novelty.

## Motivation

`vscode-tacos` is a "local-first cognitive recovery tool" — it captures task intent before context switches and surfaces an evidence-backed brief on return. Our nvim config has rich *activity* awareness (`blackbox`, `today`, `recall`, `suggest`) but no first-class **task intent** object. Coming back to a project after lunch or a meeting requires reconstructing "what was I doing" from git log and open buffers — every time.

This module adds three things TaCoS proved valuable, in a shape that composes with our existing design system:

1. A first-class task object (objective / next-step / verify-first / notes).
2. A Resume Brief panel that mixes captured intent with live evidence ("what changed while I was away").
3. Conservative switch-detection that prompts only when context is actually shifting — never during steady-state work.

This is **Option B** from the comparative review: the minimal version that earns "this changes how I work." Suggest integration, provenance chip, and cognitive debrief are explicit YAGNI for v1 (see Out of Scope).

## Design principles

- **Calm Tech** (Mark Weiser, 1995): zero prompts during a typical focused hour. The module emerges only at context boundaries.
- **Anticipatory design**: `verify_first` is pre-staged for *future you*, not retrospective documentation.
- **Feedforward**: the brief shows what to check *before* showing what you were doing — eyes on verification before muscle memory restarts.
- Respect the codebase's existing design vocabulary: one accent, brand chips, `brand.win`, mode-reactive borders. No new highlight groups, no parallel design system.

## Architecture

One file: `lua/user/resume.lua` (~300 lines, scale comparable to `recall.lua`/`today.lua`).

### Module surface

```
M.setup(opts)        -- entry point; wires autocmds
M.capture()          -- <leader>tc — opens capture form
M.brief()            -- <leader>tr — opens Resume Brief panel
M.resolve()          -- <leader>tx — mark task done
M.list()             -- <leader>tl — paused tasks across all projects

-- internal --
_state               -- in-memory mirror of tasks.json
_load() / _save()    -- persistence (atomic via tmp + rename)
_project_key()       -- canonical project root
_autocmds()          -- DirChanged / FocusLost / FocusGained handlers
_hint()              -- virtual-text ambient surface
_what_changed()      -- async: git log + diff stat + blackbox slice
_form() / _panel()   -- brand.win surfaces
```

### Wiring (per CLAUDE.md convention)

- **`lua/plugins/user-modules.lua`** Phase 3 (daily-driver tools), after `jobs` and before `spotlight`: `require("user.resume").setup()`.
- **Keymaps** on the same pseudo-spec's `keys = {...}` table: `<leader>tc`/`tr`/`tx`/`tl`. The `t` leader namespace is currently unused.
- **`lua/user/state.lua` registry** gets one new entry:
  ```lua
  { id = "resume", path = STATE_DIR .. "/resume_tasks.json",
    desc = "Resume · paused tasks per project + verify-first cues", json = true },
  ```
- **`lua/user/blackbox.lua`** gets one small additive helper: `M.since(epoch_seconds)` returns the entries newer than the timestamp. No behavior change to existing blackbox API.

### Dependencies

All internal:

- `user.brand` — `brand.win()` for form + panel; `BrandChipAccent`/`Warn` for chips. Hard require.
- `user.toast` — soft "capture this work?" prompts. Soft require (`pcall`).
- `user.blackbox` — evidence slice for the brief. Soft require.
- `vim.system` — async `git log` + `git diff --stat` for the changed-files section.

**No new plugins.** Pure first-party module.

## Data model

**File:** `~/.local/state/nvim/resume_tasks.json` (registered with `state.lua`).

```jsonc
{
  "version": 1,
  "tasks": {
    "/Users/joe/code/proj-a": {        // ← project_key (git toplevel or cwd)
      "objective":    "refactor token refresh to use retry middleware",
      "next_step":    "wire retry into AuthMiddleware.handle()",
      "verify_first": "check API contract didn't change after main rebase",
      "notes":        "remember postgres needs --restart\nstaging deploy pending",
      "blockers":     [],              // reserved; UI hidden until non-empty
      "branch":       "feature/token-refresh",
      "started":      1717000000,      // epoch seconds
      "paused_at":    1717003420,      // null when active
      "files":        [                // cwd-relative
        "src/auth/middleware.ts",
        "tests/auth/middleware.test.ts"
      ],
      "cursor":       { "file": "src/auth/middleware.ts", "line": 47, "col": 12 },
      "resumed_count": 3
    }
  }
}
```

### Task lifecycle (three states)

A given project is in exactly one of these states at any time:

1. **Uncaptured** — no entry in `tasks{}` for this project key. The default state.
2. **Active** — entry exists, `paused_at = null`. There's intent recorded and you're currently working on it.
3. **Paused** — entry exists, `paused_at` is an epoch timestamp. The task is parked; resuming sets `paused_at` back to null and increments `resumed_count`.

Transitions: `Uncaptured → Active` via `<leader>tc`. `Active → Paused` via `DirChanged` away. `Paused → Active` via `<leader>tr` `r` (resume). `Active/Paused → Uncaptured` via `<leader>tx` (resolve).

### Key decisions

- **`version: 1`** at top level — future migrations have a hook.
- **Project key** resolved by `git rev-parse --show-toplevel`, falling back to `vim.uv.cwd()`. Same fingerprint `suggest.lua` uses.
- **One task per project, period.** Capturing a second task overwrites the first (with confirm prompt if `confirm_overwrite = true` and existing task has `objective` set).
- **`paused_at = null` means active.** `M.capture()` nils it on first capture; `DirChanged` away sets it to `os.time()`; resume nils it again and increments `resumed_count`.
- **`files` captured at pause time, not continuously updated** — by design. The brief diffs "open then" vs "open now" as additional signal.
- **No `id` field** — the project key IS the id.

### Persistence

- **Atomic write:** `_save()` writes to `resume_tasks.json.tmp` then `os.rename()` (POSIX-atomic). Matches the pattern `yankring.lua` uses.
- **Corruption recovery:** `_load()` wraps `vim.json.decode` in `pcall`. On failure, rename to `resume_tasks.json.broken.<ts>` and start fresh. One toast notifies. Matches `suggest.lua` / `playbooks.lua` precedent.
- **Concurrency:** two nvim instances on the same project → last-write-wins. Documented limitation; not worth file-locking for v1.

## Surfaces

### Capture form (`<leader>tc`)

`brand.win` float, ~70 cols × ~14 rows. Three structured fields + freeform notes, all visible at once; user Tab/Shift-Tab between fields.

```
  ┌─ capture this task · ~/code/proj-a · feature/token-refresh ──┐
  │                                                               │
  │  OBJECTIVE                                                    │
  │  > refactor token refresh to use retry middleware             │
  │                                                               │
  │  NEXT STEP                                                    │
  │  > wire retry into AuthMiddleware.handle()                    │
  │                                                               │
  │  VERIFY FIRST  (what to check before resuming)                │
  │  > check API contract didn't change                           │
  │                                                               │
  │  NOTES  (optional, ⏎⏎ to save)                                │
  │  >                                                            │
  │                                                               │
  │  [⏎] save   [tab] next field   [esc] cancel                   │
  └───────────────────────────────────────────────────────────────┘
```

- Header chip shows project basename + branch (live).
- Pre-fills from existing task if one exists; title flips to *edit this task*.
- Captures auto-fields (`files`, `cursor`, `started` if new) on save.
- **Implementation note:** single modifiable buffer in the float with label lines marked read-only via extmarks (same trick `commandeer.lua` uses for filter chips). Avoids writing a custom multi-field input widget.

### Ambient hint (virtual text)

Fires on `BufEnter` into a project with a paused task if `idle_hint_ms` has elapsed since last hint emission. One line of virtual text at top of buffer:

```
⟳ paused 47m: refactor token refresh — <leader>tr to resume
```

- Color: `BrandChipAccent`.
- Fades after `hint_dwell_ms` (default 10s) or on first keystroke (`CursorMoved` once + timer).
- Suppressed if buffer filetype is in `excluded_filetypes` (default list mirrors `today.lua`).
- Per-project rate limit (`hint_rate_limit_ms`, default 5min).
- **Disable path:** `opts.hint_enabled = false` falls back to a lualine chip (`⟳ paused`) — the brief is still always reachable via `<leader>tr`.

### Resume Brief panel (`<leader>tr`)

`brand.win` float, ~76 cols × ~22 rows. `winhighlight` inherits `FloatBorder` so it retunes with mode-accent per CLAUDE.md.

Render order is **deliberate** (feedforward principle): `VERIFY FIRST` first, intent next, evidence third, unresolved last.

```
  ┌─ paused 47m ago · feature/token-refresh · ~/code/proj-a ─────┐
  │                                                               │
  │  VERIFY FIRST                                                 │
  │    → check API contract didn't change after main rebase       │
  │                                                               │
  │  WHAT YOU WERE DOING                                          │
  │    objective: refactor token refresh to use retry middleware  │
  │    next step: wire retry into AuthMiddleware.handle()         │
  │                                                               │
  │  WHAT CHANGED WHILE YOU WERE AWAY                             │
  │    • 2 commits on main (rebase needed)                        │
  │    • 3 files modified by you in other branches                │
  │    • blackbox: 12 events (last: :write at 14:02)              │
  │                                                               │
  │  OPEN THREADS                                                 │
  │    notes: remember postgres needs --restart                   │
  │           staging deploy pending                              │
  │                                                               │
  │  [r]esume  [e]dit  [✓]resolve  [q]close                       │
  └───────────────────────────────────────────────────────────────┘
```

**Live-computed sections** — `WHAT CHANGED` runs three async probes in parallel via `vim.system`:

- `git log --oneline <captured_branch>..HEAD` (if branch differs from captured)
- `git log --since=<paused_at> --oneline` (commits in the window)
- `git diff --stat <ref-at-paused_at>` (file-level churn)
- `blackbox.since(paused_at)` count + last event (synchronous, in-memory)

Each probe shows `⠋ <label>...` until it returns; on completion swaps in the result. Stale data after 30s shows a `[refresh]` hint. Pattern matches `today.lua`'s parallel git probes.

**Footer actions** (single-key, no leader prefix while panel is focused):

| Key | Action |
|---|---|
| `r` | Resume — restore captured buffers, jump cursor to captured position, nil `paused_at`, increment `resumed_count`, close panel. Missing files skipped silently. |
| `e` | Edit — close panel, reopen capture form pre-filled. |
| `x` | Resolve — confirm prompt (`y`/`n`), delete task entry, close panel. |
| `q` / `<Esc>` | Close — non-destructive; task stays paused. |

### Cross-project list (`<leader>tl`)

Small `spotlight.lua`-style float (or `vim.ui.select` if simpler). Lists all paused tasks across all projects, sorted by `paused_at` desc. `<CR>` `cd`s to that project root and opens its brief. Seed of a future cognitive-debrief surface without committing to it.

## Triggers & config

### Autocmds

Group: `user_resume` (cleared on each `setup()` call).

| Event | Filter | Action |
|---|---|---|
| `DirChanged` | `scope=global` AND new key ≠ old key | If old project is **Active** (see lifecycle) → set `paused_at = now`, persist. If new project is **Paused** → enqueue hint for next `BufEnter`. |
| `FocusLost` | — | Stamp `_last_focus_lost = uv.now()` (in-memory). Also stamps `_project_active_since[key] = now` if not already set — used to detect "actively edited but uncaptured" below. |
| `FocusGained` | — | If `away > idle_capture_ms` AND current project is **Uncaptured** AND `_project_active_since[key]` is older than `idle_capture_ms` → fire capture-toast ("you've been working on this for a while — capture it?"). If `away > idle_hint_ms` AND current project is **Paused** → enqueue hint. |
| `BufEnter` | ft not excluded AND hint queued AND `> hint_rate_limit_ms` since last hint for this project | Render virtual text; clear queue. |
| `User GitBranchChanged` | (emitted by `user.starship`'s existing branch-watch, or a new lightweight watcher if absent) | If active task's `branch` ≠ new branch → soft toast: *"branch changed — pause current task? [y/n]"*. 4-sec window, default no. |
| `VimLeavePre` | — | Force-save in-memory `_state` to disk. |

### Config table

```lua
require("user.resume").setup({
  -- timing
  idle_capture_ms     = 15 * 60 * 1000,  -- focus-away threshold to offer capture
  idle_hint_ms        =  5 * 60 * 1000,  -- focus-away threshold to surface hint
  hint_dwell_ms       = 10 * 1000,       -- how long virtual text stays
  hint_rate_limit_ms  =  5 * 60 * 1000,  -- min between hints for same project

  -- behavior
  hint_enabled        = true,            -- false → lualine chip fallback
  branch_change_prompt = true,           -- prompt to pause on branch switch
  auto_resume_buffers  = true,           -- 'r' action reopens captured file set
  confirm_overwrite    = true,           -- ask before overwriting an existing task

  -- exclusions
  excluded_filetypes  = { "neo-tree", "lazy", "mason", "qf", "help", "TelescopePrompt" },
  excluded_paths      = { vim.fn.stdpath("config") }, -- don't run while editing nvim config
})
```

### Trigger design judgment calls

- **Idle is wall-clock** (`FocusLost`/`FocusGained` derived), not active-typing. Matches `recall.lua`. Works for laptop-closed, Slack-switch, lunch.
- **Capture toast is 4-second auto-dismiss, default skip.** Critical for non-annoyance: ignoring it leaves no record. Opposite default would risk stray `<CR>` spawning a form mid-flow.
- **Capture toast only fires for Uncaptured projects you've been editing.** If a task already exists for the project (Active or Paused), no capture prompt — toast frequency stays near zero in steady state. The `_project_active_since` map ensures we don't prompt on a project you just `cd`'d into without doing any work.
- **Branch change is intent-ambiguous.** `feature/foo → feature/foo-fix` is a pivot; `feature/foo → main` is usually browsing. Module asks (4-sec toast) rather than acting. `branch_change_prompt = false` disables; task carries the stale branch label until re-captured.
- **`excluded_paths` defaults to nvim config dir** so this doesn't fire while editing the module itself.

### Defaults rationale

15min capture / 5min hint / 10s dwell / 5min hint rate-limit. A typical focused hour fires **zero** prompts. Cited inline in module header (Calm Tech — Weiser 1995).

## Edge cases

| Case | Behavior |
|---|---|
| No git repo | `project_key` falls back to `cwd`. `WHAT CHANGED` degrades gracefully; git probes hide, shows `(no git)`. |
| No captured task in current project | `<leader>tr` shows one-line float: *"no paused task here · `<leader>tc` to capture"*. Auto-dismiss on any key. |
| File deleted/moved between capture and resume | `r` skips missing files silently. Brief marks them in `WHAT CHANGED`: `- 2 captured files no longer exist`. |
| Branch deleted | Brief renders branch chip in `BrandChipWarn` with `(branch deleted)`. Resume works at cwd level. |
| Corrupted `resume_tasks.json` | Renamed to `.broken.<ts>`, fresh state, one toast. Matches `suggest.lua` pattern. |
| Two nvim instances, same project | Last-write-wins. Documented limitation. Acceptable per existing precedent. |
| Git command slow/hangs | 3-second timeout per `vim.system` call. On timeout: section shows `(git timed out)`, rest of panel renders. Never blocks. |
| `blackbox.since()` returns thousands | Display capped at last 50, with `(+N more)`. Blackbox MAX is 500 — cheap. |
| Empty buffer / scratch buffer | Capture allowed; `files = {}`, `cursor = nil`. Brief omits file-list. |
| `:UserStateClear resume` | All tasks dropped. Standard `state.lua` integration, no special handling. |

## Error handling philosophy

Match the rest of `lua/user/`: surface-don't-crash. Every async callback `vim.schedule`-wrapped and `pcall`'d on the render path. A broken probe shows `(error)` in its section; never propagates. Module has hard-require only on `brand`; `toast` and `blackbox` are soft-required (`pcall(require, ...)`) so a typo or rename elsewhere doesn't break resume.

## Testing strategy

Per CLAUDE.md: *"there is no test suite. Changes are validated by launching Neovim and observing behavior."*

### Static checks (must pass before merge)

- `./scripts/doctor.sh keymaps` — no `<leader>t*` collisions after wiring.
- `./scripts/doctor.sh` (default actionable mode) — no new warnings attributable to `user.resume`.
- `rg "vim\.fn\.system\b" lua/user/resume.lua` — must return nothing. Enforces async-only pattern.

### Manual smoke matrix (run after impl)

1. **Fresh state:** `<leader>tc` opens form → save → file shows in `:UserState` → `<leader>tr` renders brief.
2. **Switch away:** `cd` to another project → first task's `paused_at` set; no prompt (no active task in new project).
3. **Switch back:** `cd` back → next `BufEnter` shows virtual-text hint exactly once; fades after 10s.
4. **Persistence:** restart nvim → state survives, `<leader>tl` shows the paused task.
5. **Corruption recovery:** `echo garbage > resume_tasks.json` → restart → toast fires, `.broken` archive created, fresh state.
6. **Resume action:** `<leader>tr` → `r` → buffers reopen, cursor restored, `paused_at` nilled, `resumed_count` incremented.
7. **Resolve action:** `<leader>tr` → `x` → confirm `y` → task deleted, `:UserState` reflects empty.
8. **Idle threshold:** `:lua vim.cmd.doautocmd('FocusGained')` after manually back-dating `_last_focus_lost` → verify capture toast fires at the right threshold.
9. **Excluded path:** open nvim config dir → no autocmds fire, no hint.

## Out of scope for v1 (explicit YAGNI)

These are reachable in 1-2 lines once the foundation is in place. Not part of this spec.

- **Suggest integration** — `resume_task` action in `lua/user/suggest.lua`'s `ACTIONS`. One entry that fires when current project has a paused task.
- **Provenance chip** — `● Local-only` / `● AI used` lualine segment via `starship.lua`. TaCoS-flavored but separable concern.
- **Cognitive Debrief** cross-day view — `<leader>tl` covers the immediate need; richer aggregation can come later.
- **Archive on resolve** — `resume_archive.jsonl` append-only log of finished tasks. Wait for actual demand.
- **AI integration** — `ai_cmd.lua` hookup to draft `verify_first` or summarize `notes`. Separate concern.
- **Per-branch tasks within one project** — wait for actual pain. Branch is the differentiator most of the time and shows on the brief header.
- **Deep evidence tier** (TaCoS Option C) — `<leader>tR` full-split with full blackbox timeline + `git log -p`. Glanceable view probably answers 95%; add only if missed.

## File-level change summary

| File | Change |
|---|---|
| `lua/user/resume.lua` | **new** — ~300 lines, module implementation |
| `lua/plugins/user-modules.lua` | add `require("user.resume").setup()` in Phase 3; add 4 `<leader>t*` keymaps |
| `lua/user/state.lua` | add one entry to `registry()` |
| `lua/user/blackbox.lua` | add `M.since(epoch_seconds)` helper (additive) |
| `README.md` | add section under user-modules describing resume (after impl, separate commit) |
| `docs/superpowers/specs/2026-05-29-resume-lua-design.md` | this file |
