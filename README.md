<div align="center">

```
███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝
```

### a banger of a config — the kind that replaces VSCode and then some

`113 plugins` · `30 plugin specs` · `45 native modules + 8 toys` · `nvim 0.12+` · `lazy.nvim` · `catppuccin mocha`

</div>

---

## What this is

A complete Neovim distro tuned to be your **single home in the terminal**. Native LSP for 15+ languages. Two AI surfaces (Copilot inline + Avante chat with Claude). Full git workflow with Magit-style commits, PR review, time-travel, line-by-line blame whispers. Database client, REST client, Kubernetes panel, Jupyter notebooks, Obsidian-style second brain. All running on nvim 0.12 with the modern `vim.lsp.config` API and the maintained `nvim-treesitter` main branch.

On top of that, a **design system** (`lua/user/brand` + `curtain` + `welcome`) and **50+ hand-rolled native modules** that turn the editor into something more like a cockpit than a text widget. The whole UI is **mode-reactive**: a single per-mode color (blue NORMAL · green INSERT · mauve VISUAL · red REPLACE · peach COMMAND · teal TERMINAL) drives six surfaces in lockstep — statusline mode capsule, bufferline tab underline, compass HUD chip, cursor block/beam, line number (via modicator), and popup borders (LSP hover/signature, completion menu, telescope). Change mode and six things retune at once.

A shared **chip vocabulary** (`BrandChipAccent` / `BrandChipSurface` / `BrandChipOk` / `BrandChipWarn` / `BrandChipErr` / `BrandChipInfo`, defined once in `user.brand`) renders the colored capsules you see across every persistent panel: the digit + learned + project chips in the **Suggest** panel, the digit + pin chips in the **Playbooks** panel, the per-row chips in the **Compass HUD**, and the severity chips in the **diagnostic gutter**. One source of truth for color → behavior; change the token, every panel updates.

Three of those modules — **`suggest`**, **`commandeer`**, and **`playbooks`** — are the headline:

- **`<Space><Space>`** opens a context-aware action panel. Ranks 4-6 suggestions by what's actually relevant right now (errors, modified buffers, git state, filetype, time of day). Stays open as you work and re-ranks live as state changes. Learns from your picks — actions you take in a given context get a bonus the next time that context appears, and two-action sequences ("fix → commit") build a learned chain. Project-scoped: a `.suggest.lua` in any repo adds project-specific actions.
- **`<leader>`** (with the which-key timeout) shows only context-relevant bindings. In a non-git file you don't see git keymaps. In a Python file you see REPL keys. In a markdown file you see preview/present. **`<leader>?`** escapes to the full reference.
- **`:Playbooks`** turns learned sequences into named, pinnable chains. If you've done `fix → save → commit` three times, that's a playbook. Name it, pin to `<F2>`, fire the whole chain with one key.

First launch plays a quiet welcome ritual; **`:Tour`** is a 7-slide guided walkthrough you can take any time.

If VSCode does it, this does it — faster, in your terminal, on your keymaps. And then it keeps going.

---

## Table of contents

