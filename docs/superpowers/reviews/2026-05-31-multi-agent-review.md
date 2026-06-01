# Multi-agent code review — 2026-05-31

Four parallel agents reviewed `lua/user/` (~60 modules) and `lua/plugins/` (~30 specs) through distinct lenses: **[SEC]** security · **[BUG]** correctness · **[DRY]** duplication/coupling · **[LUA]** Lua/nvim conventions. Findings below are merged across agents, deduplicated, and ranked by severity. Each item is a checkbox so this doubles as a triage list.

> Methodology notes: agents worked from CLAUDE.md context, not session history; `_play/` novelty modules were excluded from scope. No agent had access to the others' findings — overlaps (e.g. compass blocking I/O surfacing in both [BUG] and [LUA]) are independent confirmations.

---

## CRITICAL — fix before next push

- [ ] **[SEC] Auto-`dofile` of project-local `.suggest.lua` on every Suggest open** — `lua/user/suggest.lua:715-726`
  - Opening any malicious repo and pressing `<Space><Space>` → arbitrary Lua execution with full editor privileges. `pcall(dofile, path)` runs the file body *before* `validate_action` ever inspects the returned table.
  - **Fix:** prompt-on-first-encounter, persist SHA256-keyed trust file at `~/.local/state/nvim/suggest_trust.json`; or require explicit `:SuggestProjectTrust` per repo. Vim's `exrc`/`secure` model is the precedent.

- [ ] **[SEC] Same pattern in `lua/user/checklist.lua:68-77`** — `dofile(cwd .. "/.preflight.lua")` runs on every `:Checklist`/preflight with no trust check. Identical fix.

- [ ] **[SEC] Webhook `/eval` endpoint is auth-optional by default** — `lua/user/webhook.lua:50-58, 81-85`
  - `vim.g.webhook_token` defaults to nil; `check_token` returns true when no token is set. Any local process (including a browser tab via CORS-less POST to `http://localhost:7777/eval`) can run arbitrary Ex commands → `:!rm -rf` / `:lua os.execute(...)`.
  - **Fix:** (a) refuse to start `/eval` without a token configured, (b) add `Origin`/`Sec-Fetch-Site` checks against browser-driven CSRF, (c) document `webhook_token` as mandatory in README. Consider dropping `/eval` entirely — `/open` + `/notify` cover the legitimate use cases.

---

## HIGH — real bugs, broken features, or change-amplification at scale

- [ ] **[BUG] Jumplist navigation is broken** — `lua/user/jumppulse.lua:93-94`
  - `vim.cmd("normal! 1" .. "\\<C-o>")` does NOT interpret the escape; pressing `<C-o>` after `gd` inserts literal characters and does nothing. Error is swallowed by `pcall`.
  - **Fix:** `local CTRL_O = vim.api.nvim_replace_termcodes("<C-o>", true, false, true)` then `nvim_feedkeys(vim.v.count1 .. CTRL_O, "n", false)`.
  - **Repro:** open file → `gd` → press `<C-o>` → cursor doesn't return.

