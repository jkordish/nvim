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

`113 plugins` · `30 plugin specs` · `42 native modules + 8 toys` · `nvim 0.12+` · `lazy.nvim` · `catppuccin mocha`

</div>

---

## What this is

A complete Neovim distro tuned to be your **single home in the terminal**. Native LSP for 15+ languages. Two AI surfaces (Copilot inline + Avante chat with Claude). Full git workflow with Magit-style commits, PR review, time-travel, line-by-line blame whispers. Database client, REST client, Kubernetes panel, Jupyter notebooks, Obsidian-style second brain. All running on nvim 0.12 with the modern `vim.lsp.config` API and the maintained `nvim-treesitter` main branch.

On top of that, a **design system** (`lua/user/brand` + `curtain` + `welcome`) and **50 hand-rolled native modules** that turn the editor into something more like a cockpit than a text widget. Two of those modules — **`suggest`** and **`commandeer`** — are the headline:

- **`<Space><Space>`** opens a context-aware action panel. Ranks 4-6 suggestions by what's actually relevant right now (errors, modified buffers, git state, filetype, time of day). Stays open as you work and re-ranks live as state changes. Learns from your picks — actions you take in a given context get a bonus the next time that context appears, and two-action sequences ("fix → commit") build a learned chain.
- **`<leader>`** (with the which-key timeout) shows only context-relevant bindings. In a non-git file you don't see git keymaps. In a Python file you see REPL keys. In a markdown file you see preview/present. **`<leader>?`** escapes to the full reference.

If VSCode does it, this does it — faster, in your terminal, on your keymaps. And then it keeps going.

---

## Table of contents

