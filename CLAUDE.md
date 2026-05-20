# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A personal Neovim distribution (nvim 0.12+) built on `lazy.nvim` with ~30 plugin specs and ~45 hand-rolled native Lua modules under `lua/user/`. There is no build step, no test suite, no package manifest. Changes are validated by launching Neovim and observing behavior.

## Commands

```bash
./scripts/doctor.sh issues       # primary health check — runs nvim headless,
                                 # captures :checkhealth + :messages, surfaces
                                 # only errors+warns. Exit code = # of errors.
./scripts/doctor.sh stats        # plugin count + startup ms
./scripts/doctor.sh section <x>  # one plugin's :checkhealth section
./scripts/doctor.sh full         # entire report
./install.sh --dry-run           # show what install would do without running
```

Inside nvim, the equivalents of "run the test suite" are `:Lazy` (plugin states), `:Mason` (LSP/tool states), and `:checkhealth`.

## Architecture

### Load order

`init.lua` requires, in this order: `core.options` → `core.keymaps` → `core.autocmds` → `core.lazy`. Leader is set in `options.lua` (must run before lazy so plugin keymaps register against the right leader).

### Two parallel module systems

1. **`lua/plugins/*.lua`** — one file per `lazy.nvim` plugin spec group (`lsp.lua`, `git.lua`, `lang-python.lua`, …). Lazy discovers them via `{ import = "plugins" }` in `core/lazy.lua`. Defaults: `lazy = true, version = false`.

2. **`lua/user/*.lua`** — first-party native Lua modules. They are NOT individual lazy specs. They're all loaded by a single pseudo-spec at `lua/plugins/user-modules.lua`, which calls each module's `.setup()` from inside one `config` function (eager, `priority = 100`). Keymaps for user modules live on that pseudo-spec's `keys = {...}` array.

   **To add a new user module:** create `lua/user/foo.lua` exporting `M.setup()`, add a `require("user.foo").setup()` line in the correct phase of `user-modules.lua`, then add any `<leader>` keymaps to the same file's `keys` table. Don't make user modules into separate lazy specs.

### Setup phases inside `user-modules.lua` (order matters)

1. **Design system** — `brand` → `curtain` → `welcome`. Must run first; everything else pulls colors/window builders from `user.brand`.
2. **Entry points** — `suggest`, `commandeer`, `playbooks`, `tour`, `state`.
3. **Daily-driver tools** — `yankring`, `jobs`, `spotlight`, `explain`, etc.
4. **Cockpit** — `compass`, `radar`, `throttle`, `cockpit`, `starship` (statusline lives here, not in plugin land).
5. **Niche** — `dreams`, `rift`, `seance`, `homunculus`, …
6. **Novelty** — `require("user._play").setup()` (lazy entry, opens `:Play` picker).

### Shared design vocabulary

Three coupled facts that any visual change has to respect:

- **One accent** — `user.brand.M.c.accent` (`#cba6f7`) threads through every float, border, prompt, chip. Change it once, the whole UI retunes.
- **Chip highlight groups** — `BrandChipAccent` / `Surface` / `Ok` / `Warn` / `Err` / `Info` are defined once in `user.brand` and used by every persistent panel (Suggest, Playbooks, Compass, diagnostic gutter). Don't define one-off chip highlights; reuse these.
- **Mode-reactive accent** — a single `ModeChanged` autocmd in `user.starship._hook_mode_accent` retints six surfaces in lockstep (statusline mode capsule, bufferline tab underline, compass HUD chip, cursor block/beam, line number via modicator, popup borders). When you add a new floating UI, either let it inherit the default `FloatBorder` (so it retunes) or set its own `winhighlight` (so it stays static). Don't half-do it.

### Suggest / Playbooks data flow (the headline feature)

- `<Space><Space>` opens `user.suggest` — context-ranked action panel that learns from picks. State at `~/.local/state/nvim/suggest_state.json`. Three signals: recency, context-match (project-scoped fingerprint), sequence (cross-action transitions, global).
- Actions live in the `ACTIONS` table in `lua/user/suggest.lua`. Each entry: `{ id, when(ctx)→priority|nil, label(ctx)→str, run(ctx) }`. Per-project actions can be added via a `.suggest.lua` at any project root.
- `user.playbooks` reads the sequence graph from suggest's state; chains of ≥3 repetitions become discovered playbooks. Names + F-key pins persist at `~/.local/state/nvim/playbooks.json`.
- Self-aware suggestions: suggest knows about other user.* modules (tour, journal, macros, cockpit, state) and surfaces them by introspecting their state. When adding a new user.* module that has its own state file or surface, consider whether suggest should know about it.

### Persistent state inventory

`:UserState` is the source of truth — it lists every state file under `~/.local/state/nvim/` with size, age, and description. `user.state.M.registry` is where new entries get registered. If your new module persists anything, register it there so `:UserStateClear` / `Export` / `Import` know about it.

### Statusline coupling

`user.starship` is both the lualine config AND the source of `_mode_defs` and color palette `c` that `user.compass` and several other surfaces pull from by reference. Don't fork the mode-color table; import it.

## Conventions worth knowing

- **`lazy = true` by default** — plugin specs should declare their own load triggers (`event`, `keys`, `cmd`, `ft`). The user-modules pseudo-spec is the deliberate exception (`lazy = false, priority = 100`).
- **Statusline `%` escaping** — any text rendered through lualine chains must escape literal `%` to `%%` (see `user.starship.chain`) or it crashes with `E539`.
- **Borders** — `winborder = "rounded"` is set globally. Prefer `user.brand.win(opts)` over raw `nvim_open_win` so new floats inherit the curtain animation.
- **Catppuccin lualine theme** — must be the full name `catppuccin-mocha`, not bare `catppuccin`. Bare name crashes lualine.
- **Deprecation warnings** — `core/options.lua` silences specific upstream-plugin deprecations (`vim.highlight`, `vim.validate`, etc.). If a new noisy deprecation appears from a plugin awaiting upstream fix, add its prefix to `muted_prefixes` there rather than disabling the warning system.

## Where things live (just the non-obvious bits)

```
init.lua                   entry point, 5 lines
lua/core/                  options · keymaps · autocmds · lazy bootstrap
lua/plugins/               30 lazy specs
  user-modules.lua         loads ALL of lua/user/*; owns user-module keymaps
lua/user/                  ~45 first-party modules (one feature each)
lua/user/_play/            8 novelty toys behind :Play picker
scripts/doctor.sh          headless healthcheck (use this, not :checkhealth)
```

`README.md` is the user-facing manual and is comprehensive — consult it for feature/keymap reference rather than reverse-engineering from code.