- [ ] **[BUG] `suggest_state.json` and `playbooks.json` written non-atomically** — `lua/user/suggest.lua:26-30`, `lua/user/playbooks.lua:28-32`
  - `io.open(path, "w")` truncates immediately. Crash mid-write → next session silently restores empty defaults (the `vim.json.decode` failure is swallowed by `load_state`'s `pcall`).
  - **Fix:** mirror `resume.lua:_save/_load` — write to `path .. ".tmp." .. pid`, then `os.rename`. On load failure, archive the broken file and toast.

- [ ] **[BUG] `yankring.json` write storm** — `lua/user/yankring.lua:17-21,28`
  - Every `y`/`d`/`c` triggers synchronous `io.open` + JSON encode of full ring on `TextYankPost`. Crash mid-write = empty ring. A 100-yank macro fsyncs 100 JSON encodes.
  - **Fix:** tmp+rename pattern + 500 ms debounce timer.

- [ ] **[BUG] `hints.lua` close-timer race closes the WRONG hint's window** — `lua/user/hints.lua:166-177`
  - `_show` tracks only `_current.timer` (fade); the fade callback creates a separate `close_timer`. If `_close_current()` runs explicitly between fade-fire and close-fire, the next hint becomes `_current` and the orphan timer dismisses it.
  - **Fix:** track both timers on `_current`, or check `_current == this_hint` inside the close callback.

- [ ] **[SEC+BUG+LUA] Blocking shell calls on the UI thread in interactive paths** — `lua/user/compass.lua:126-127, 137`; `lua/user/suggest.lua:38-40, 866-867`; `lua/user/commandeer.lua:95`; `lua/user/homunculus.lua:89`
  - `vim.fn.system("uptime"/"vm_stat"/"getconf")` in the compass HUD render path (~250 ms cadence) and `vim.fn.systemlist("git -C ... status --porcelain")` on every Suggest open. First hit on a dirty monorepo is 100-300 ms — defeats the "instant panel" feel CLAUDE.md flags as headline UX.
  - **Fix:** async — `vim.system({...}, { text = true }, function(o) cache.x = o.stdout end)` on a `uv.new_timer()` (2 s for compass). Suggest panel becomes eventually-consistent — first open shows cached state, refreshes async.

- [ ] **[DRY] Anthropic API call duplicated 4× verbatim** — `lua/user/{explain,ai_cmd,homunculus,dreams}.lua` (~200 LOC duplicated)
  - Same endpoint, env key check, curl arg vector, `anthropic-version: 2023-06-01` header, `parsed.content[1].text` extraction. API version bumps, streaming, prompt caching, retry/backoff = 4-file lockstep edits.
  - **Fix:** extract `lua/user/_claude.lua` exposing `claude.send{model, max_tokens, prompt, on_text, on_err}` + streaming variant for `explain`. Knock-on: makes default-model swaps (e.g. Sonnet 4.5) a one-line change.

- [ ] **[DRY] JSON read/write pattern reinvented in ~20 modules** — `suggest`, `playbooks`, `commandeer`, `yankring`, `macroreg`, `hints`, `projects`, `tabs`, `jira`, `confluence`, `resume`, `profiles` (file:line in agent report)
  - 20+ copies of `io.open → f:read("*a") → pcall(vim.json.decode) → close`. The `{luanil={object=true,array=true}}` flag is set in some, omitted in others — arrays vs objects round-trip differently across modules. Any atomic-write fix (above) has to be applied 20 times.
  - **Fix:** `lua/user/_jsonstore.lua` with `load(id) / save(id, data)`, paths resolved via `user.state.M.registry`. Subsumes the atomic-write fixes for suggest/playbooks/yankring above.

- [ ] **[DRY] State paths hardcoded in each module instead of via registry** — same module list as above plus cross-module re-hardcoding inside `suggest.lua:488,540,568,646`
  - `local STATE_FILE = vim.fn.stdpath("state").."/foo.json"` in each module while `state.lua:10-58` independently re-declares the same string. Suggest reaches across module boundaries and hardcodes `playbooks.json`/`macros.json`/`jira_cache.json` a third time. Rename = touch 2-3 sites per module.
  - **Fix:** `user.state.M.path_for(id)` becomes the single source of truth. Registry stops being write-only documentation.

- [ ] **[DRY] `suggest.lua` reaches into other modules' on-disk files instead of asking** — `lua/user/suggest.lua:488` (reads `playbooks.json`), `:540,546` (reads `macros.json`), `:646` (stats `jira_cache.json`), `:568,579` (scans workspaces dir)
  - Dependency-inversion violation: suggest knows the on-disk schema of 4 other modules. If `playbooks.lua` changes its layout, suggest silently breaks with no signal.
  - **Fix:** each module exposes a cheap `M.summary()`/`M.count()`; suggest calls those.

- [ ] **[DRY] Git plumbing duplicated and inconsistently quoted** — `suggest.lua:38,40,866,867`, `compass.lua:34-36`, `commandeer.lua:95`, `homunculus.lua:89`, `today.lua:13,185`, `checklist.lua:19-20`, `tabs.lua:832`, `resume.lua:47,158`, `jira.lua:356`, `starship.lua:323`
  - Two styles coexist: sync `shellescape`'d `systemlist` (suggest/compass/commandeer/homunculus) vs async list-form `vim.system` (resume/tabs/today/jira). `compass.lua:35` forgets to shellescape `cwd` — path-injection bug today.
  - **Fix:** `lua/user/_git.lua` — `is_repo / branch / toplevel / dirty_count / diff_files`, list-form `vim.system`, small TTL cache. Promotes `suggest._git_cache` (already half this).

- [ ] **[LUA] Highlights defined outside `brand.lua`** — `lua/plugins/ui.lua:27-36, 280-285`, `lua/user/welcome.lua:28`, `lua/user/cipher.lua:88`, ~20 sites total
  - Direct `nvim_set_hl` calls for chips/borders the design system already exposes. Breaks mode-reactive retint and the colorscheme-survival pattern in `brand._hook_mode_accent`. CLAUDE.md explicitly mandates centralization.
  - **Fix:** define Notify/WhichKey groups inside `brand.M.apply_hl` so `ColorScheme` re-applies them; delete per-site `set_hl` calls.

- [ ] **[LUA] Unguarded buffer autocmd in `seance.enable`** — `lua/user/seance.lua:84`
  - `CursorHold/CursorHoldI` registered with no `group`. Re-enable after wipe-and-reopen leaks the stale id.
  - **Fix:** `nvim_create_augroup("seance_buf_" .. bufnr, { clear = true })`.

---

## MEDIUM — latent bugs, defense-in-depth, future-proofing

- [ ] **[SEC] API keys passed as `curl` argv** — `lua/user/{ai_cmd:68, explain:73, dreams:76, homunculus:54}.lua` and Jira/Confluence Basic auth (`jira.lua:135-141`, `confluence.lua:89-103`)
  - Visible in `ps auxww` to any local user for the curl lifetime. Acceptable on single-user laptop, risky on shared boxes.
  - **Fix:** write header to `mkstemp` + `chmod 600` and pass `-H @file`, or stream via `-H "@-"` over stdin. Subsumed by the `_claude.lua` extraction above for the Anthropic ones.

- [ ] **[SEC] Homunculus auto-fires Anthropic egress on `VimLeavePre`** — `lua/user/homunculus.lua:131-141`
  - POSTs the day's full diff (potentially containing staged secrets) to `api.anthropic.com` silently on every nvim exit in a git repo. Throttled to once per 10 min — no opt-in prompt.
  - **Fix:** gate on `vim.g.homunculus_enabled` (default off); surface in README/tour with a security note.

- [ ] **[SEC] Webhook `/open` accepts arbitrary path** — `lua/user/webhook.lua:40-48`
  - Lower-risk than `/eval` but combined with `BufRead` autocmds (LSP, treesitter) becomes an attack vector if any plugin has a buffer-content exploit. Same auth fix as `/eval`.

- [ ] **[BUG] `seance` cache grows unboundedly** — `lua/user/seance.lua:7, 23-26`
  - One entry per (bufnr,line) visited. No cap, no LRU, no `BufWipeout` cleanup.
  - **Fix:** ~2000-entry FIFO + `BufWipeout` autocmd to strip wiped bufnr entries.

- [ ] **[BUG] Debounced-save timer field leaks on `:close()` failure** — `lua/user/commandeer.lua:49-57`, `lua/user/tabs.lua:976-983`
  - If `_dirty_timer:close()` raises (handle already closed), the field never clears → subsequent saves silently never schedule.
  - **Fix:** `pcall` the clear AND always null out the field in a finally-style.

- [ ] **[BUG] `tabs.lua` closed-stack trim assumes ordering** — `lua/user/tabs.lua:1005-1010`
  - `while #_closed_stack > CLOSED_MAX do table.remove(_closed_stack) end` pops the LAST element — fine today because saves use `table.insert(snap, 1, ...)`, but one regression in push order silently destroys the most recent close.
  - **Fix:** `table.remove(_closed_stack, #_closed_stack)` explicit + assert/document the invariant.

- [ ] **[BUG] `recall.lua` cwd restore uses `tcd` regardless of original scope** — `lua/user/recall.lua:89`
  - If original change was `:lcd` or `:cd`, `tcd` changes a different scope on restore.
  - **Fix:** record `vim.fn.haslocaldir()` at push; dispatch to `cd`/`tcd`/`lcd` at pop.

- [ ] **[DRY] `find_project_root` is private to `suggest.lua`** — `lua/user/suggest.lua:687-696`
  - 8-deep parent walk for `.git`/`.suggest.lua`. Every other module reimplements via `git rev-parse --show-toplevel` — the two answers disagree for non-git projects with `.suggest.lua`. `projects.lua:172`, `resume.lua:47` silently use different definitions of "project".
  - **Fix:** move into the `_git.lua` or new `_project.lua` from the High-severity fix above.

- [ ] **[DRY] Float-window construction split between `brand.win` and raw `nvim_open_win`** — ~25 sites bypass `brand.win` (full list in agent report; notable: `welcome`, `cipher`, `toast`, `ai_cmd`, `dreams`, `compass`, `quill`, `rift`, `tabs`, `today`, `checklist`, `blackbox`, `rextest`, `hints`, `radar`, `throttle`, `present`, `jobs`, `perfhud`, `confluence`, `jira`, `constellation`, `tsplay`)
  - CLAUDE.md explicitly says "prefer `user.brand.win(opts)`" — new floats miss curtain animation and mode-reactive retinting. The "six surfaces in lockstep" promise is silently broken for every raw-window panel.
  - **Fix:** audit each call. Simple ones (`today`, `checklist`, `blackbox`, `quill`) → straight conversion. Complex panels needing extra control → extend `brand.win` with the missing knobs rather than carving exceptions.

- [ ] **[DRY] Inconsistent notify wrappers** — bare `vim.notify` in ~6 modules vs `brand.notify` in ~70+
  - `ai_cmd`, `explain`, `homunculus`, `today` paths, `smartpaste`, `webhook`, `checklist`, `welcome` use bare notify. No technical reason — they predate the branded notifier.
  - **Fix:** mechanical migration. Add `brand.notify_error / .notify_warn` shorthands while there to kill `vim.log.levels.X` boilerplate.

- [ ] **[LUA] Unguarded autocmd in `constellation.open`** — `lua/user/constellation.lua:141`
  - `CursorMoved` autocmd with no group, attached on every open. Mostly self-cleaning via `bufhidden="wipe"`, but if buffer survives (`:hide`) handler leaks.
  - **Fix:** `group = nvim_create_augroup("user_constellation_" .. state.buf, { clear = true })`.

- [ ] **[LUA] `vim.fn.system` synchronous pipes in `smartpaste`** — `lua/user/smartpaste.lua:46, 52`
  - **Fix:** `vim.system({"jq","."}, { stdin = s, text = true }, function(o) vim.schedule(...) end)`.

- [ ] **[LUA] `pcall` in toast overseer hooks swallows errors silently** — `lua/user/toast.lua:159-176, 179-194`
  - **Fix:** `local ok, err = pcall(...)` and `vim.notify(..., vim.log.levels.DEBUG)` on failure.

- [ ] **[LUA] `hl_cache` lookup uses O(n) `vim.tbl_count` per new key** — `lua/user/starship.lua:925-936`
  - **Fix:** maintain an integer counter alongside the cache.

- [ ] **[BUG] `resume.lua` Probe-2 `git diff HEAD~N..HEAD` errors on shallow repos** — `lua/user/resume.lua:376-386`
  - If N exceeds shallow depth, error silently captured into `diff_out=nil`. Brief loses signal.
  - **Fix:** check `git rev-parse HEAD~N` first, or fall back to diff against merge-base.

---

## LOW — nits, style, future cleanup

- [ ] **[DRY] `suggest.lua` is 1342 LOC doing 4 jobs** — split into `suggest/{init,state,context,rank,ui,actions}.lua`. No behavior change; clearer change-amplification surface.
- [ ] **[DRY] `cockpit.lua:44-71` hardcodes every panel name** in open/close — tiny `local PANELS = {...}` + iterate, or `cockpit.register(name, opener, closer)` API.
- [ ] **[DRY] `pcall(function() require("user.brand").notify(...) end)` boilerplate** — `commandeer.lua:325,331,339`, `tour.lua:248,259`, `state.lua:140,151,155,191,198,201,208,219,221`, `playbooks.lua:186,208,403`. Brand is in setup phase 1, can't be missing. Drop the `pcall`, cache `local brand = require("user.brand")` at module top.
- [ ] **[BUG] `perfhud.lua:116-125` monkeypatches `vim.lsp.buf_request_all` and never unhooks.** Harmless today; double-wraps if `state` is ever reset.
- [ ] **[BUG] `welcome.lua:82-87` defers `keymap.set` 800 ms after sweep.** If buf wiped in the gap, user has no way to dismiss. Bind dismiss keys synchronously at open.
- [ ] **[BUG] `ai_cmd.lua:65-91` uses both `text=true` and stdout/stderr callbacks.** Redundant; pick one.
- [ ] **[BUG] `suggest.lua:23` `vim.tbl_deep_extend("force", state, parsed)`** accumulates ghost keys in `state.sequences` across forget+restart cycles. Probably benign; worth a comment.
- [ ] **[LUA] `treesitter.lua:8` and `extras.lua:7` load eagerly.** Treesitter could be `event = { "BufReadPost", "BufNewFile" }` to defer `get_installed` shell-out. (Verify main-branch idiom first.)
- [ ] **[LUA] `brand.lua:232` `nvim_strwidth(text or "")` everywhere `right_pad` is called.** Drop the `or ""`.
- [ ] **[LUA] `tabs.lua:1362-1364` `BufEnter`/`BufModifiedSet` redrawtabline fires far more than needed.** Debounce with `vim.uv.now()` gate (same pattern as `hints.lua:227-230`).
- [ ] **[SEC] `state.lua:162` runs `vim.fn.system({"jq", "."}, raw)` over state file contents.** Array-form so safe; flagged only as informational.
- [ ] **[SEC] No global `exrc`/`secure` setting in `core/options.lua`** — good; the two `dofile` sites above are the only project-local code-execution paths.

---

## Suggested fix order (highest-leverage first)

1. **Critical SEC × 3** — `.suggest.lua` trust prompt → `.preflight.lua` trust prompt → webhook token mandatory + drop `/eval`. Half a day. **Blocks safe use on shared machines or with untrusted repos.**
2. **`_jsonstore.lua` extraction** — fixes ~20 modules' atomic-write gap (suggest/playbooks/yankring HIGH bugs) + 200 LOC of duplication in one stroke. Half a day.
3. **`_claude.lua` extraction** — 4-file dedup, makes API-key-out-of-argv fix a one-line change. ~2 hours.
4. **`_git.lua` extraction** — async-ifies compass/suggest/commandeer/homunculus blocking paths AND closes `compass.lua:35`'s missing shellescape. Half a day.
5. **`jumppulse.lua` termcode fix** — 5 minutes, restores `<C-o>`/`<C-i>`.
6. **`brand.notify` migration + highlight centralization** — mechanical, restores the "six surfaces in lockstep" guarantee from CLAUDE.md. ~2 hours.
7. **Medium-severity bug sweep** — seance unbounded cache, debounce-timer leaks, tabs trim invariant, recall cwd scope. ~3 hours.
8. **Low/nit polish** — pick at leisure.

Steps 2-4 are the architectural leverage points: each one collapses multiple HIGH findings into a single fix.