1. [Install — one shot](#install--one-shot)
2. [After install](#after-install)
3. [What Mason handles for you](#what-mason-handles-for-you-no-brew-needed)
4. [Per-feature setup](#per-feature-setup)
5. [Verifying you're set up](#verifying-youre-set-up)
6. [The two headlines: Suggest + Commandeer](#the-two-headlines--suggest--commandeer)
7. [Feature highlights](#feature-highlights)
8. [VSCode parity table](#vscode-parity-table)
9. [First-class languages](#first-class-languages)
10. [Workflows — a day in the life](#workflows--a-day-in-the-life)
11. [Native Lua modules (`lua/user/`)](#native-lua-modules-luauser)
12. [Diagnostic tool — `doctor.sh`](#diagnostic-tool--doctorsh)
13. [Keymap reference](#keymap-reference)
14. [The status bar](#the-status-bar)
15. [Layout / where things live](#layout--where-things-live)
16. [Customization](#customization)
17. [Troubleshooting](#troubleshooting)

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
./scripts/doctor.sh issues
```

---

## The two headlines — Suggest + Commandeer

These are what set this config apart. Read these even if you skip everything else.

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

### `<leader>` (with which-key timeout) — `user.commandeer`

The which-key popup is now context-filtered. Instead of dumping 80+ bindings on you, it shows only the ones relevant to right now.

- In a non-git buffer: no `<leader>g*` (Neogit, git-conflict, time-travel)
- In a non-Python file: no `<leader>r*` (REPL)
- In a non-markdown file: no `<leader>P` (Present)
- Without diagnostics: no `<leader>x*` (Trouble)
- Without a Makefile/Cargo.toml/etc.: no `<leader>T*` (tasks)

**`<leader>?`** opens the full unfiltered reference any time. **`:CommandeerToggle`** flips a session-level "show all" flag.

### How they relate

`<Space><Space>` is the *thinking* surface — "here's what makes sense right now."
`<leader>` is the *doing* surface — "I know what I want to press, just show me the namespace."

You'll use both. `<leader>` for muscle memory, `<Space><Space>` when you're not sure what to do next.

---

## Feature highlights

### Editor essentials
- **LSP** with inlay hints, document highlight, signature help, code actions, rename, format-on-save (`conform.nvim`)
- **Treesitter** (main branch) with context-sticky headers, textobjects, rainbow delimiters, auto-tag
- **Completion** via `blink.cmp` — LSP + path + buffer + snippets + Copilot, ghost text inline
- **Snippets** via LuaSnip + friendly-snippets
- **Linting** via `nvim-lint` (shellcheck, hadolint, markdownlint)

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
- **Kubernetes** — kubectl.nvim (`<leader>k`) — Lens-style pods/logs/exec
- **Jupyter** — Quarto + Molten with cell execution and inline plot rendering (opt-in)
- **Obsidian** — full second-brain (`<leader>nn`, `nt`, `nb`, `ng`)
- **Pomodoro** — `<leader>np1/2/3`, countdown shows in statusline
- **Devcontainers** — VSCode Remote Containers parity (`<leader>Cu`)
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
| Remote Containers | devcontainer.nvim | `<leader>Cu` |
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
| `suggest`     | Reactive context-aware action panel. Live re-ranking. Persistent learning. | `<Space><Space>` |
| `commandeer`  | which-key filter that hides irrelevant leader bindings. | `<leader>` (with timeout) |

### Daily-driver tools
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `yankring`     | — | `<leader>p` | Persistent yank history of 50, telescope picker with syntax preview |
| `ai_cmd`       | `:AI <intent>` | `<leader>ai` | Direct one-shot Anthropic API call with cursor context |
| `perfhud`      | `:PerfHUD` | `<leader>up` | Live FPS/RSS/LSP req rate/top-5 slowest plugins float |
| `present`      | `:Present` | `<leader>P` | Markdown → slideshow split on `# H1` |
| `workspace`    | `:WorkspaceSave/Load/List` | `<leader>WS/WR/WL` | Tab×window+harpoon snapshot per cwd |
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

### Cockpit / mission control
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `cockpit`      | `:Cockpit` | `<leader>!!` | Engage full HUD layout (symtree L, trouble R, terminal bottom, compass+radar floating) |
| `compass`      | `:Compass` | `<leader>!c` | Always-on bottom-right widget: mode · cwd · branch · LSP · clock |
| `radar`        | `:Radar` | `<leader>!r` | Circular ASCII radar plotting diagnostics + marks by proximity |
| `throttle`     | `:Throttle` | `<leader>!t` / `<F1>` | 2×N tiled action launcher |
| `checklist`    | `:Preflight` | `<leader>!p` | Pre-flight checks (working tree clean, on branch, no debug prints, …) |
| `blackbox`     | `:Blackbox` | `<leader>!b` | Event recorder with timeline browser |
| `eject`        | `:Eject` | `<leader>!e` | Panic: closes floats, kills jobs, stops webhook, resets layout |
| `starship`     | (lualine segs) | — | 25-module conditional starship-style statusline |

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
./scripts/doctor.sh              # default: issues (errors + warns), grouped by section
./scripts/doctor.sh stats        # plugin count + startup ms
./scripts/doctor.sh messages     # just :messages
./scripts/doctor.sh health       # full :checkhealth (~10k lines)
./scripts/doctor.sh errors       # only ❌ lines
./scripts/doctor.sh warns        # only ⚠ lines
./scripts/doctor.sh full         # the whole report
./scripts/doctor.sh section snacks   # one plugin's section
```

Polls until the checkhealth buffer stabilizes (≥1s of no growth, 12s max). CI-friendly:

```bash
if ./scripts/doctor.sh issues; then echo "clean"; fi
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
| `<leader>Cu` / `<leader>Cd` / `<leader>Ca` / `<leader>Cx` / `<leader>Cl` | devcontainer: up / down / attach / exec / logs |
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

Reading left to right with powerline wedges:

```
 NORMAL ◆ joseph@host ◆ nvim ◆ main ↑2 ◆ +3 ~1 -0 ◆ … ◆ file.py @q 3/47 ◆ ⠋ 2 jobs ◆  fmt-off ◆ ◆ ◆ ◆ py .venv 3.12 ◆ ↓1 ◆ direnv ◆ cpu ▂▂▂ 2.5 ◆ ram 67% ◆ 80% ◆ 14:32
```

Cut to the essentials. Only segments with *something to say right now* render. The starship-style chains hide modules whose context doesn't apply (no python segment in a `.go` file, no docker segment if there's no Dockerfile, no SSH host unless you're actually remote).

**Always-visible:** mode · user · cwd · clock · cpu · ram · battery (when not fully charged)
**Conditional:** git branch+ahead/behind/stash · git diff stats · ↓updates if behind upstream · direnv · jobs spinner · pomo · overseer counts · autoformat status · Copilot status · python/node/go/rust version · package version · k8s context · cloud account · cmd duration (only after >500ms commands)

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
├── lua/user/                   # 42 native modules — daily-driver tools
│   ├── (design)        brand · curtain · welcome
│   ├── (entry points)  suggest · commandeer
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
- **Add a Suggest action** — append to the `ACTIONS` table in `lua/user/suggest.lua`. Each entry is `{ id, when(ctx)→priority, label(ctx)→str, run(ctx) }`.
- **Customize Commandeer filtering** — edit the `RULES` table in `lua/user/commandeer.lua`. Each key is the first char after `<leader>`; value is a function returning true/false based on context.
- **Customize the throttle launcher** — set `vim.g.throttle_actions` to a list of `{ key, label, icon, run }` entries.
- **Point Obsidian at an existing vault** — edit the `workspaces` table in `lua/plugins/notes.lua`.
- **Disable a plugin** — set `enabled = false` on its spec.
- **Pin a plugin version** — add `version = "x.y.z"` or `commit = "abc1234"` to its spec.

---

## Troubleshooting

**First step for any weirdness:** `./scripts/doctor.sh issues`.

| Symptom | Fix |
|---|---|
| "I don't know what's broken" | `./scripts/doctor.sh issues` |
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

---

Backups of any prior config land in `~/.config/nvim.bak-<timestamp>` — restore with `mv ~/.config/nvim.bak-<ts> ~/.config/nvim`.