1. [Install — one shot](#install--one-shot)
2. [After install](#after-install)
3. [What Mason handles for you](#what-mason-handles-for-you-no-brew-needed)
4. [Per-feature setup](#per-feature-setup)
5. [Verifying you're set up](#verifying-youre-set-up)
6. [The headlines: Suggest, Commandeer, Playbooks, Tour](#the-headlines--suggest--commandeer--playbooks--tour)
7. [Feature highlights](#feature-highlights)
8. [VSCode parity table](#vscode-parity-table)
9. [First-class languages](#first-class-languages)
10. [Workflows — a day in the life](#workflows--a-day-in-the-life)
11. [Native Lua modules (`lua/user/`)](#native-lua-modules-luauser)
12. [Diagnostic tool — `doctor.sh`](#diagnostic-tool--doctorsh)
13. [Keymap reference](#keymap-reference)
14. [The status bar](#the-status-bar)
15. [The compass HUD](#the-compass-hud)
16. [Recently shipped](#recently-shipped)
17. [Layout / where things live](#layout--where-things-live)
18. [Customization](#customization)
19. [Troubleshooting](#troubleshooting)

---

## Install — one shot

The fastest way: clone this config and run `install.sh`. Works on **macOS** (Homebrew, installed if missing) and **Ubuntu/Debian/Pop/Mint LTS** (apt + GitHub-release fallbacks).

```bash
git clone <this-repo> ~/.config/nvim
cd ~/.config/nvim
./install.sh
```

The script: detects OS → installs package manager if missing → installs required CLIs → recommended CLIs → prompts per language (python/go/rust/docker) → optional extras (Ghostty, Quarto+Jupyter, glow) → backs up any existing `~/.config/nvim` → runs `:Lazy! sync` + compiles every Treesitter parser + installs every Mason tool → verifies + prints next steps.

| Flag | Purpose |
|---|---|
| `--yes` / `-y`     | Accept every prompt, fully unattended |
| `--minimal`        | Required tools only |
| `--skip-system`    | Only re-bootstrap plugins |
| `--skip-bootstrap` | Only install OS deps |
| `--dry-run`        | Print what would run, no execution |

### Manual brew block (macOS)

```bash
brew install neovim ripgrep fd tree-sitter tree-sitter-cli git node jq \
             lazygit pngpaste yazi gh ghostscript
brew install --cask font-jetbrains-mono-nerd-font ghostty
brew install python go rustup && rustup-init -y
brew install --cask docker
brew install quarto glow
pip install --user pynvim jupyter_client cairosvg pnglatex plotly kaleido pyperclip nbformat
```

## After install

```bash
nvim                      # lazy.nvim bootstraps + installs every plugin (~60s)

# inside nvim:
:Mason                    # auto-installs LSPs/formatters/linters/DAP adapters
:checkhealth              # confirm everything is green

# auth:
:Copilot auth             # GitHub Copilot
gh auth login             # Octo (PRs/issues from your shell)

# Avante (Claude) — add to ~/.zshrc:
export ANTHROPIC_API_KEY=sk-ant-...
```

## What Mason handles for you (no brew needed)

| Category | Tools |
|---|---|
| **LSPs**       | `lua_ls` · `pyright` · `ruff` · `vtsls` · `eslint` · `gopls` · `bashls` · `jsonls` · `yamlls` · `marksman` · `taplo` · `dockerls` · `emmet_language_server` · `tailwindcss` · `ltex` |
| **Formatters** | `stylua` · `shfmt` · `prettierd` · `black` · `isort` · `goimports` |
| **Linters**    | `shellcheck` · `hadolint` · `markdownlint` |
| **DAP**        | `debugpy` · `codelldb` · `delve` · `js-debug-adapter` |

*Rust's `rust_analyzer` is installed by `rustaceanvim`, not Mason.*

## Per-feature setup

| Feature | Setup beyond brew |
|---|---|
| Copilot | `:Copilot auth` |
| Avante (Claude) | `export ANTHROPIC_API_KEY=...` |
| Octo + gh-actions | `gh auth login` |
| Lazygit, Yazi, pngpaste | in brew block |
| Inline images in markdown | Ghostty + Snacks.image (built-in) |
| Markdown preview (`<leader>mp`) | needs `node`, builds itself on first launch |
| Live server | auto-installs `live-server` via npm |
| Database UI (`<leader>D`) | nothing extra; add connections via `:DBUIAddConnection` |
| REST client | open any `.http` file — done |
| Devcontainers (`<leader>C*`) | Docker Desktop or compatible runtime |
| Jupyter / Quarto | optional pip block; plugins stay dormant until installed |
| Obsidian (`<leader>n*`) | nothing — `~/notes/{inbox,daily,assets}` auto-created |
| cheat.sh (`<leader>?h`) | internet |
| devdocs (`<leader>?d`) | `glow` + `:DevdocsFetch <slug>` |
| User AI modules (`:AI`, `:Explain`, `:Dreams`, `:Homunculus*`) | `ANTHROPIC_API_KEY` |
| `:Cipher` (encrypted scratchpad) | `openssl` (preinstalled on macOS) |

## Verifying you're set up

```vim
:checkhealth              " everything green except optional items you skipped
:Lazy                     " all plugins should show ● not ⏳
:Mason                    " LSPs/tools should all show ◍ (installed)
```

And the better way:
```bash
./scripts/doctor.sh           # actionable issues only (curated noise filter)
```

---

## The headlines — Suggest · Commandeer · Playbooks · Tour

These set this config apart. Read these even if you skip everything else.

### `<Space><Space>` — `:Suggest`

A reactive contextual action panel. **Opens as a floating card**, **stays open** while you work, **re-ranks live** as context changes, and **learns** from your picks across sessions.

```
    1  ●  fix · Undefined name 'foo' in line 23
    2     save this buffer
    3     run nearest test
    4  ●  open python repl
    5     ask AI about this code
    6     spotlight (everything)

    ────────────────────────────────────────────
    server.py  ·  python  ·  3 dirty  ·  1 err

    ● = learned in this context     ? = show all     q = close
```

Each number key fires its action. The **`●` marker** means *you've picked this action before in this kind of situation*. The subtitle shows the current "fingerprint" (filename + filetype + git state + error count) so you can see *why* the panel is suggesting what it is.

**Reactivity**: a private autocmd group listens to `DiagnosticChanged`, `BufWritePost`, `BufEnter`, `BufModifiedSet`, `InsertLeave`, `LspAttach`, `FocusGained`. On any of those, a 220ms-debounced re-rank fires. Fix an error → the "fix" suggestion drops away, "commit" climbs.

**Learning**: every pick is stored at `~/.local/state/nvim/suggest_state.json` with three signals:
- **Recency** — used in the last hour gets +10, decays linearly
- **Context-match** — historically picked in *this exact fingerprint* (`E:M:D:python:3` = errors, modified, dirty git, python, afternoon) gets `min(20, count × 4)`
- **Sequence** — if you picked an action in the last 2 minutes, actions that historically followed it get `min(18, count × 3)`

So `fix → save → commit` really does become a learned chain.

```vim
:SuggestStats     " see what it's learned
:SuggestForget    " wipe and start fresh
```

#### Self-aware actions

Suggest knows about the rest of the user.* modules and surfaces them at the right moments — not as menu items, as context-relevant suggestions:

| When | Surfaces | Priority |
|---|---|---|
| `.toured` marker missing **and** buffer empty (likely fresh launch) | "take the 2-min tour" | 90 |
| Strong unnamed sequence chains exist (≥5 strength, not yet named) | "name your top playbook" | 40 |
| ≥3 sequences observed | "browse learned playbooks" | 26 |
| Today's journal `~/notes/journal/<today>.md` exists | "open today's journal" | 30 |
| Yesterday's exists but today's doesn't | "open yesterday's journal entry" | 16 |
| Saved macros count > 0 | "run a saved macro · N available" (live count) | 20 |
| Cockpit not currently engaged | "engage cockpit (full HUD layout)" | 16 |
| Total state files > 50MB | "review user state · NMB total" (live size) | 24 |
| Always (low-priority safety) | "run a quick shell command" | 14 |

These run alongside the standard 29 actions (errors, git, language tools, navigation). The catalog is **38 actions** plus per-project `.suggest.lua` overrides.

So `<Space><Space>` on a brand-new install with no buffers shows:

```
    1     take the 2-min tour
    2     restore last session here   (if a snapshot exists)
    3     find a file
    4     grep the project
```

And after a week of use at 6pm in a python project with errors:

```
    1  ●  fix · NoneType has no attribute foo
    2     write today's journal entry
    3     name your top playbook (you have strong unnamed chains)
    4     save this buffer
    5     run nearest test
    6     commit · 2 files changed
```

Single keystroke, whole-system awareness.

#### Per-project actions via `.suggest.lua`

Drop a file at any project root and Suggest merges its actions into the panel for that project only:

```lua
-- .suggest.lua
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
}
```

Each entry is `{ id, when(ctx)→priority|nil, label(ctx)→str, run(ctx) }`. Auto-reloaded on mtime change or `DirChanged`. IDs are namespaced internally (`proj.deploy`). Project actions show with a `▸` marker in the panel and get a +5 visibility nudge.

```vim
:SuggestProject        " inspect what's loaded
:SuggestProjectEdit    " open or scaffold .suggest.lua
:SuggestProjectReload  " force re-read
```

Learning is **project-scoped** — the fingerprint includes the project root name, so a `fix → commit` sequence in repo A doesn't bleed into repo B's suggestions. Sequences (cross-action transitions) stay global because patterns like `fix→save→commit` are universal.

### `<leader>` (with which-key timeout) — `user.commandeer`

The which-key popup is now context-filtered. Instead of dumping 80+ bindings on you, it shows only the ones relevant to right now.

- In a non-git buffer: no `<leader>g*` (Neogit, git-conflict, time-travel)
- In a non-Python file: no `<leader>r*` (REPL)
- In a non-markdown file: no `<leader>P` (Present)
- Without diagnostics: no `<leader>x*` (Trouble)
- Without a Makefile/Cargo.toml/etc.: no `<leader>T*` (tasks)

**`<leader>?`** opens the full unfiltered reference any time. **`:CommandeerToggle`** flips a session-level "show all" flag.

**Adaptive learning:** every `<leader>?` escape is observed. The next leader keystroke tells Commandeer what you were *actually* looking for. If you escape ≥3 times in a filetype to reach the same namespace (say `<leader>r*` in a non-Python file), that namespace gets quietly loosened — it stays visible in that filetype going forward. A toast tells you when it happens. `:CommandeerStats` shows what's learned; `:CommandeerReset` wipes it.

### `:Playbooks` — `user.playbooks`

Suggest tracks pairwise sequences (`after X you picked Y` with a count). After three repetitions of a chain, it surfaces in `:Playbooks` (also `<leader>up`) as a discovered playbook. Chip-styled two-row layout per item — same design vocabulary as the suggest panel and compass:

```
   1   F2   morning routine                 ×7   ← chip row: digit (top=accent, others=surface) + pin (ok-green when pinned) + name (top=bold accent) + strength
        fix_error  →  save  →  commit            ← chain row, dimmed via BrandSubtext
   2   F3   ship-it                          ×6
        format_buffer  →  save  →  run_test
   3        —                                ×4
        spotlight  →  swap_other
   4        —                                ×3
        grep  →  open_file

   ──────────────────────────────────────────────────────────────────────
   [n] name   [p] pin to F-key   [u] unpin   [d] delete    [q] close
```

- **Discovery**: walks the sequence graph from each action's strongest follower (≥3 occurrences), chains up to 5 deep, suppresses sub-chains of longer ones
- **Names** + **pins** persist to `~/.local/state/nvim/playbooks.json`
- **Pinning**: pick `<F2>`/`<F3>`/`<F4>`/`<F5>`. The key fires the whole chain — each step runs with a 250ms delay so autocmds/UI events propagate between actions
- **`d`** hides a chain; **`:PlaybookForget`** un-hides all
- **`:PlaybookRun <name>`** to fire by name from anywhere

**Live progress toast** when a chain fires — a single replacing notification at the top tracks the chain:

```
✦  morning routine          [◐ ○ ○ ○]  fix_error     ← step 1 starts (pinned)
✦  morning routine          [● ◐ ○ ○]  save          ← step 2 starts
✦  morning routine          [● ● ◐ ○]  run_test      ← step 3 starts
✓  morning routine          [● ● ● ●]  4 steps       ← done (2.2s fade)
```

`●` done · `◐` current · `○` pending · `✗` failed (longer timeout so you can read the error). One toast handle that mutates via nvim-notify's `replace` semantics — never piles up.

Emergent behavior, named and operationalized.

### `:Tour` — `user.tour`

7-slide guided walkthrough of the headlines. Brand-styled card with progress dots and slide counter. `n`/`<Space>`/`<Right>` next, `p`/`<Left>` back, `q`/`<Esc>` finish.

First nvim launch surfaces a single notification offering it; `:TourReset` resets the marker if you want it offered again.

### How they relate

- `<Space><Space>` is the *thinking* surface — "here's what makes sense right now."
- `<leader>` is the *doing* surface — "I know what I want to press, just show me my namespace."
- `:Playbooks` is the *automating* surface — "I do this all the time, give me one key."
- `:Tour` is the *learning* surface — for the first time you (or a new user) sit down.

You'll use them in that order over weeks. `<leader>` is muscle memory. `<Space><Space>` is when you're not sure. `:Playbooks` after a month, when patterns have emerged. `:Tour` once, ever, unless you reset it.

---

## Feature highlights

### Editor essentials
- **LSP** with inlay hints, document highlight, signature help, code actions, rename, format-on-save (`conform.nvim`)
- **Treesitter** (main branch) with context-sticky headers, textobjects, rainbow delimiters, auto-tag
- **Completion** via `blink.cmp` — LSP + path + buffer + snippets + Copilot, ghost text inline
- **Snippets** via LuaSnip + friendly-snippets
- **Linting** via `nvim-lint` (shellcheck, hadolint, markdownlint)

### `user.resume` — task intent across interruptions
`<leader>Kc` captures the current task (objective, next step, what to verify first, freeform notes). `<leader>Kr` opens the **Resume Brief** — a four-section panel showing what you were doing, what changed in the repo while you were away (commits, file churn, branch divergence) via async `vim.system` probes, and any open threads. `<leader>Kl` lists paused tasks across all projects; `<leader>Kx` resolves the current project's task.

State is project-keyed (git toplevel) and stored at `~/.local/state/nvim/resume_tasks.json`. Switching directories auto-pauses the outgoing task; returning to a project with a paused task surfaces a subtle virtual-text hint on the next BufEnter — no modal prompts, no toasts during steady-state work.

Inspired by [vscode-tacos](https://github.com/jkordish/vscode-tacos); adapted to nvim and scoped to the genuine novelty. Design grounded in Calm Tech (Weiser & Brown 1995) — zero prompts during a focused hour; information surfaces only on natural transition points (DirChanged, FocusGained, BufEnter after pause).

### AI
- **Copilot** ghost text completions (`<M-l>` accept, `<M-]/[>` cycle)
- **Avante** Cursor-style chat agent powered by Claude Sonnet 4.6 (`<leader>aT` toggle, needs `ANTHROPIC_API_KEY`)
- **`:AI <intent>`** direct one-shot Anthropic call from cmdline
- **`:Explain`** streaming Anthropic explanation of the diagnostic under cursor — token-by-token virt_lines
- **`:HomunculusWake`** AI agent that summarizes today's git diff into a daily journal file

### Navigation
- **Telescope** (fuzzy files, grep, symbols, marks, registers, git) as the single primary picker
- **Neo-tree** (`<leader>e`), **Oil** (`-`), **Yazi** (`:Yazi`) — three explorer styles for different moods
- **Flash** (`s`/`S`) for jump-anywhere
- **Harpoon 2** (`<leader>1-4`) for pinned files
- **Spotlight** (`<C-S-Space>` / `<leader>uS`) — unified picker across files+buffers+marks+jumps+diagnostics+commands+AI
- **Smart-splits** (`<A-h/j/k/l>`) that cross tmux & wezterm panes

### Git (full Magit-class workflow)
- **Neogit** — magit-style staging/commit/rebase/log (`<leader>gn`) — the single primary git UI
- **Lazygit** floating via toggleterm (`<leader>gG`)
- **Diffview** (`<leader>gV`) for file-history
- **Gitsigns** with inline hunk preview, blame, stage from buffer
- **git-conflict** for inline merge resolution (`<leader>gxo/gxt/gxb`)
- **gh-actions** panel for CI runs (`<leader>gA`)
- **Octo** for full PR/issue review (`<leader>Op`)
- **`:TimeTravel`** scrub the current file across every commit that touched it with `←/→`

### Per-language premium
- **Rust** — `rustaceanvim`: macro expansion, runnables, debuggables, codelldb DAP; `crates.nvim` for Cargo.toml versions
- **Go** — `go.nvim`: struct tags, GoImpl, fill struct, fill switch, if-err; `nvim-dap-go` via delve
- **Python** — `venv-selector.nvim` auto-detects venvs/poetry/conda; `nvim-dap-python` via debugpy; `neotest-python`
- **TypeScript** — `vtsls` + `eslint`, **Emmet** + **TailwindCSS** LSP auto-attach in JSX/TSX/Vue/Svelte/Astro

### Real apps living in nvim
- **Database client** — vim-dadbod-ui (`<leader>D`) — Postgres/MySQL/SQLite/BigQuery side panel
- **REST client** — kulala (`<leader>Rs`) — `.http` files, response in split
- **Kubernetes** — kubectl.nvim (`<leader>k`) — Lens-style pods/logs/exec. First open compiles the bundled Rust client (`make build` via lazy's `build` hook); needs Go + Cargo on PATH
- **Jupyter** — Quarto + Molten with cell execution and inline plot rendering (opt-in)
- **Obsidian** — full second-brain (`<leader>nn`, `nt`, `nb`, `ng`)
- **Pomodoro** — `<leader>np1/2/3`, countdown shows in statusline
- **Devcontainers** — VSCode Remote Containers parity (`<leader>Du`)
- **Markdown preview** in browser with synced scroll
- **Live server** for HTML/CSS/JS dev

### Refactoring & code intelligence
- **refactoring.nvim** — extract function/variable/block, inline, debug print injection
- **Multicursors** — Sublime-style (`<leader>m`, `<up>`/`<down>` add cursor)
- **Neogen** — generate docstrings (Google/rustdoc/godoc/JSDoc/TSDoc/ldoc)
- **Aerial** outline (`<leader>cO`), **Dropbar** winbar breadcrumbs (`<leader>cp`)
- **Glance** (`gpd`/`gpr`/`gpt`/`gpi`) for beautiful peek windows

### Tests & debug
- **Neotest** (`<leader>tn/td/ts`) for python/go/rust with inline status
- **DAP + DAP-UI** with codelldb/debugpy/delve/js-debug-adapter
- **Overseer** task runner — VSCode `tasks.json` equivalent (`<leader>Tt`)

### Writing & docs
- **render-markdown** for live in-editor rendering
- **markdown-preview** for browser-based synced preview
- **ltex-ls** for grammar/spell on markdown/tex/text/gitcommit
- **img-clip** to paste clipboard screenshots into markdown (`<leader>cP`)

### Visual polish
- **Catppuccin Mocha** with full plugin theming integration
- **Single accent color** (`#cba6f7` lavender) threaded through every float, border, prompt, key chip
- **noice** for cmdline + UI · **nvim-notify** stacking notifications · **fidget** LSP progress
- **tiny-inline-diagnostic** floating diagnostic near cursor
- **incline** floating filename + LSP + diagnostic + line-count badge in each window
- **smear-cursor** silky animated cursor · **modicator** mode-colored line numbers
- **nvim-scrollbar** with diagnostic + git markers
- **Snacks** (folke) — bigfile, animated scroll, statuscolumn, zen mode, scratch buffer
- **Twilight** dim non-focused code
- **Curtain** (custom) — every float opens/closes with a 140ms ease-out expansion

### Lookups
- **cheat.sh** (`<leader>?h`) — TLDR for any tool
- **devdocs** (`<leader>?d`) — offline language docs

### Just for fun (`:Play`)
Eight novelty modules behind a single command: `aurora`, `matrix`, `tarot`, `tiny_world`, `haiku`, `synth`, `oracle`, `glyph`. Try `:Play` for a picker, or `:Play tarot` to fire one.

---

## VSCode parity table

| VSCode feature | What you get here | Keymap |
|---|---|---|
| Source Control panel | Neogit (better — magit-style) | `<leader>gn` |
| Git Lens / inline blame | Gitsigns + blame line + `:Seance` whispers | `<leader>ghb` |
| Pull Requests extension | Octo | `<leader>Op` |
| GitHub Actions extension | gh-actions.nvim | `<leader>gA` |
| Run and Debug | DAP + DAP-UI | `<leader>du` |
| Tasks (`tasks.json`) | Overseer | `<leader>Tt` |
| Testing | Neotest | `<leader>ts` |
| Remote Containers | devcontainer.nvim | `<leader>Du` |
| Jupyter notebooks | Quarto + Molten + jupytext | `<leader>Ji` |
| Live Server | live-server.nvim | `<leader>Wl` |
| REST Client | kulala.nvim (`.http` files) | `<leader>Rs` |
| SQLTools | vim-dadbod + UI | `<leader>D` |
| Kubernetes | kubectl.nvim | `<leader>k` |
| Search & Replace | grug-far | `<leader>sR` |
| Outline | Aerial | `<leader>cO` |
| Breadcrumbs | dropbar.nvim | (always on) |
| Color picker | ccc.nvim | `<leader>Wp` |
| Markdown Preview | markdown-preview.nvim | `<leader>mp` |
| Emmet | emmet-language-server (auto) | (typing) |
| Tailwind IntelliSense | tailwindcss-ls + tailwind-tools | (typing) |
| Bracket Pair Colorizer | rainbow-delimiters | always on |
| TODO Tree | todo-comments + Trouble | `<leader>st` |
| AI Copilot Chat | Avante (Claude) | `<leader>aT` |
| Command Palette | **`:Suggest`** (better — contextual) | `<Space><Space>` |
| Refactor menu | refactoring.nvim | `<leader>crm` |
| Generate docstring | Neogen | `<leader>cn` |
| Multi-cursor | multicursor.nvim | `<leader>m` |
| Peek definition | Glance | `gpd` |
| Integrated terminal | toggleterm + flatten + smart-splits | `<C-/>` |
| File explorer | Neo-tree + Oil + Yazi | `<leader>e` / `-` / `:Yazi` |
| Notebook (Obsidian-like) | obsidian.nvim | `<leader>nn` |
| Settings UI | hand-edited Lua (better — version-controlled) | `:e $MYVIMRC` |

---

## First-class languages

| Language | LSP | Formatter | Linter | DAP | Tests | Notable extras |
|---|---|---|---|---|---|---|
| **Lua** | lua_ls | stylua | — | — | — | full nvim API completion |
| **Python** | pyright + ruff | ruff | ruff | debugpy | neotest | venv-selector, jupyter (opt) |
| **TS/JS** | vtsls + eslint | prettierd | eslint | js-debug | neotest | emmet, tailwind, auto-import on file move |
| **Go** | gopls | gofumpt/goimports | — | delve | neotest | struct tags, fillstruct, GoImpl, GoIfErr |
| **Rust** | rust_analyzer | rustfmt | clippy | codelldb | neotest | macro expand, runnables, cargo completion |
| **Bash** | bashls | shfmt | shellcheck | — | — | |
| **JSON** | jsonls + schemastore | prettierd | — | — | — | schema-aware completion |
| **YAML** | yamlls + schemastore | prettierd | — | — | — | schema-aware completion |
| **Markdown** | marksman + ltex | prettierd | markdownlint | — | — | render-markdown, pencil, preview |
| **HTML** | emmet + tailwindcss | prettierd | — | — | — | auto-tag close |
| **CSS/SCSS** | cssls (auto) + tailwind | prettierd | — | — | — | ccc color picker, document colors |
| **TOML** | taplo | taplo | — | — | — | |
| **Docker** | dockerls + hadolint | — | hadolint | — | — | docker-compose-langserver |
| **HTTP** | (kulala) | — | — | — | — | request runner in `.http` files |
| **SQL** | (dadbod completion) | — | — | — | — | live schema completion from connection |

---

## Workflows — a day in the life

### Open a project cold
```
$ nvim ~/code/myrepo
```
Snacks dashboard pops with `good afternoon, joseph.` and three actions. Pick `r` to pick up where you were. Or:
- `<Space><Space>` — open Suggest, it'll tell you what to do based on what state the repo is in
- `<leader><space>` — same thing
- `<leader>e` — Neo-tree on the left
- `<leader>fy` — Yazi for full TUI file management
- `<leader>1-4` — jump to a Harpoon-pinned file

### The bug-fix loop (now reactive)
1. `<Space><Space>` opens Suggest. Top entry is `fix · Undefined name 'foo' in line 23`. Press `1`.
2. Cursor jumps to the error. `:Explain` streams Claude's diagnosis into virt_lines below the line.
3. Apply the fix, save. Suggest **re-ranks in place** — `fix` drops, `run nearest test` climbs.
4. Press `2` (or whatever number it ended up on). Test passes. Suggest re-ranks again. `commit` is now top.
5. Press `1`. Neogit opens. After commit, Suggest closes.
6. Tomorrow at 6pm with dirty buffers, Suggest will surface `commit` higher because you keep picking it.

### Reviewing a PR without leaving nvim
1. `<leader>Op` lists open PRs (Octo, via `gh`)
2. Pick one — buffer opens with full PR description, comments, reviews
3. `<leader>Oc` for CI checks; `<leader>gA` for the full Actions panel
4. Open changed files, comment inline, submit review with `:Octo review submit`

### Writing in your second brain
1. `<leader>nn` new note in Obsidian vault (or `<leader>nt` for today's daily)
2. Type in markdown — render-markdown renders live; ltex-ls flags grammar
3. `<leader>cP` to paste a screenshot from clipboard (auto-saves, inserts link)
4. `<leader>mp` opens a synced browser preview

### Hacking on Python with a notebook
1. `<leader>cv` picks the right venv
2. Open a `.ipynb` — jupytext converts to markdown
3. `<leader>Ji` starts a Jupyter kernel; `<leader>Je` evaluates cells inline
4. `<leader>td` debugs the test under cursor with debugpy

### Database exploration
1. `<leader>D` opens dadbod-UI
2. Add a connection or pick a saved one
3. `<leader>S` runs the query in a `.sql` buffer

---

## Native Lua modules (`lua/user/`)

42 hand-rolled modules (~9300 lines of original Lua, no third-party deps beyond what's already loaded), plus 8 novelty toys under `lua/user/_play/`. Loaded eagerly as one pseudo-plugin spec at `lua/plugins/user-modules.lua`.

### Design system (foundation for everything else)
| Module | What it does |
|---|---|
| `brand`     | Color palette, geometry, typography, motion tokens. `brand.win(opts)` is the single window builder every other module uses. |
| `curtain`   | 140ms ease-out-quad open/close animation for every brand-built float. |
| `welcome`   | First-launch ritual: NVIM banner with gradient sweep + tagline. One-time marker; `:Welcome` to replay. |

### Headline entry points
| Module | What it does | Trigger |
|---|---|---|
| `suggest`     | Reactive context-aware action panel · 38 built-in actions + per-project `.suggest.lua` · self-aware (surfaces tour/playbooks/journal/macros/cockpit/state when relevant) · live re-ranking · project-scoped learning · playbook hints · **preview-on-hover** (cursor on an item shows a one-line target preview via virt_lines — e.g. `commit` → list of dirty filenames, `fix · error` → location+message) · **chip-styled rows** (top item gets accent-bg digit + bold accent label; learned items get green ● chip; project actions get info-blue marker) | `<Space><Space>` |
| `commandeer`  | which-key filter that hides irrelevant leader bindings · `<leader>?` escapes to full · **adaptive**: loosens rules after 3 escapes to the same namespace | `<leader>` (with timeout) |
| `playbooks`   | Discovered chains from sequence learning · name + pin to `F2`-`F5` · fire by key | `:Playbooks` / `<leader>up` |
| `tour`        | 7-slide guided walkthrough of the headlines · first-launch nudge | `:Tour` |

### Daily-driver tools
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `state`        | `:UserState{,Clear,Export,Import}` | `<leader>us` | Inspect every persistent state file · sizes / ages / descriptions · selective clear · tar export/import across machines |
| `yankring`     | — | `<leader>p` | Persistent yank history of 50, telescope picker with syntax preview |
| `ai_cmd`       | `:AI <intent>` | `<leader>ai` | Direct one-shot Anthropic API call with cursor context |
| `perfhud`      | `:PerfHUD` | `<leader>uP` | Live FPS/RSS/LSP req rate/top-5 slowest plugins float |
| `present`      | `:Present` | `<leader>P` | Markdown → slideshow split on `# H1` |
| `workspace`    | `:WorkspaceSave/Load/List` | `<leader>WS/WR/WL` | Tab×window+harpoon snapshot per cwd |
| `tabs`         | `:Tab{Rename,Pick,PickClose,Last,UndoClose,NewNamed,CloseOthers,JumpLabel,Move{Left,Right}}` | `<M-j>{letter}` · `<M-1>..<M-9>` · `<M-\`>` · `<leader><tab>{r,a,p,D,N,o,u,1-9,<tab>,<,>}` | HCI-grounded named tabs: tabid-keyed names + labels survive `:tabmove` · `<M-j>{letter}` stable jump derived from name · clickable chips · `<tab><tab>` toggles MRU (`↶` marks target) · picker is MRU-sorted with previewer · `<tab>u` undo-close (10-deep) · `<tab>o` confirms if ≥2 named tabs would die |
| `repl`         | `:Repl*` | `<leader>rt/rl/rp/rb/rr` | Per-filetype REPL with send line/paragraph/buffer/selection |
| `coverage`     | `:Coverage{Show,Hide,Refresh}` | `<leader>uc/uC` | Cobertura/LCOV gutter signs |
| `jobs`         | `:Job <name> <cmd>` / `:JobList` | `<leader>uj` | Async job queue; spinner in lualine |
| `heatmap`      | `:Heatmap` | `<leader>uh` | Git blame age → 9-step gradient gutter |
| `pulse`        | (auto) | (auto on `n`/`N`/`*`/`#`) | Search-jump line flash |
| `webhook`      | `:WebhookStart <port>` | — | TCP HTTP server inside nvim |
| `symtree`      | `:SymTree` | `<leader>uo` | LSP symbol ASCII tree side panel |
| `today`        | `:Today` | `<leader>ut` | Today's commits/files/lines + hourly sparkline |
| `spotlight`    | `:Spotlight` | `<C-S-Space>` / `<leader>uS` | Unified picker across files+marks+diagnostics+commands+AI |
| `smartpaste`   | `:SmartPaste` | `<leader>uv` | Detects URL/JSON/base64/UUID/hex/timestamp in clipboard |
| `tsplay`       | `:TSPlay` | `<leader>cl` | Live treesitter AST playground |
| `rextest`      | `:RegexTest` | `<leader>uR` | Floating regex with live match-highlighting |
| `explain`      | `:Explain` | `<leader>cX` | Streaming AI explanation of diagnostic — SSE → virt_lines |
| `timetravel`   | `:TimeTravel` | `<leader>gT` | Scrub the current file across every commit |
| `macroreg`     | `:Macro{Save,Run}` | `<leader>qm/qM` | Persistent named macro library |
| `resume`       | `:Resume{Capture,Brief,List,Resolve}` | `<leader>Kc/Kr/Kl/Kx` | Per-project task intent with async Resume Brief (what changed while you were away) · auto-pause on DirChanged · virtual-text hint on return · Calm-Tech (Weiser 1995): zero prompts in steady state |

### Cockpit / mission control
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `cockpit`      | `:Cockpit` | `<leader>!!` | Engage full HUD layout (symtree L, trouble R, terminal bottom, compass+radar floating) |
| `compass`      | `:Compass` | `<leader>!c` | Always-on bottom-right HUD, 5 rows of Catppuccin-colored chips, tunes with mode: mode capsule · dir + branch + git status · LSP + diagnostics · cpu/ram telemetry · date + clock + pomo/jobs spinner |
| `radar`        | `:Radar` | `<leader>!r` | Circular ASCII radar plotting diagnostics + marks by proximity |
| `throttle`     | `:Throttle` | `<leader>!t` / `<F1>` | 2×N tiled action launcher |
| `checklist`    | `:Preflight` | `<leader>!p` | Pre-flight checks (working tree clean, on branch, no debug prints, …) |
| `blackbox`     | `:Blackbox` | `<leader>!b` | Event recorder with timeline browser |
| `eject`        | `:Eject` | `<leader>!e` | Panic: closes floats, kills jobs, stops webhook, resets layout |
| `starship`     | (lualine segs) | — | 30-module starship-style statusline — mode capsule, animated job spinner, pulsing macro REC, LSP/diag/lang capsules, system telemetry |

### Opt-in / niche (invoked by command)
| Module | Command | What it does |
|---|---|---|
| `dreams`       | `:Dreams` / `:DreamNow` | After 90s idle, AI generates a surreal paragraph and types it into a sidebar |
| `rift`         | `:Rift` (visual mode) | Visual selection → ripgrep across project → floating "echoes" panel |
| `constellation`| `:Constellation` | Project files as a star map; size = LOC, color = recency |
| `synesthesia`  | `:Synesthesia` | Hashes every identifier to a deterministic pastel color |
| `cipher`       | `:Cipher` | AES-256-CBC encrypted scratchpad in a float |
| `seance`       | `:Seance` | On CursorHold, whispers git blame author + age + commit subject |
| `homunculus`   | `:HomunculusWake` / `:HomunculusRead` | AI agent writes today's git activity to `~/notes/journal/YYYY-MM-DD.md` |
| `quill`        | `:Quill` / `:QuillReplay` | Logs every keystroke; replays a past session as typing animation |
| `summon`       | `:Summon` | Recall any plugin window you've closed in the last 20 |

### Novelty namespace — `:Play`
Single entry point, lazy-loaded. `:Play` opens a picker; `:Play <name>` runs directly. Includes: `aurora` (gradient float), `matrix` (katakana rain), `tarot` (developer's tarot card), `tiny_world` (ASCII garden), `haiku` (AI haiku for current function), `synth` (chord on save), `oracle` (AI yes/no with coin animation), `glyph` (cursor-word sigils).

### Setup requirements per module
| Module | Needs |
|---|---|
| `ai_cmd`, `explain`, `suggest` (just for `:Explain` action), `dreams`, `homunculus`, `:Play oracle`, `:Play haiku` | `ANTHROPIC_API_KEY` |
| `cipher` | `openssl` (preinstalled on macOS) |
| `seance`, `heatmap`, `timetravel`, `today`, `homunculus` | git repo |
| `coverage` | `coverage.xml` / `lcov.info` in the project |
| `:Play synth` | macOS (`afplay`) or Linux (`paplay`/`canberra-gtk-play`) |
| `webhook` | nothing — `vim.uv.new_tcp` builds the server |
| `tsplay`, `symtree`, `synesthesia` | LSP attached (for symtree) / treesitter parser |

---

## Diagnostic tool — `doctor.sh`

`~/.config/nvim/scripts/doctor.sh` runs nvim headless, captures `:checkhealth` + `:messages` + `lazy.stats()`, and surfaces only the actionable issues. Exit code = number of `❌ ERROR` lines.

```bash
./scripts/doctor.sh              # default: actionable — issues minus a curated noise list
./scripts/doctor.sh issues       # all errors + warns (no noise filter)
./scripts/doctor.sh keymaps      # static scan: <leader> collisions across all specs
./scripts/doctor.sh stats        # plugin count + startup ms
./scripts/doctor.sh messages     # just :messages
./scripts/doctor.sh health       # full :checkhealth (~10k lines)
./scripts/doctor.sh errors       # only ❌ lines
./scripts/doctor.sh warns        # only ⚠ lines
./scripts/doctor.sh full         # the whole report
./scripts/doctor.sh section snacks   # one plugin's section
```

The `actionable` filter drops lines you've knowingly accepted: snacks modules explicitly disabled in `extras.lua`, headless-only artifacts (kitty graphics protocol, dashboard "not ready"), optional overseer adapters with no project file, mason languages you don't write, and the lazy/luajit 5.1 false-positive. The noise list lives at the top of `doctor.sh` — extend it when a new line trains your eye to skip past it. Real regressions still appear because they won't match.

The `keymaps` mode statically parses every `<leader>` binding declared in `lua/plugins/*.lua` and `lua/core/*.lua`. lazy.nvim silently last-wins on collisions, so without this they only surface when you press the docs-promised key and get the wrong feature. Which-key `group = "..."` entries and buffer-local LSP-on-attach bindings are excluded — only real global collisions report.

Polls until the checkhealth buffer stabilizes (≥1s of no growth, 12s max). CI-friendly:

```bash
if ./scripts/doctor.sh; then echo "clean"; fi
```

---

## Keymap reference

`<Space>` is leader. Press it (with the 350ms which-key timeout) for a context-filtered popup. **`<leader>?`** opens the unfiltered full reference. **`<Space><Space>`** opens Suggest.

### Global
| key | action |
|---|---|
| `<Space><Space>` | **`:Suggest`** — context-aware action panel |
| `<F1>` / `<leader>!t` | Throttle — 2×N action grid |
| `<leader>?` | which-key, all bindings |
| `<leader>w` / `<leader>q` / `<leader>Q` | write / quit / smart-quit (confirms unsaved) |
| `<leader>e` / `<leader>E` | Neo-tree toggle / focus |
| `-` | Oil — open parent directory |
| `<C-/>` | toggle terminal (floating) |
| `<C-y>` | resume Yazi |
| `s` / `S` | Flash jump / Flash treesitter |
| `<C-S-p>` / `<D-S-p>` | Telescope commands palette |
| `<leader>!` | Quick shell command (prompts, runs in floating term) |

### Suggest (`<Space><Space>` or `:Suggest`)
| key (inside panel) | action |
|---|---|
| `1`-`6` | Fire that suggestion |
| `?` | Close panel, open full bindings reference |
| `q` / `<Esc>` | Close |

`:SuggestStats` shows learned state. `:SuggestForget` wipes it.

### Search (`<leader>s`)
`sg` live grep · `sw` grep word · `sb` buffer fuzzy · `sd` diagnostics · `sk` keymaps · `sc` commands · `sh` help · `sm` marks · `sr` registers · `sR` project replace (grug-far) · `s.` resume last · `st` todos

### LSP / Code (`<leader>c`, plus bare-key navs)
| key | action |
|---|---|
| `gd` `gr` `gI` `gy` `K` | def / refs / impl / type / hover |
| `gpd` `gpr` `gpt` `gpi` | Glance peek versions |
| `<leader>cr` `<leader>ca` `<leader>cf` | rename / code action / format |
| `<leader>cs` `<leader>cS` | document / workspace symbols |
| `<leader>cl` | Treesitter playground · also runs LSP codelens action |
| `<leader>cn` / `<leader>cN` | generate docstring / class doc |
| `<leader>cO` | Aerial outline |
| `<leader>cp` | breadcrumb picker (dropbar) |
| `<leader>cP` | paste clipboard image (markdown) |
| `<leader>cX` | AI explain diagnostic (streaming) |
| `<leader>th` / `<leader>tF` | toggle inlay hints / autoformat |
| `]d` `[d` | next / prev diagnostic |
| `]]` `[[` | next / prev LSP reference (snacks.words) |

### Refactor (`<leader>cr`) — visual selection where applicable
| key | action |
|---|---|
| `cre` / `crf` | extract function / to file |
| `crv` | extract variable |
| `cri` / `crI` | inline variable / function |
| `crb` / `crB` | extract block / to file |
| `crp` / `crV` / `crc` | print line / print var / cleanup prints |
| `crm` | refactor menu |

### Multi-cursor (`<leader>m`)
`<leader>m` (n) start at cursor · `<leader>m` (v) start from selection · `<up>` / `<down>` (n/v) add cursor on line above/below · `<leader>md` / `<leader>mD` next/prev match · `<leader>mA` all matches · `<leader>ms` skip · `<leader>mw` arbitrary motion · `<leader>mc` clear · `<Esc>` smart clear

### AI (`<leader>a`)
| key | action |
|---|---|
| `<M-l>` `<M-]>` `<M-[>` | accept / next / prev Copilot ghost text |
| `<leader>aT` `<leader>aA` `<leader>aE` | Avante toggle / ask / edit |
| `<leader>ai` | `:AI` — one-shot Anthropic call about cursor |

### Git (`<leader>g`)
| key | action |
|---|---|
| `<leader>gn` / `<leader>gN` | Neogit / Neogit floating |
| `<leader>gc` / `<leader>gP` / `<leader>gp` / `<leader>gl` | commit / push / pull / log |
| `<leader>gG` | Lazygit (floating) |
| `<leader>gV` / `<leader>gh` / `<leader>gH` | Diffview / file history / repo history |
| `<leader>gA` | GitHub Actions panel |
| `]h` `[h` | next / prev hunk |
| `<leader>ghs ghr ghp ghb` | stage / reset / preview / blame hunk |
| `<leader>gxo gxt gxb gxn` | merge conflict: ours / theirs / both / none |
| `<leader>gx]` `<leader>gx[` | next / prev conflict |
| `<leader>gB` | open file/line on GitHub remote |
| `<leader>gT` | TimeTravel — scrub current file across commits |

### GitHub via Octo (`<leader>O`)
`Op` PR list · `OP` new PR · `Oi` issue list · `OI` new issue · `Or` start review · `Oc` PR checks · `Os` search

### Tests (`<leader>t`)
`tn`/`tN` nearest / file · `ts` summary · `to` output · `tO` panel · `td` debug nearest · `tS` stop

### Debug (`<leader>d`)
`db` breakpoint · `dB` conditional · `dc` continue · `di`/`do`/`dO` step in/over/out · `dr` repl · `du` UI · `dl` run last · `dt` terminate
Per-language: Go `<leader>dgt/dgl` · Python `<leader>dpt/dpc/dps`

### Tasks (`<leader>T`)
`Tt` panel · `Tr` run template · `Tc` run shell cmd · `Ta` quick action · `Ti` info · `Tb` build · `Tl`/`Ts` load/save bundle

### Diagnostics / Trouble (`<leader>x`)
`xx` workspace · `xX` buffer · `xs` symbols · `xr` LSP refs · `xq` quickfix · `xQ` Trouble quickfix · `xL` loclist

### Utility (`<leader>u`)
`uS` Spotlight · `uv` Smart paste · `up` Perf HUD · `uo` SymTree · `ut` Today · `uj` Jobs · `uh` Heatmap · `uc`/`uC` Coverage on/off · `uR` Regex tester · `uw`/`uW` Webhook start/stop

### Workspace (`<leader>W`)
`WS` save · `WR` restore · `WL` list

### Resume (`<leader>K`) — task intent across interruptions
`Kc` capture (objective / next step / verify-first / notes) · `Kr` Resume Brief panel (async what-changed: commits, file churn, branch divergence) · `Kl` list paused tasks across projects · `Kx` resolve current project's task

### Tabs (`<leader><tab>`) — named, clickable, HCI-grounded
| key | action |
|---|---|
| **`<M-j>`{letter}** | **jump by stable letter label** — each tab gets a single-char label derived from its name (`api` → `[a]`); pressing `<M-j>` shows the menu, the next keystroke selects |
| **`<M-J>`{letter…}**`<Esc>` | **sustained label-jump** — mode stays active across multiple jumps; each keystroke jumps, `<Esc>` / `<CR>` exits. Amortizes mode-entry cost when scanning several tabs in sequence (`<M-J>asd<Esc>` = 5 keystrokes for 3 jumps) |
| `<M-1>`..`<M-9>` / `<M-\`>` | chord-free positional jump to tab N / toggle MRU |
| `<leader><tab>n` / `<leader><tab>N` | new tab (auto-named) / new + prompt for name |
| `<leader><tab>c` / `<leader><tab>o` / `<leader><tab>D` | close current / close all others (commits immediately, no confirm) / pick one to close |
| `<leader><tab>u` / `<leader><tab>U` | **undo close** (single) / **batch undo** — `u` pops the most recent close; `U` reopens *every* tab from the last close operation (e.g. everything `<leader><tab>o` just killed) in one keystroke |
| `<leader><tab>r` / `<leader><tab>R` / `<leader><tab>a` | rename / revert last rename (swap with previous) / revert to auto-name (`cwd:t`) |
| `<leader><tab>]` / `<leader><tab>[` | next / prev (vim's `gt` / `gT` also work) |
| `<leader><tab><tab>` | toggle to most recently used tab (look for the `↶` chip in the tabline) |
| `<leader><tab>1`..`<leader><tab>9` | positional jump (discoverable in which-key menu) |
| `<leader><tab>p` | pick by name — MRU-sorted, previewer shows files in the highlighted tab, `<CR>` jump · `<C-r>` rename · `<C-x>` close |
| `<leader><tab>>` / `<leader><tab><` | move current tab right / left |

Each chip in the tabline shows `▎N [label] icon name`. The active tab's accent bar is `▎`; the MRU toggle target gets `↶`. Names persist across sessions in `~/.local/state/nvim/tab_names.json`.

**HCI grounding** — the design choices have specific principles behind them:

- **Stable identity** (Nielsen #4 consistency, recognition-over-recall): names and letter labels are keyed by tabpage *id*, not tabnr, so `:tabmove` doesn't silently shuffle either one. The tab you named `api` keeps the name *and* the `[a]` label wherever you drag it. Labels are assigned in tabid (creation) order so the first-created `src` gets `[s]` regardless of where it currently sits.
- **Fitts's Law** (one-keystroke target): `<M-j>{letter}` is two keystrokes for any tab; `<M-N>` is one keystroke for tabs 1–9; click is mouse-free. Multiple paths to the same target with different speed/memorability tradeoffs (Nielsen #7: flexibility).
- **Reversibility over confirmation** (Gmail "Undo Send" 2009, Material snackbar 2014, Tognazzini's First Principles ongoing): when recovery is cheap and visible, pre-confirmation is wasted friction in the common case. `close_others` commits immediately and its notify advertises the escape hatch in the same beat — `closed 4 other tabs · <leader><tab>U to restore all`. Batch undo restores everything from the last close operation (snapshots harvested within 500ms of each other = one user op) in a single keystroke, so even `:tabonly`-style bulk closes are one-keystroke reversible.
- **Trustworthy cognitive offloading** (Risko & Gilbert 2016 "Cognitive Offloading" in *Trends in Cognitive Sciences*; foundational: Clark & Chalmers 1998 "The Extended Mind"): the undo-close stack persists to disk at `~/.local/state/nvim/tab_undo_stack.json`, debounced on `TabClosed` and flushed synchronously on `VimLeavePre`. Closed-tab recovery survives `:qa`, crashes, reboots, and overnight idle. On load, entries whose files vanished between sessions are pruned (no zombie restores). The user can offload "what tab did I close yesterday" to the system *for real* — externalization that's actually externalized. Registered with `user.state` so `:UserState` lists it.
- **In-region micro-feedback** (Bartram 2002 "Whisper, Don't Scream"; Just & Carpenter eye-mind hypothesis 1976/1980; Calm Technology, Case ongoing): restoring a tab no longer fires a floating notify panel — the restored chip itself flashes `↺` with a green-tinted highlight for 1.5s, in the tabline where the user's eye is already going. Batch undo flashes all restored chips simultaneously — three glyphs blinking at once *is* "restored 3 tabs," shown in the region of action. Sub-threshold for distraction, pre-attentively detectable. The notify is kept only for failure paths (no closed tabs, no previous tab) where no visual change happens and the user needs the auditory channel for status.
- **Spatial context preservation** (Czerwinski et al. 2004 "A Diary Study of Task Switching and Interruption," CHI; Norman 1983 mental models; the grounding behind Chrome's close-tab-to-prior behavior since 2008): closing the current tab is one deliberate context shift — vim's default of dumping you on the spatially adjacent tab adds an *unintended* second shift. The TabClosed handler now overrides vim's auto-pick: when you close current, focus returns to your MRU-previous tab. Tabs `[home, code, docs, api, test]`, you were on `test` having just come from `code`, you `<leader><tab>c` → you land on `code`, not `api`. The "side trip" you took into the closed tab unwinds cleanly to where you were before it. Closing a *non-current* tab leaves focus untouched (only intentional close-of-current triggers the restore, gated by a TabLeave handler that captures the leaving tabid).
- **Semantic zoom / focus+context** (Furnas 1986 "Generalized Fisheye Views"; Sarkar & Brown 1992; Carpendale 2005 "A Framework of Distortion Viewing"; modern: constraint-aware density): when the sum of full-chip widths would exceed the screen, the renderer estimates total width up front and switches non-priority chips to a compact form (`▎N [x]` — lead glyph + tabnr + label, no icon, no name). Active tab and MRU toggle target stay at full density — they're the user's two primary contexts and lose the most from compaction. Just-restored chips also stay full (the ↺ flash deserves its full presence). Even at 15+ tabs in a 100-col terminal, every `[label]` affordance stays visible so `<M-j>{letter}` reaches any tab regardless of whether its full name fits on screen — recovery via the picker remains available for names the user can't read at a glance.
- **Ambient transparency for offloaded state** (Pousman & Stasko 2006 "A Taxonomy of Ambient Information Systems"; Hassenzahl 2010 "Experience Design"; modern: explainable-AI / transparent-automation 2020s applied to any tool that holds state for the user): the persistent undo stack quietly carries closed-tab recovery across sessions, but the user can't trust offloading they can't see. Risko & Gilbert (the cognitive-offloading paper backing the persistence work) explicitly identify this as the trust gap that makes offloading fail in practice. Fix: a soft `↺N` chip appears in the lualine statusline whenever the undo stack is non-empty — invisible when zero (calm tech preserved, no ink for no state), green-tinted chip when ≥1. Clicking opens the picker (which shows ghost rows for every closed tab). Peripheral awareness without interruption — the user *knows* what the tool is holding for them, can glance at it, can act on it, never has to ask "do I still have that tab I closed?"
- **Flow-preserving sustained interaction** (Hutchins, Hollan & Norman 1986 "Direct Manipulation Interfaces"; Csíkszentmihályi 1990 flow theory applied to UX; modern: "sticky modes" in Cursor / Linear / VSCode multi-cursor — GOMS keystroke-level analysis from Card-Moran-Newell 1983, still actively cited): when a user wants to scan several tabs in sequence, single-shot `<M-j>` charges the mode-entry cost on every jump (`<M-j>a <M-j>d <M-j>s` = 6 keystrokes for 3 jumps). `<M-J>` (capital) opens *sustained* label-jump: the peach feedforward highlight stays continuously visible, each keystroke jumps, `<Esc>` / `<CR>` exits, a missed label exits with a notify so the user can't get lost. Three jumps becomes `<M-J>asd<Esc>` = 5 keystrokes for 3 jumps — one cognitive setup ("I'm browsing my workspace") covers the whole chain.
- **Symmetric forgiveness** (Tognazzini's First Principles of Interaction Design; Norman 2013 *Design of Everyday Things* revision; modern: NN/g's "error recovery as design" — every destructive action should be reversible with no special remembering, not just the ones the designer happened to remember). Earlier rounds shipped close-undo, batch-undo, persistent cross-session undo, and the ambient `↺N` chip — closing was fully forgiving. But rename was the silent asymmetry: type a typo, hit `<CR>`, the old name was gone. Fix: `<leader><tab>R` (capital, symmetric with lowercase `r` for rename) swaps current ⇄ previous custom name. One-deep history per tab, in-memory only (rename is rare; persistent rename history would bloat the state file). The rename prompt's title bar surfaces `was 'oldname' (<leader><tab>R reverts)` whenever the tab has a revertable history — recovery affordance visible *at the moment of decision*, not hidden behind documentation the user has to remember exists. Revert is itself revertible (the swap preserves both directions), and `_prev_name` entries are reaped when tabs close so the table stays bounded.
- **Temporal awareness in spatial interfaces** (Tversky 2019 *Mind in Motion* — humans naturally read time from spatial displays when temporal info is inline; Munzner 2014 *Visualization Analysis and Design*; ongoing 2020s spatial-temporal info-vis): the picker showed tabs spatially (MRU-sorted) but the *temporal* dimension was invisible — the user couldn't tell which tab they were just on a minute ago vs. one abandoned three hours ago. Fix: picker rows now show idle time inline. Live rows read `▎ 2 [a]  16s  api  (1 win)` (active reads `now`); ghost rows read `↺ src (closed 1h ago · 2 files)` (just-closed reads "just now" so the wording stays natural at the low-resolution end). Wall-clock `os.time()` for both `_last_visited_epoch` per tab and `closed_at_epoch` per snapshot — survives cross-session restarts so yesterday's closed tab in the picker still reads "1d ago" instead of "0s ago" (which would happen with the within-session `uv.now()` monotonic clock the batching logic uses). Tabline itself stays clean — added density goes to the deeper view that warrants it (focus+context principle reapplied).
- **Mixed-initiative interaction with ghost-text suggestion** (Horvitz 1999 "Principles of Mixed-Initiative User Interfaces," AAAI; modern lineage through Copilot inline 2021 / Cursor 2023 / VSCode IntelliSense — system *proposes*, user *accepts or overrides*, reducing interaction cost without taking control): `<leader><tab>N` opened an empty prompt every time, leaving the user to invent a name on the spot — even though the system had rich context (cwd, git branch) it could have proposed from. Fix: when the prompt buffer is empty AND a suggestion exists, the system's best guess renders as faded `Comment`-colored ghost text trailing the cursor (alongside the prospective `[label]` it would yield). Type anything → ghost disappears, replaced by the live label preview for what you typed. `<CR>` on empty input → suggestion accepted. `<CR>` after typing → your text wins. The suggestion comes from `smart_default_name()`: `cwd:t · branch_basename` when in a non-default git branch, else `cwd:t` — defaults (`main`, `master`, `HEAD`) are suppressed because they don't add signal. Headless fallback surfaces `[suggest: ...]` in the prompt label and applies the same empty-submit-accepts contract.
- **Proximity as relatedness** (Tversky 2019 *Mind in Motion* reapplying Gestalt grouping to modern spatial UIs; Munzner 2014 *Visualization Analysis and Design*; ongoing 2020s work on workspace clustering — Suh et al. 2023): the tabline was a flat horizontal line, equally weighting tabs from different projects. The system already knew about relatedness — each tab's cwd — but wasn't exploiting it visually, so the user had to mentally re-cluster every glance. Fix: chip-to-chip spacing now reflects cwd relatedness. Same-cwd tabs cluster with the standard tight gap; cwd transitions get a thin ` ╱ ` separator (a wider gap in compact mode, where ink density is constrained). Quiet when all tabs share a cwd (no separator, no visual noise); informative when tabs span multiple projects — `nvim api docs ╱ tmp ╱ home` lets the eye auto-group `nvim/api/docs` as one workspace before reading a single name. Tversky's research: humans group adjacent items as related *automatically*; supporting that with intentional spacing is free cognitive scaffolding.
- **Pre-attentive cues for urgent state** (Treisman & Gelade 1980 "A Feature-Integration Theory of Attention"; modern lineage through Healey & Enns 2012 "Attention and Visual Memory in Visualization and Computer Graphics" and Ware 2019 *Information Visualization: Perception for Design*, 4th ed): the tabline carried `●` for unsaved changes but was *blind* to LSP errors in non-current tabs — a user editing `api` while `docs` accumulated three errors had zero peripheral awareness. Fix: chips with ≥1 ERROR-severity diagnostic append `⚠N` in a red highlight. Color (red) + shape (`⚠`) double-encode urgency — both are pre-attentive features (~200ms detection latency, no conscious scanning required), so the urgent chip pops from a row of normal-toned ones automatically. Per-tab count cached and invalidated on `DiagnosticChanged` so the cost is bounded under high-frequency render. Warnings/info/hints excluded — too common to be load-bearing as a peripheral cue (noise > signal). Errors-only is the calibration: rare enough that the glyph stays meaningful, urgent enough to be worth interrupting peripheral calm.
- **Redundant encoding for accessibility** (WCAG 1.4.1 "Use of Color" — W3C, ongoing through WCAG 2.2 published 2023; ISO 9241-171 software accessibility; modern lineage through Apple HIG and Material 3 accessibility chapters): color must never be the *sole* indicator of state. ~8% of men have red-green color blindness; some users run monochrome terminals; bright-sunlight environments compress color distance. An audit across the prior 17 rounds turned up one remaining gap — active vs inactive was differentiated purely by background color (accent vs surface) and bold weight. Modified `●`, MRU `↶`, restored `↺`, error `⚠N`, label `[x]` all already pair color with shape; active didn't. Fix: lead glyph now weight-encodes activeness — `▌` (half-block, heavier) for active, `▎` (thin bar, unchanged) for inactive. Same family of glyphs so the visual rhythm is preserved; weight difference survives monochrome rendering, color-blind perception, and high-glare displays. The rest of the encoding chain stays as-is; active just gained a shape signifier alongside its color one.
- **Affordance ≠ signifier** (Norman 2013 *Design of Everyday Things* revised edition — Norman's own self-revision separating *what's possible* from *the cue that the possibility exists*; modern lineage through NN/g's 2020s discoverability research; standard practice in command palettes — VSCode, Linear, Cursor, Raycast all publish inline keybind legends): the picker had three powerful in-panel actions — `<CR>` select, `<C-r>` rename, `<C-x>` close-or-drop — but none had a visible signifier. A first-time user opened the picker, saw a list of tabs, had zero indication the advanced actions existed. Telescope has a built-in `<C-/>` help overlay, but *that* itself isn't signified either — a recursive discoverability gap. Fix: the picker's `results_title` (telescope's section header above the rows, where the user's eye is already going) now displays the mode-aware keybind legend. Jump mode shows `<CR> jump · <C-r> rename · <C-x> close (ghost: <CR> restore · <C-x> drop)` so the user knows ghost rows behave differently; close mode shows the tighter `<CR> close · <C-r> rename · <C-x> drop` since ghosts are excluded from that flow. Affordance, signifier, locus of attention — all three colocated.
- **System status visibility** (Nielsen #1): tabline shows current (`▎`), toggle target (`↶`), label (`[x]`), modified (`●`), file icon, and name in every chip — no hidden state.
- **Recognition rather than recall**: picker shows label, name, MRU rank, win count, modified status, and a file-list preview pane in one panel. The label appears in both the tabline and the picker — incidental learning makes the muscle memory build itself.
- **Calm Technology** (Case, 2014): `set showtabline=1` so the tabline disappears entirely when there's only one tab. Zero-information UI is invisible UI; the row of vertical space is given back to actual content. The tabline reappears the moment a second tab exists.
- **Recovery as first-class** (anticipatory design): the picker mixes live tabs with **ghost rows** for the undo-close stack — selecting `↺ src (closed · 2 files)` restores it. Recovery surfaces *in the same flow* you'd already use to find a tab, instead of behind a separate keymap. `<C-x>` on a ghost row drops it from the stack; `<C-x>` on a live tab closes it. Same gesture, both "remove this entry from view" (Nielsen #4 consistency across modes).
- **Feedforward / self-revealing gestures** (Vermeulen et al., 2013): pressing `<M-j>` to enter label-jump mode flips every `[x]` chip in the tabline to a high-contrast peach background — the affordance reveals itself *in the region the user is already looking at*, with no cmdline echo to split attention. Out of mode, labels rest in the calm accent. Mode reveals itself synchronously through the affordance that already lives there, instead of forcing the eye down to a separate menu.
- **Information at point of decision** (Card/Moran/Newell 1983 GOMS; modern: Yang, Steinfeld & Rosé, CHI 2020): the rename / new-named prompt is a floating one-line input whose title shows the labels currently in use, and whose trailing virtual text updates in real time as you type — `name new tab: app   → [p]` shifts to `→ [b]` if you backspace and type `bug`. The user sees the *consequence of their input* while choosing it, closing Norman's gulf of evaluation pre-emptively instead of forcing a commit-then-discover cycle. Headless / no-UI sessions fall through to `vim.ui.input` with a static `[in use: a d n]` hint — still principled, just without the live preview.

### Sessions / Macros (`<leader>q`)
`qs` restore cwd · `ql` restore last · `qd` stop saving · `qm` macros pick · `qM` save reg q as named macro

### Harpoon (pinned files)
`<leader>H` add · `<leader>h` menu · `<leader>1..4` jump · `<M-S-N>` / `<M-S-P>` next / prev

### Notes (`<leader>n`)
| key | action |
|---|---|
| `nn` / `no` / `ns` | new note / open / search |
| `nt` / `ny` / `nT` | today / yesterday / tomorrow |
| `nb` / `nf` / `ng` | backlinks / follow link / tags |
| `nr` / `np` / `nx` | rename / paste image / toggle checkbox |
| `np1` / `np2` / `np3` | pomodoro 25m focus / 5m break / 15m long break |

### Dev apps
| key | action |
|---|---|
| `<leader>D` | Database UI (dadbod) |
| `<leader>k` | Kubernetes panel |
| `<leader>Wl` / `<leader>Wp` / `<leader>Wc` | live server / color picker / convert color |
| `<leader>Du` / `<leader>Dd` / `<leader>Da` / `<leader>Dx` / `<leader>Dl` | devcontainer: up / down / attach / exec / logs |
| `<leader>?h` / `<leader>?d` / `<leader>?D` | cheat.sh / devdocs current ft / devdocs search |

### REST (`.http` buffers, `<leader>R`)
`Rs` send · `Ra` send all · `Rl` replay · `RI` inspect · `Rn`/`Rp` next/prev · `Rc` copy as curl · `Rf` paste from curl

### Notebook (`<leader>Q` Quarto / `<leader>J` Molten)
`Qp`/`Qq` preview start/stop · `Qe` run above · `QE` run all · `Qr` run below
`Ji` init kernel · `Je` (n) eval operator · `Jr` (v) eval selection · `Jl`/`Jc` line/recell · `Jh`/`Jo`/`Jd` hide/enter/delete output

### Language-specific (active only in matching buffers)
**Rust** — `<leader>cR` action · `<leader>cE` expand macro · `<leader>cC` open Cargo.toml · `<leader>cM` parent module · `<leader>tr`/`<leader>tD` runnables/debuggables
**Go** — `<leader>cgt`/`cgT` add/rm tags · `cgi` impl · `cgf`/`cgs` fill struct/switch · `cge` if-err · `cgr` go run
**Python** — `<leader>cv` select venv
**Web** — Emmet expands (e.g. `div.foo>p*3<TAB>` in insert mode)

### Windows
| key | action |
|---|---|
| `<C-h/j/k/l>` | nvim window navigation |
| `<A-h/j/k/l>` | smart-splits — crosses tmux/wezterm panes |
| `<A-S-h/j/k/l>` | resize across same |
| `<leader>wp` / `<leader>ws` | pick window / swap window |
| `<S-h>` / `<S-l>` | prev / next buffer |

### Markdown
`<leader>mp` browser preview · `<leader>cP` paste image · `<leader>P` Present (slideshow)

### Toggles (`<leader>t`)
`tc` TS context · `tT` Twilight (dim) · `ta` autosave · `tF` autoformat · `th` inlay hints · `tP` toggle filter (Commandeer)

### Play (`<leader>` doesn't have a Play binding — pure command surface)
`:Play` for picker · `:Play <name>` to run · `:Play oracle <q>` for args

---

## The status bar

One continuous starship-style chain — the per-mode capsule anchors the left, and every segment from there flows through powerline wedges. The whole line is built in `lua/user/starship.lua` and rendered through lualine.

```
● NORMAL ◆  joseph ◆ nvim ◆ poetry ◆ v0.4.1 ◆  main ↑2 ◆ +3 ~1 -0 ◆  3  1 ◆ 󰒋 lua·tsserver ◆ ⠋ 2 jobs ◆ ↓1 ◆ direnv ◆  file.py ◆ ✦ ◆  3.12  .venv ◆ cpu ▂▂▂ 2.5 ◆ ram 67% ◆ 80% ◆  14:32
```

Cut to the essentials. Only segments with *something to say right now* render. The chain skips empty segments so the visual rhythm stays tight — no python segment in a `.go` file, no docker segment if there's no Dockerfile, no SSH host unless you're actually remote.

**Mode capsule** — left anchor, per-mode color + glyph + label. Every Vim sub-mode mapped: `● NORMAL · ◐ O-PEND ·  INSERT · 󰒉 VISUAL · 󰒉 V·LINE · 󰒉 V·BLOCK ·  REPLACE ·  COMMAND ·  EX ·  SHELL ·  TERMINAL ·  PROMPT`. The bg color shifts with mode (blue normal → green insert → mauve visual → red replace → peach command → teal terminal) — the whole left half visually retunes when you change mode.

**Mode-reactive accent everywhere** — the same mode color drives the active **bufferline tab underline**, the **compass mode capsule**, the **cursor block/beam** (`Cursor` / `iCursor` / `vCursor` / `rCursor` / `cCursor` / `TermCursor`), and the **popup borders** (`FloatBorder`, `FloatTitle`, blink.cmp menu/doc/signature borders, telescope borders, `LspSignatureActiveParameter`). All wired through one `ModeChanged` autocmd in `user.starship._hook_mode_accent`. Six surfaces breathe together — flip to INSERT and statusline + bufferline + compass + cursor + popups + line number (via modicator) all tune green at once; flip to VISUAL and they all shift mauve. Floats that set their own `winhighlight` (compass, brand panels) keep their existing styling — the mode-accent only affects defaults.

**Diagnostic gutter chips** — `DiagnosticSignError` / `Warn` / `Info` / `Hint` are overridden to chip-style (base fg + severity bg + bold) so the gutter icons render as colored capsules instead of fg-only glyphs. Same color-by-severity vocabulary as the statusline diagnostic chip and compass diagnostics row. Re-applied on `ColorScheme` so theme reloads don't strip it.

**Animated segments** — refresh runs at 10fps so motion reads as smooth:
- `⠋ N jobs` — braille spinner that advances per frame while `user.jobs` has running tasks; vanishes the instant the queue clears
- `● REC @q` — pulsing red capsule (500ms period) while recording a macro
- `✓ saved · file.lua` — save pulse chip after every `BufWritePost`. Bright green for the first 60% of a 1.6s window, then fades to teal for the last 40% — the eye reads the transition as "ack". Flips to red `✗ saved · file` if the write failed. Tiny micro-feedback on the action you do hundreds of times a day.
- `▶ morning-routine · 2m` — last-fired playbook LED (sapphire while running, green ✓ on done, red ✗ on error). Records the most recent `M.run_chain()` call, fades from the chain after 10 minutes of inactivity — so you remember what just ran without it cluttering the line forever.
- `♥` / `♡` — session heartbeat. Once a minute, for 200ms, a tiny red heart pulses (lit ♥ for the first 100ms, dim ♡ for the second 100ms) on the right side of the chain. Pure delight detail — signals "the editor is alive" without ever demanding attention. Anchored on `vim.uv.now() % 60000` so it fires deterministically at the top of every minute.
- `⌨ 2.4k · 47m` — engagement chip on the right side. Tracks keystrokes today (persisted to `~/.local/state/nvim/engagement.json`, resets at midnight) and minutes since this nvim's `VimEnter`. Counts via `vim.on_key`; writes batch to disk every 5s so high-rate input doesn't thrash. Survives nvim restarts within the same calendar day. Format: raw under 1k, `X.Yk` to 10k, `Nk` past that.
- `🔥 14d` — writing-streak chip. Consecutive calendar days you've launched nvim. Persisted alongside the engagement count. Hidden at streak ≤ 1 (no gloating on day 0/1). Bg color tiers escalate with streak length: surface (2–6 days, subtle) → yellow (7+, week) → peach (14+, two weeks) → mauve (30+, month+). Computed via a strict day-after check (`os.time + 86400`), so a single missed day resets the streak to 1.

**Always-visible:** mode · user · cwd · clock · cpu · ram · battery (when not fully charged) · OS
**Conditional:** git branch+ahead/behind/stash · git diff stats · diagnostics (severity-colored bg) · LSP clients · ↓updates if behind upstream · direnv · jobs spinner · macro pulse · search match count · pomo · overseer counts · autoformat status · Copilot status · python/node/go/rust version · package version · k8s context · cloud account · cmd duration (only after >500ms commands)

---

## The compass HUD

`:Compass` (or `<leader>!c`) toggles a small floating panel pinned to the bottom-right corner. Five rows of Catppuccin-colored chips, rounded border, `COMPASS` title centered. Refreshes every 250ms.

```
╭────────── COMPASS ──────────╮
│ ● NORMAL                    │   mode capsule (per-mode color, mirrors statusline)
│  nvim   main   ✓         │   dir (sky) · branch (mauve) · git clean/dirty
│ 󰒋 lua_ls·tsserver    clean │   LSP chip (teal) · diagnostics (severity-colored bg or green "clean")
│ cpu ▃▃ 1.20    ram 67%      │   system telemetry — bg escalates orange→red on pressure
│  Wed May 20    14:32      │   date · time · pomo + jobs spinner if active
╰─────────────────────────────╯
```

**Design symmetry with the statusline** — pulls `user.starship._mode_defs` for the mode capsule and `user.starship.c` for the color palette, so the same single source of truth drives both surfaces. Diagnostic semantics match (red→yellow→sky→teal by severity, green for "clean"). Spinner uses the same braille frames at the same 80ms phase, so the compass spinner and the statusline spinner animate in lockstep.

**Coloring without statusline syntax** — buffer content can't use lualine's `%#hl#text%*` tags, so chips are colored via `vim.api.nvim_buf_set_extmark` with auto-registered `Compass_<n>` highlight groups (one per unique fg/bg/bold tuple). Same caching pattern as `user.starship.hl()`.

**Reactive details:**
- **Auto-resize** — width recomputes per tick; window resizes silently when content changes (branch name shrinks, LSP clients attach)
- **Pressure colors** — cpu chip turns orange above 60% normalized load, red above 85%; ram chip turns orange above 75%, red above 90%; the compass visibly "heats up" when the system does
- **Conditional extras** — pomo remaining-time and `⠋ N` jobs spinner appear in row 5 only when active

---

## Recently shipped

A chronological log of the visual / UX slices that landed in the current arc. New readers can skip; returning ones can scan to see what changed.

### Visual coherence arc

**1. Statusline v2** — `user.starship`, `plugins/ui.lua`
Anchored the left half with a per-mode capsule (16 sub-modes mapped: blue NORMAL · green INSERT · mauve VISUAL · red REPLACE · peach COMMAND · teal TERMINAL · sapphire PROMPT · yellow SHELL). Lualine refresh bumped 200ms → 100ms so animated chips read as smooth. Dropped lualine_a (mode moved into the chain) so the whole left half is one continuous powerline with no theme-color seam.

**2. Compass HUD v2** — `user.compass`
Plain-text 1995 box replaced with five rows of Catppuccin-colored chips rendered via `nvim_buf_set_extmark` (statusline `%#hl#` syntax doesn't work in buffer content). Pulls `user.starship._mode_defs` and `user.starship.c` so the mode capsule and color palette stay in sync with the statusline by reference. Auto-resizes per 250ms tick; pressure colors on cpu/ram chips so the HUD visibly heats up under load.

**3. Mode-reactive accent — bufferline + cursor + popups** — `_hook_mode_accent`
One `ModeChanged` autocmd in `user.starship` retints **15 bufferline highlight groups** (selected tab underline + indicator + diagnostic variants), **7 cursor groups** (Cursor / iCursor / vCursor / rCursor / cCursor / lCursor / TermCursor), and **9 popup-border groups** (`FloatBorder`, `FloatTitle`, blink.cmp menu/doc/signature, telescope borders, `LspSignatureActiveParameter`). Six visible surfaces — statusline + bufferline + compass + cursor + line number + popup borders — all retune in lockstep. Floats that set their own `winhighlight` (compass, brand panels) are insulated.

**4. Animated chips for state changes** — `M.modules.*` in `user.starship`
- `⠋ N jobs` — braille spinner (12.5fps, anchored on `vim.uv.now()` so all spinners phase-lock)
- `● REC @q` — pulsing red capsule when recording a macro (500ms period)
- `✓ saved · file.lua` — save pulse: two-phase fade (bright green → teal) over 1.6s after every `BufWritePost`. Flips red on failed writes.
- `▶ morning-routine · 2m` — last-fired playbook LED (sapphire running, green ✓ done, red ✗ error). 10-minute TTL.
- `♥` / `♡` — session heartbeat: 200ms pulse once per minute, anchored on `vim.uv.now() % 60000` so it fires deterministically.
- `⌨ 2.4k · 47m` — engagement chip: keystrokes today (persisted via `vim.on_key` + debounced writes) + session minutes.
- `🔥 14d` — writing-streak chip with tiered bg colors (surface 2-6d → yellow 7+ → peach 14+ → mauve 30+). Strict day-after math; gap of 1+ days resets to 1. Hidden at streak ≤ 1.

**5. Diagnostic gutter chips** — `_hook_diag_chips`
`DiagnosticSign{Error,Warn,Info,Hint}` overridden to chip-style (base fg + severity bg + bold). The gutter icons now render as colored capsule pills instead of fg-only glyphs. Same severity color vocabulary as the statusline `diag` chip and compass diagnostics row.

**6. Suggest panel chip polish + preview-on-hover** — `user.suggest`
Each row's digit becomes a 3-col colored chip — `BrandChipAccent` for the top item, `BrandChipSurface` for others. Learned items get a green ` ● ` chip; project actions get a `▸` info-blue marker; top item's label is bold-accent. Cursor placement triggers a one-line virt_lines preview below the focused item, describing what the action would target right now (e.g. `commit` → list of dirty filenames, `fix · error` → location + message). 11 action previews covered; uncovered actions gracefully skip.

**7. Playbooks panel chip polish** — `user.playbooks`
Final persistent panel onto the chip vocabulary. Two-row layout per item: chip row (digit + pin chip + name + ×strength) + dimmed chain row. Top item's digit uses accent bg, others use surface; pinned chains get an ok-green pin chip. `selected_item()` rewired to find the focused item across both rows of the layout. Three persistent panels — Suggest, Playbooks, Compass — now speak one chip vocabulary.

### Stability fixes that landed alongside

- **`curtain.lua`** — guarded the animation timer's close so queued `vim.schedule_wrap` callbacks can't re-enter and call `timer:close()` on an already-closing handle ("handle is already closing" spam fixed).
- **`user.suggest`** — forward-declared `find_project_root` and `project_name` so the `fingerprint()` function (defined earlier in the file) can call them. Was crashing every `:Suggest` invocation silently.
- **`user.starship.chain`** — escapes `%` in chip text to `%%` before wrapping with `%#hl#` markers; also sanitizes the noice cmdline echo component in `lualine_c`. Fixes the `E539: Illegal character < >` lualine crash when typing `:`-commands containing `%` (e.g. `:e %`, `:%s/x/y/`).
- **Snacks dashboard `preset.header`** — newer snacks requires it to be a string, not a function. Dynamic greeting moved into a custom function-section that returns `{ align, padding, text }` — same visual, supported API.
- **`kubectl.nvim`** — added the missing `build = "make build"` hook to the lazy spec. Plugin needs a Rust client (`libkubectl_client.dylib`) built via Go + Cargo on first install. Without the hook, `:Kubectl` crashed with `module 'kubectl_client' not found`.

### Shared design system

Brand-level chip tokens added to `user.brand` so every panel pulls from one vocabulary:

```lua
BrandChipAccent   { fg = bg,   bg = accent,  bold = true }
BrandChipSurface  { fg = text, bg = surface, bold = true }
BrandChipOk       { fg = bg,   bg = ok,      bold = true }
BrandChipWarn     { fg = bg,   bg = warn,    bold = true }
BrandChipErr      { fg = bg,   bg = err,     bold = true }
BrandChipInfo     { fg = bg,   bg = info,    bold = true }
```

Change a token, every panel using it updates. Five surfaces and three panels speak the same color language.

---

## Layout / where things live

```
~/.config/nvim
├── init.lua                    # entry
├── install.sh                  # one-shot system bootstrap
│
├── lua/core/                   # options, keymaps, autocmds, lazy bootstrap
│
├── lua/plugins/                # 30 spec files
│   ├── colorscheme · ui · visual · treesitter · lsp · completion
│   ├── copilot · avante
│   ├── telescope · explorer · yazi
│   ├── git · git-advanced
│   ├── editor · extras · refactor
│   ├── dap · tasks
│   ├── lang-rust · lang-go · lang-python
│   ├── devtools · web · notebook
│   ├── markdown · notes · writing
│   ├── fun · terminal-hub
│   └── user-modules            # loads everything under lua/user/
│
├── lua/user/                   # 45 native modules — daily-driver tools
│   ├── (design)        brand · curtain · welcome · tour
│   ├── (entry points)  suggest · commandeer · playbooks · state
│   ├── (utilities)     yankring · ai_cmd · perfhud · jobs · heatmap · today · spotlight
│   │                   smartpaste · explain · timetravel · macroreg · coverage · symtree
│   │                   workspace · repl · pulse · rextest · tsplay · webhook · present
│   ├── (cockpit)       cockpit · compass · radar · throttle · checklist · blackbox · eject
│   ├── (statusline)    starship
│   └── (niche)         dreams · rift · constellation · synesthesia · cipher · seance
│                       homunculus · quill · summon
│
├── lua/user/_play/             # 8 novelty toys behind `:Play`
│   ├── aurora · matrix · tarot · tiny_world
│   └── haiku · synth · oracle · glyph
│
└── scripts/
    └── doctor.sh               # headless :checkhealth + :messages capture
```

**Mental model:** every module under `lua/user/` is a single feature. Setup happens in `lua/plugins/user-modules.lua` which `require()`s each module's `setup()`. Adding a new module = write `lua/user/foo.lua` with a `setup()`, add a `require("user.foo").setup()` line, optionally add a keymap to its `keys = {...}`.

---

## Customization

- **Change colorscheme** — edit `lua/plugins/colorscheme.lua` and the `theme = "catppuccin-mocha"` line in `lua/plugins/ui.lua`. Catppuccin lualine themes are named `catppuccin-{mocha,latte,frappe,macchiato}`, not bare `catppuccin`.
- **Change the accent color** — `lua/user/brand.lua` → `M.c.accent`. Every float, border, key chip, suggest panel marker, prompt — all flow from that one value.
- **Add a language** — append to `ensure_installed` in `lua/plugins/lsp.lua` (LSP), `lua/plugins/treesitter.lua` (parser), and `formatters_by_ft` in lsp.lua for conform.
- **Add a Suggest action globally** — append to the `ACTIONS` table in `lua/user/suggest.lua`. Each entry is `{ id, when(ctx)→priority, label(ctx)→str, run(ctx) }`.
- **Add a Suggest action per-project** — `:SuggestProjectEdit` from any project root scaffolds a `.suggest.lua` with a template. Same entry shape.
- **Name + pin a playbook** — open `:Playbooks`, navigate to a row, press `n` to name, `p` to pin to an F-key. Persists across sessions.
- **Carry your learning between machines** — `:UserStateExport` produces a tarball of Suggest's learning + Playbooks + yankring + macros + tiny_world + workspace snapshots (excluding the encrypted scratchpad and LSP log). `:UserStateImport <path>` restores on the other side.
- **Selectively reset a single module's state** — `:UserStateClear <id>` (completion lists all 11 ids). Or open `:UserState` and press `c` on a row.
- **Customize Commandeer filtering** — edit the `RULES` table in `lua/user/commandeer.lua`. Each key is the first char after `<leader>`; value is a function returning true/false based on context.
- **Customize the throttle launcher** — set `vim.g.throttle_actions` to a list of `{ key, label, icon, run }` entries.
- **Point Obsidian at an existing vault** — edit the `workspaces` table in `lua/plugins/notes.lua`.
- **Disable a plugin** — set `enabled = false` on its spec.
- **Pin a plugin version** — add `version = "x.y.z"` or `commit = "abc1234"` to its spec.

---

## Troubleshooting

**First step for any weirdness:** `./scripts/doctor.sh` (actionable signal, noise filtered).

| Symptom | Fix |
|---|---|
| "I don't know what's broken" | `./scripts/doctor.sh` |
| Wall of treesitter errors on open | Missing tree-sitter CLI. `brew install tree-sitter-cli` then `:TSUpdate` |
| Icons look broken / question marks | Set your terminal font to a Nerd Font (`brew install --cask font-jetbrains-mono-nerd-font`) |
| Copilot says "not authenticated" | `:Copilot auth` and follow the device-code link |
| Avante doesn't work | `echo $ANTHROPIC_API_KEY` — must be exported in your shell rc |
| LSP not attaching | `:Mason` — server should show ◍ (installed). `:LspInfo` shows what's attached |
| Snacks.image complains about magick/gs/tectonic/mmdc | All optional formats. PNG via Ghostty kitty protocol works without any of them |
| Lualine warns "theme not found" | Make sure `theme = "catppuccin-mocha"` (not bare `catppuccin`) in `lua/plugins/ui.lua` |
| Slow startup | `:Lazy profile` shows time per plugin. Doctor `stats` shows total |
| Want to nuke and restart | `rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim` (config in `~/.config/nvim` survives) |
| Suggest panel feels stuck | `:SuggestForget` wipes learned state; reopens fresh |
| Too many bindings in which-key | `:CommandeerToggle` flips between context-filtered and show-all |
| Tour was offered but I missed it | `:Tour` runs it from anywhere |
| Want a brand new user to see the tour | `:TourReset` clears the marker; next launch surfaces the nudge |
| Playbooks panel is empty | Fire 3+ matching sequences via `:Suggest` — chains discovered after that |
| `.suggest.lua` not loading | `:SuggestProject` shows path + actions; `:SuggestProjectReload` to force re-read |
| Not sure where my data lives | `:UserState` lists every state file with size + age + description |
| LSP log eating disk | `:UserState` shows its size; `:UserStateClear lsp_log` wipes it |
| `<leader>k` says `module 'kubectl_client' not found` | The Rust client wasn't built. `:Lazy build kubectl.nvim` runs the bundled `make build` step (needs Go + Cargo on PATH — both installed by the `brew install python go rustup` line above). If you hit a cargo network timeout fetching `k8s-openapi`, retry with `CARGO_HTTP_TIMEOUT=300 CARGO_NET_RETRY=10 make build` in `~/.local/share/nvim/lazy/kubectl.nvim/` |
| Statusline says `E539: Illegal character < >` | Was a known noice-cmdline-echo bug when typing `:e %`-style commands. Fixed via `%` escaping in `user.starship.chain` and the noice component. If you see it on a fresh install, pull the latest config |
| Suggest panel won't open | Verify with `:lua require("user.suggest").show()`. If it errors with `attempt to call global 'project_name' (a nil value)`, you're on an older copy — pull latest (forward-declared in `user.suggest`) |

---

Backups of any prior config land in `~/.config/nvim.bak-<timestamp>` — restore with `mv ~/.config/nvim.bak-<ts> ~/.config/nvim`.
