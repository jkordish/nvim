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

`122 plugins` · `30 plugin specs` · `49 hand-rolled Lua modules` · `nvim 0.12+` · `lazy.nvim` · `catppuccin mocha`

</div>

---

## What this is

A complete Neovim distro tuned to be your **single home in the terminal** — not just an editor. Native LSP for 15+ languages, three AI assistants wired in (Copilot ghost text + Copilot Chat + Avante/Claude), full Git workflow including Magit-style commits and PR review, a database client, a REST client, a Kubernetes panel, Jupyter notebooks, a second-brain note system, all running on **nvim 0.12** with the modern `vim.lsp.config` API and the maintained `nvim-treesitter` main branch.

On top of that: a **`lua/user/` directory of 49 hand-rolled native modules** — yank-ring, AI cmdline with streaming, perf HUD, presentation mode, workspace snapshots, per-language REPL, coverage gutters, async job queue, git churn heatmap, search-jump pulse, in-nvim HTTP server, symbol tree, daily activity dashboard, spotlight picker, smart paste, treesitter playground, regex tester, streaming AI explainer, git time machine, named macros, cockpit HUD, starship-style statusline, compass, radar, throttle launcher, pre-flight checklist, black box recorder, eject panic, aurora animation, matrix rain, contribution calendar, code-as-constellation map, synesthesia identifier coloring, breathing exercise, AI haiku, idle-time dream paragraphs, save-chord audio, developer tarot deck, ASCII tamagotchi, dimensional rift, sigil generator, encrypted scratchpad, line-by-line blame whispers, journal-writing homunculus agent, keystroke steno + replay, window summoner, coin-flip oracle, upside-down code mirror.

If VSCode does it, this does it — faster, in your terminal, on your keymaps. And then it keeps going.

---

## Table of contents

1. [Install — one shot](#install--one-shot)
2. [After install](#after-install)
3. [What Mason handles for you](#what-mason-handles-for-you-no-brew-needed)
4. [Per-feature setup](#per-feature-setup)
5. [Verifying you're set up](#verifying-youre-set-up)
6. [Feature highlights](#feature-highlights)
7. [VSCode parity table](#vscode-parity-table)
8. [First-class languages](#first-class-languages)
9. [Workflows — show me a day in the life](#workflows--show-me-a-day-in-the-life)
10. [Native Lua modules (`lua/user/`)](#native-lua-modules-luauser) — the cockpit + 48 hand-rolled features
11. [Diagnostic tool — `doctor.sh`](#diagnostic-tool--doctorsh)
12. [Keymap reference](#keymap-reference) (`Space` is leader)
13. [The status bar](#the-status-bar)
12. [Layout / where things live](#layout--where-things-live)
13. [Customization tips](#customization-tips)
14. [Troubleshooting](#troubleshooting)

---

## Install — one shot

The fastest way: clone the config and run `install.sh`. Works on **macOS** (via Homebrew, installs it if needed) and **Ubuntu/Debian/Pop/Mint LTS** (via apt + GitHub release fallbacks for tools apt doesn't ship).

```bash
git clone <this-repo> ~/.config/nvim     # or copy the dir manually
cd ~/.config/nvim
./install.sh                              # interactive, recommended
```

The script:
1. Detects your OS (macOS or Ubuntu LTS)
2. Installs the package manager if missing (Homebrew on macOS)
3. Installs **required** tools (neovim, ripgrep, fd, tree-sitter, git, node, jq)
4. Installs **recommended** tools (lazygit, yazi, gh, pngpaste/xclip, JetBrainsMono Nerd Font)
5. Prompts per language for **toolchains** (python, go, rust, docker)
6. Prompts for **optional extras** (Ghostty, Quarto+Jupyter, glow)
7. Backs up any existing `~/.config/nvim` to `*.bak-<timestamp>`
8. Runs Lazy sync, compiles every Treesitter parser, installs every Mason tool
9. Verifies the install and prints next steps

**Flags:**

| Flag | Purpose |
|---|---|
| `--yes` / `-y`     | Accept every prompt, fully unattended |
| `--minimal`        | Required tools only, skip recommended + languages |
| `--skip-system`    | Skip OS package installs — just re-bootstrap plugins (use after a config change) |
| `--skip-bootstrap` | Skip nvim plugin bootstrap — just install OS deps |
| `--dry-run`        | Print what would run, don't execute |
| `-h` / `--help`    | Show help |

**Examples:**
```bash
./install.sh --yes                    # zero-prompt full install
./install.sh --minimal --yes          # bare minimum, quick start
./install.sh --skip-system            # bootstrap only — after pulling config changes
./install.sh --dry-run                # see what it would do
```

### If you'd rather install manually

Same packages the script handles — copy-paste this block:

```bash
# macOS
brew install neovim ripgrep fd tree-sitter tree-sitter-cli git node jq \
             lazygit pngpaste yazi gh
brew install --cask font-jetbrains-mono-nerd-font ghostty
brew install python go rustup && rustup-init -y
brew install --cask docker
brew install quarto glow
pip install --user pynvim jupyter_client cairosvg pnglatex plotly kaleido pyperclip nbformat

# Ubuntu / Debian / Pop / Mint LTS
sudo apt-get update
sudo apt-get install -y ripgrep fd-find git nodejs npm jq curl wget \
                        python3 python3-pip python3-venv build-essential
sudo ln -sf $(which fdfind) /usr/local/bin/fd
# neovim 0.11+ via official AppImage (apt's nvim is usually too old)
curl -L -o /tmp/nvim.tgz https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
sudo tar -C /opt -xzf /tmp/nvim.tgz && sudo ln -sf /opt/nvim-linux64/bin/nvim /usr/local/bin/nvim
# tree-sitter, lazygit, yazi, gh, etc. — see install.sh for the GitHub-release recipes
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

*Rust's `rust_analyzer` is installed and managed by `rustaceanvim`, not Mason.*

## Per-feature setup

| Feature | Setup beyond brew |
|---|---|
| Copilot | `:Copilot auth` |
| Avante (Claude) | `export ANTHROPIC_API_KEY=...` in shell rc |
| Octo + gh-actions | `gh auth login` |
| Lazygit, Yazi, pngpaste | in brew block |
| Inline images in markdown | Ghostty/WezTerm/Kitty + Snacks.image (built-in) |
| Markdown preview (`<leader>mp`) | needs `node`, builds itself on first launch |
| Live server (`<leader>Wl`) | auto-installs `live-server` via npm |
| Database UI (`<leader>D`) | nothing extra; add connections via `:DBUIAddConnection` |
| REST client | open any `.http` file — done |
| Devcontainers (`<leader>C`) | Docker Desktop or compatible runtime |
| Jupyter / Quarto | optional pip block above; plugins stay dormant until installed |
| Obsidian (`<leader>n*`) | nothing — `~/notes/{inbox,daily,assets}` auto-created |
| cheat.sh (`<leader>?h`) | internet only |
| devdocs (`<leader>?d`) | `glow` from optional block; `:DevdocsFetch <slug>` to download |

## Verifying you're set up

```vim
:checkhealth              " everything green except optional items you skipped
:Lazy                     " all plugins should show ● not ⏳
:Mason                    " LSPs/tools should all show ◍ (installed)
```

---

## Feature highlights

### Editor essentials
- **LSP** with inlay hints, document highlight, signature help, code actions, rename, format-on-save
- **Treesitter** (main branch) with context, textobjects, rainbow delimiters, auto-tag
- **Completion** via `blink.cmp` — LSP + path + buffer + snippets + Copilot, ghost text inline
- **Snippets** via LuaSnip + friendly-snippets

### AI, three flavors
- **Copilot** ghost text completions (`<M-l>` accept, `<M-]/[>` cycle)
- **CopilotChat** in-buffer chat with explain/review/fix/optimize/docs/tests templates
- **Avante** (Cursor-style agent powered by Claude Sonnet 4.6)

### Navigation
- **Telescope** (find files, grep, symbols, marks, registers, git…) + **fzf-lua** as alternate fast picker
- **Neo-tree** (`<leader>e`), **Oil** (`-`), **Yazi** (`<leader>fy`) — three file-explorer styles for any mood
- **Flash** (`s`/`S`) for jump-anywhere, **Harpoon** (`<leader>1-4`) for pinned files
- **Glance** floating peek windows (`gpd`/`gpr`/`gpt`/`gpi`)
- **Smart-splits** (`<A-h/j/k/l>`) that cross into tmux & wezterm panes

### Git (full Magit-class workflow)
- **Neogit** — magit-style staging/commit/rebase/log (`<leader>gn`)
- **Lazygit** floating (`<leader>gG`), **Fugitive** (`<leader>gg`), **Diffview** (`<leader>gV`)
- **Gitsigns** with inline hunk preview, blame, reset, stage from buffer
- **git-conflict** for inline merge resolution (`<leader>gxo/gxt/gxb`)
- **gh-actions** panel for CI runs (`<leader>gA`), **Octo** for full PR/issue review (`<leader>Op`)

### Per-language premium
- **Rust** — `rustaceanvim` with macro expansion, runnables, debuggables, integrated DAP via codelldb; `crates.nvim` for Cargo.toml version completion
- **Go** — `go.nvim`: struct tags, GoImpl, fill struct, fill switch, `if err != nil` boilerplate; `nvim-dap-go` via delve
- **Python** — `venv-selector.nvim` auto-detects venvs/poetry/conda; `nvim-dap-python` via debugpy; `neotest-python` for inline test runs
- **TypeScript** — `vtsls` (the fast successor to tsserver), `eslint`, **Emmet** + **TailwindCSS** LSP auto-attach in JSX/TSX/Vue/Svelte/Astro

### Real applications living in nvim
- **Database client** — vim-dadbod-ui (`<leader>D`) — Postgres/MySQL/SQLite/BigQuery side panel
- **REST client** — kulala (`<leader>Rs`) — open `.http`, send request, response in split
- **Kubernetes** — `<leader>k` — Lens-style pods/logs/exec/port-forward
- **Jupyter** — Quarto + Molten with cell execution and inline plot rendering
- **Obsidian** — full second-brain (`<leader>nn`, `nt`, `nb`, `ng`)
- **Pomodoro** — `<leader>np1/2/3` — timer in the statusline
- **Markdown preview** in browser with synced scroll
- **Live server** for HTML/CSS/JS dev
- **Devcontainers** — VSCode Remote Containers parity

### Refactoring & code intelligence
- **refactoring.nvim** — extract function/variable/block (with "to file" variants), inline, debug print injection
- **Multicursors** — Sublime-style multi-cursor (`<leader>m`)
- **Neogen** — generate docstrings (Google/rustdoc/godoc/JSDoc/TSDoc/ldoc)
- **Symbol usage** — virtual-text reference + impl counts above functions
- **Aerial** outline (`<leader>cO`), **Dropbar** winbar breadcrumbs (`<leader>cp`)

### Tests & debug
- **Neotest** (`<leader>tn/td/ts`) for python/go/rust with inline status
- **DAP + DAP-UI** with codelldb/debugpy/delve/js-debug-adapter wired
- **Overseer** task runner — VSCode `tasks.json` equivalent (`<leader>Tt`)

### Writing & docs
- **render-markdown** for live markdown rendering
- **markdown-preview** for browser-based synced preview
- **vim-pencil** prose mode (`<leader>tP`)
- **ltex-ls** for grammar/spell on `markdown`/`tex`/`text`/`gitcommit`
- **vim-wordy** for weak-word detection
- **img-clip** to paste clipboard screenshots into markdown (`<leader>cP`)
- **headlines** colored backgrounds for headers; **render-markdown** for emphasis/lists

### Visual polish
- **Catppuccin Mocha** with full plugin theming integration
- **noice** command line + UI · **nvim-notify** stacking notifications · **fidget** LSP progress
- **tiny-inline-diagnostic** floating diagnostic near cursor (replaces virtual_text)
- **incline** floating filename in each window
- **smear-cursor** silky animated cursor · **modicator** mode-colored line numbers
- **nvim-scrollbar** with diagnostic + git markers · **mini.map** minimap
- **Snacks** (folke) — bigfile handling, animated scroll, statuscolumn, zen mode, scratch buffer
- **Twilight** dim non-focused code · **Codesnap** beautify selections for sharing

### Lookups
- **cheat.sh** (`<leader>?h`) — TLDR for any tool
- **devdocs** (`<leader>?d`) — offline language docs

### Just for fun
- **Cellular automaton** (`<leader>Xr` make-it-rain · `Xg` game-of-life · `Xs` scramble)

---

## VSCode parity table

| VSCode feature                  | What you get here                                  | Keymap               |
|---------------------------------|----------------------------------------------------|----------------------|
| Source Control panel            | Neogit (better — magit-style)                      | `<leader>gn`         |
| Git Lens / inline blame         | Gitsigns + blame line                              | `<leader>ghb`        |
| Pull Requests extension         | Octo                                               | `<leader>Op`         |
| GitHub Actions extension        | gh-actions.nvim                                    | `<leader>gA`         |
| Run and Debug                   | DAP + DAP-UI                                       | `<leader>du`         |
| Tasks (`tasks.json`)            | Overseer                                           | `<leader>Tt`         |
| Testing                         | Neotest                                            | `<leader>ts`         |
| Remote Containers               | devcontainer.nvim                                  | `<leader>Cu`         |
| Jupyter notebooks               | Quarto + Molten + jupytext                         | `<leader>Ji`         |
| Live Server                     | live-server.nvim                                   | `<leader>Wl`         |
| REST Client                     | kulala.nvim (`.http` files)                        | `<leader>Rs`         |
| SQLTools                        | vim-dadbod + UI                                    | `<leader>D`          |
| Kubernetes                      | kubectl.nvim                                       | `<leader>k`          |
| Project Manager                 | telescope projects + Harpoon                       | `<leader>1-4`        |
| Search & Replace                | grug-far + spectre                                 | `<leader>sR`         |
| Outline                         | Aerial                                             | `<leader>cO`         |
| Breadcrumbs                     | dropbar.nvim                                       | (always on)          |
| Minimap                         | mini.map                                           | `<leader>tm`         |
| Color picker                    | ccc.nvim                                           | `<leader>Wp`         |
| Markdown Preview                | markdown-preview.nvim                              | `<leader>mp`         |
| Emmet                           | emmet-language-server (LSP, auto-attaches)         | typing               |
| Tailwind IntelliSense           | tailwindcss-ls + tailwind-tools                    | typing               |
| Bracket Pair Colorizer          | rainbow-delimiters                                 | always on            |
| TODO Tree                       | todo-comments + Trouble                            | `<leader>st`         |
| Copilot Chat                    | CopilotChat.nvim                                   | `<leader>aa`         |
| AI agent (Cursor)               | Avante (Claude)                                    | `<leader>aT`         |
| Command Palette                 | Telescope commands / fzf-lua commands              | `<leader>sc`         |
| Refactor menu                   | refactoring.nvim                                   | `<leader>crm`        |
| Generate docstring              | Neogen                                             | `<leader>cn`         |
| Multi-cursor                    | multicursors.nvim                                  | `<leader>m`          |
| Peek definition                 | Glance                                             | `gpd`                |
| Integrated terminal             | toggleterm + flatten + smart-splits                | `<C-/>`              |
| File explorer                   | Neo-tree + Oil + Yazi                              | `<leader>e` / `-` / `<leader>fy` |
| Notebook (Obsidian-like)        | obsidian.nvim                                      | `<leader>nn`         |
| Settings UI                     | hand-edited Lua (better — version-controlled)      | `:e $MYVIMRC`        |

---

## First-class languages

| Language    | LSP                      | Formatter        | Linter      | DAP        | Tests       | Notable extras                              |
|-------------|--------------------------|------------------|-------------|------------|-------------|---------------------------------------------|
| **Lua**     | lua_ls                   | stylua           | —           | —          | —           | full nvim API completion                     |
| **Python**  | pyright + ruff           | ruff             | ruff        | debugpy    | neotest     | venv-selector, jupyter (opt)                |
| **TS/JS**   | vtsls + eslint           | prettierd        | eslint      | js-debug   | neotest     | emmet, tailwind, auto-import on file move   |
| **Go**      | gopls                    | gofumpt/goimports| —           | delve      | neotest     | struct tags, fillstruct, GoImpl, GoIfErr    |
| **Rust**    | rust_analyzer            | rustfmt          | clippy      | codelldb   | neotest     | macro expand, runnables, cargo completion   |
| **Bash**    | bashls                   | shfmt            | shellcheck  | —          | —           |                                              |
| **JSON**    | jsonls + schemastore     | prettierd        | —           | —          | —           | schema-aware completion                      |
| **YAML**    | yamlls + schemastore     | prettierd        | —           | —          | —           | schema-aware completion                      |
| **Markdown**| marksman + ltex          | prettierd        | markdownlint| —          | —           | render-markdown, headlines, pencil, preview |
| **HTML**    | emmet + tailwindcss      | prettierd        | —           | —          | —           | auto-tag close                               |
| **CSS/SCSS**| cssls (auto) + tailwind  | prettierd        | —           | —          | —           | ccc color picker, document colors           |
| **TOML**    | taplo                    | taplo            | —           | —          | —           |                                              |
| **Docker**  | dockerls + hadolint      | —                | hadolint    | —          | —           | docker-compose-langserver                    |
| **HTTP**    | (kulala)                 | —                | —           | —          | —           | request runner in `.http` files             |
| **SQL**     | (dadbod completion)      | —                | —           | —          | —           | live schema completion from connection      |

---

## Workflows — show me a day in the life

### 1. Open a project cold
```
$ nvim ~/code/myrepo
```
Alpha dashboard pops with recent files. Pick one with `r`. Or:
- `<leader><space>` — fuzzy file pick (Telescope)
- `<leader>e` — Neo-tree on the left
- `<leader>fy` — Yazi if you want full TUI file management
- `<leader>fg` — git-tracked files only
- `<leader>1-4` — jump to a Harpoon-pinned file (after pinning with `<leader>H`)

### 2. The bug-fix loop
1. `<leader>sg` live-grep the project for the error string
2. Telescope jumps you in. Hit `K` for hover, `gd` for definition, `gr` for refs
3. `<leader>cn` to generate a docstring if it's missing
4. `<leader>ca` for code actions
5. `<leader>tn` runs the nearest test, `<leader>td` debugs it
6. Inline diagnostic floats next to cursor; `]d`/`[d` walk between them
7. Format-on-save fires automatically

### 3. Reviewing a PR without leaving nvim
1. `<leader>Op` lists open PRs (Octo, via `gh`)
2. Pick one — buffer opens with full PR description, comments, reviews
3. `<leader>Oc` to view CI checks; `<leader>gA` for the full Actions panel
4. Open changed files, comment inline, submit review with `:Octo review submit`

### 4. Writing a doc / journal entry
1. `<leader>nn` new note in your Obsidian vault (or `<leader>nt` for today's daily)
2. Type in markdown — render-markdown renders headers/lists/checkboxes live, headlines colors them
3. `<leader>cP` to paste a screenshot from clipboard (auto-saves, inserts link)
4. `<leader>tP` toggles prose mode (soft wrap, smart j/k)
5. ltex-ls flags grammar issues; `<leader>ca` applies its suggestions
6. `<leader>mp` opens a synced browser preview

### 5. Hacking on Python with a notebook
1. `<leader>cv` picks the right venv (auto-detects .venv/poetry/conda)
2. Open a `.ipynb` — jupytext converts it to markdown for editing
3. `<leader>Ji` starts a Jupyter kernel
4. `<leader>Je` evaluates cells; plots and tables render inline via Snacks.image
5. `<leader>td` debugs the test under cursor with debugpy

### 6. Pomodoro / focus block
1. `<leader>np1` starts a 25-minute focus timer — statusline shows `  24:31 focus`
2. `<leader>z` toggles Zen mode for distraction-free editing
3. Timer expires → desktop notification, statusline switches to break

### 7. Database exploration
1. `<leader>D` opens dadbod-UI panel
2. Pick a saved connection or `:DBUIAddConnection`
3. Browse schema in the tree, open any table to see the query template
4. `<leader>S` runs it; results render in a split with column completion in your queries

---

## Native Lua modules (`lua/user/`)

49 hand-rolled modules (~9300 lines of original Lua, zero third-party dependencies beyond what's already loaded). Loaded eagerly as one pseudo-plugin spec at `lua/plugins/user-modules.lua` so all commands and keymaps register at startup. Grouped by intent below.

### Practical — daily-driver tools (`<leader>u`)
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `yankring`     | —              | `<leader>p`  | Persistent yank history of 50, telescope picker with syntax preview |
| `ai_cmd`       | `:AI <intent>` | `<leader>ai` | Direct Anthropic API call with cursor context — returns suggestions |
| `perfhud`      | `:PerfHUD`     | `<leader>up` | Live FPS / RSS memory / LSP req rate / top-5 slowest plugins in a float |
| `present`      | `:Present`     | `<leader>P`  | Markdown → slideshow split on `# H1` |
| `workspace`    | `:WorkspaceSave/Load/List` | `<leader>WS/WR/WL` | Tab×window+cursor+harpoon snapshot per cwd |
| `repl`         | `:Repl*`       | `<leader>rt/rl/rp/rb/rr` | Per-filetype REPL with send line/paragraph/buffer/selection |
| `coverage`     | `:Coverage{Show,Hide,Refresh}` | `<leader>uc/uC` | Cobertura/LCOV gutter signs for covered/uncovered lines |
| `jobs`         | `:Job <name> <cmd>` / `:JobList` | `<leader>uj` | Async job queue; spinner in lualine `  ⠋ 2 jobs` |
| `heatmap`      | `:Heatmap`     | `<leader>uh` | Git blame age → 9-step color gradient gutter |
| `pulse`        | `:Pulse`       | (auto on n/N/*/#) | Search-jump line flash via extmark + timer |
| `webhook`      | `:WebhookStart <port>` | `<leader>uw/uW` | **Actual TCP HTTP server inside nvim** — POST /open, /eval, /notify |
| `symtree`      | `:SymTree`     | `<leader>uo` | LSP-symbol ASCII tree side panel with type-aware icons |
| `today`        | `:Today`       | `<leader>ut` | Today's commits/files/lines + 24-hour sparkline + top changed files |

### Power-user picker + transforms (`<leader>u` + `<leader>c`)
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `spotlight`    | `:Spotlight`   | `<C-S-Space>` / `<leader>uS` | Unified picker across files+buffers+marks+jumps+diagnostics+commands+AI |
| `smartpaste`   | `:SmartPaste`  | `<leader>uv` | Detects URL/JSON/base64/UUID/hex/timestamp in clipboard → offers transforms |
| `tsplay`       | `:TSPlay`      | `<leader>uT` | Live treesitter AST playground following the cursor |
| `rextest`      | `:RegexTest`   | `<leader>uR` | Floating regex input with live match-highlighting + count |
| `explain`      | `:Explain`     | `<leader>cX` | **Streaming** AI explanation of the diagnostic under cursor (SSE → virt_lines) |
| `timetravel`   | `:TimeTravel`  | `<leader>gT` | Scrub the current file through every commit that touched it with `←/→` |
| `macroreg`     | `:Macro{Save,Run}` | `<leader>qm/qM` | Persistent named macro library |

### The cockpit (`<leader>!`)
A mission-control HUD layout you can engage with one keystroke. Symtree on the left, Trouble on the right, terminal at the bottom, compass + radar floating, all balanced.

| Module | Command | Keymap | What it does |
|---|---|---|---|
| `cockpit`      | `:Cockpit` / `:Disengage` | `<leader>!!` | Engage / disengage the entire HUD layout |
| `compass`      | `:Compass`     | `<leader>!c` | Always-on floating display: mode · cwd · branch · LSP · git dirty · clock |
| `radar`        | `:Radar`       | `<leader>!r` | Circular ASCII radar showing diagnostics + marks plotted by proximity |
| `throttle`     | `:Throttle`    | `<leader>!t` / `<F1>` | Tiled action launcher — press 1-8 to fire (Run tests, Build, Lazygit, …) |
| `checklist`    | `:Preflight`   | `<leader>!p` | Pre-flight checks with pass/fail lights; override with `.preflight.lua` |
| `blackbox`     | `:Blackbox`    | `<leader>!b` | Event recorder (cmds, buf writes, LSP attach, yanks) with timeline browser |
| `eject`        | `:Eject`       | `<leader>!e` | Panic button: closes all floats, kills jobs, stops webhook, resets layout |
| `warnings`     | (lualine seg)  | —            | LED status lights: ●MOD ●ERR ●JOB ●GIT ●NET |
| `starship`     | (lualine segs) | —            | 25-module conditional statusline (next section) |

### The starship-style statusline modules
Each segment is a function returning `{text, fg, bg}` or `""` when context doesn't apply. Heavy TTL caching. Rendered with powerline `` wedges via auto-allocated highlight groups.

**Always:** os · user · dir · time · cmd_duration (after >500ms commands) · cpu · ram · battery
**Conditional:** ssh (only on remote) · git branch + ahead/behind/stash · git diff (when changes exist) · python venv (only in py files/projects) · node version (in JS/TS) · go (in go files) · rust (in rust files) · terraform (in tf) · docker (when Dockerfile in repo) · k8s (when k8s yaml + context) · cloud (gcloud/aws account) · direnv (when .envrc loaded) · update (↓N when behind upstream) · ai (Copilot+Avante combined) · pomo · project_type (auto-detect rust/go/node/poetry/…) · package_version (this project's own version from Cargo.toml/pyproject.toml/package.json)

### The artistic deck (`<leader>A`)
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `aurora`       | `:Aurora`     | `<leader>Aa` | Animated shifting-hue gradient floating in the corner |
| `matrix`       | `:Matrix`     | `<leader>Am` | Persistent katakana rain in a slim side column |
| `contribcal`   | `:Contributions` | `<leader>Ac` | GitHub-style 7×52 commit heatmap of your year |
| `constellation`| `:Constellation` | `<leader>An` | Project files as a star map; size = LOC, color = recency |
| `synesthesia`  | `:Synesthesia` | `<leader>As` | Hashes every identifier to a deterministic pastel color |
| `zen`          | `:Zen`        | `<leader>Az` | Animated breathing circle: 4s in · 4s hold · 4s out |
| `haiku`        | `:Haiku`      | `<leader>Ah` | AI 5-7-5 haiku about the function under cursor |

### The occult deck (`<leader>A` continued)
| Module | Command | Keymap | What it does |
|---|---|---|---|
| `dreams`       | `:Dreams` / `:DreamNow` | `<leader>Ad/AD` | After 90s idle, AI generates a surreal paragraph about your code and types it into a sidebar |
| `synth`        | `:Synth` / `:SynthDemo` | `<leader>Ay` | Maps filetype → macOS system sound on save (Glass for lua, Hero for python, Funk for go, …) |
| `tarot`        | `:Tarot` / `:TarotDraw` | `<leader>At/AT` | 18-card developer tarot deck. Daily card is deterministic by date. |
| `tiny_world`   | `:TinyWorld`  | `<leader>Aw` | Persistent ASCII garden that grows from your saves + commits |
| `rift`         | `:Rift`       | `<leader>Ar` (v) | Visual selection → ripgrep across project → floating "echoes" panel |
| `glyph`        | `:Glyph`      | `<leader>Ag/AG` | Cursor-word → deterministic ASCII sigil as virt_lines below |
| `cipher`       | `:Cipher`     | `<leader>AC` | AES-256-CBC encrypted scratchpad in a float; passphrase via stdin to openssl |
| `seance`       | `:Seance`     | `<leader>AS` | On CursorHold, whispers the git blame author + age + commit subject |
| `homunculus`   | `:HomunculusWake` / `:HomunculusRead` | `<leader>AH/AJ` | AI agent: gathers today's git diff, writes a journal entry, appends to `~/notes/journal/YYYY-MM-DD.md`. Auto-runs on VimLeavePre. |
| `quill`        | `:Quill` / `:QuillReplay` | `<leader>Aq/AQ` | Logs every keystroke with timestamp; replays a past session as a typing animation |
| `summon`       | `:Summon`     | `<leader>Au` | Remembers every plugin window you've opened; pick to recall one you closed |
| `oracle`       | `:Oracle <q>` | `<leader>Ao` | Spinning ASCII coin animation, lands on AI's yes/no answer (or random if no key) |
| `mirror`       | `:Mirror`     | `<leader>AM` | Vertical split with the source file rendered upside-down + characters reversed, live-synced |

### Setup requirements per module

| Module | Needs |
|---|---|
| `ai_cmd`, `explain`, `dreams`, `haiku`, `oracle`, `homunculus` | `ANTHROPIC_API_KEY` |
| `cipher` | `openssl` (preinstalled on macOS) |
| `seance`, `heatmap`, `timetravel`, `today`, `homunculus`, `contribcal` | git repo |
| `coverage` | A `coverage.xml` / `lcov.info` in the project |
| `synth` | macOS (`afplay` + system sounds) or Linux (`paplay`/`canberra-gtk-play`) |
| `webhook` | nothing — `vim.uv.new_tcp` builds the server itself |
| `tsplay`, `symtree`, `glyph`, `synesthesia` | LSP attached (for symtree) / treesitter parser (for the others) |

---

## Diagnostic tool — `doctor.sh`

`~/.config/nvim/scripts/doctor.sh` runs nvim headless, captures `:checkhealth` + `:messages` + `lazy.stats()`, and surfaces only the actionable issues. Exit code = number of `❌ ERROR` lines.

```bash
./scripts/doctor.sh              # default: issues (errors + warns), grouped
./scripts/doctor.sh stats        # plugin count + startup ms
./scripts/doctor.sh messages     # just :messages
./scripts/doctor.sh health       # full :checkhealth (~10k lines)
./scripts/doctor.sh errors       # only ❌ lines
./scripts/doctor.sh warns        # only ⚠ lines
./scripts/doctor.sh full         # the whole report
./scripts/doctor.sh section snacks   # one plugin's section
```

Polls until the checkhealth buffer stabilizes (≥1s of no growth, 12s max) so async checks complete. Filters out section delimiters intelligently so the long `========` rules don't trip the regex. Use it in any CI gate:

```bash
if ./scripts/doctor.sh issues; then echo "clean"; fi
```

---

## Keymap reference

`<Space>` is leader. Press `<leader>?` for a buffer-aware overview, or `<leader>sk` to search every binding via Telescope.

### Global
| key | action |
|---|---|
| `<leader><space>` / `<leader>ff` | find files (Telescope) |
| `<leader>fg` / `<leader>fr` / `<leader>fb` | git files / recent / buffers |
| `<leader>fy` / `<leader>fY` | Yazi at file / at cwd |
| `<leader>e` / `<leader>E` | Neo-tree toggle / focus |
| `-` | Oil — open parent directory |
| `<C-/>` | toggle terminal (floating) |
| `<C-y>` | resume Yazi |
| `s` / `S` | Flash jump / Flash treesitter |
| `<leader>w` / `<leader>q` | write / quit |
| `<leader>?` | buffer-local which-key overview |

### Search (`<leader>s`)
`sg` live grep · `sw` grep word · `sb` buffer fuzzy · `sd` diagnostics · `sk` keymaps · `sc` commands · `sh` help · `sm` marks · `sr` registers · `sR` project replace (grug-far) · `s.` resume last · `st` todos

### Fast picker — fzf-lua (`<leader>z`)
`zf` files · `zg`/`zG` live grep / resume · `zb` buffers · `zh` help · `zs`/`zS` symbols · `zc` commands · `zr` resume

### LSP / Code (`<leader>c`, plus bare-key navs)
| key | action |
|---|---|
| `gd` `gr` `gI` `gy` `K` | def / refs / impl / type / hover |
| `gpd` `gpr` `gpt` `gpi` | **Glance** peek versions of the above |
| `<leader>cr` `<leader>ca` `<leader>cf` | rename / code action / format |
| `<leader>cs` `<leader>cS` | document / workspace symbols |
| `<leader>cn` / `<leader>cN` | generate docstring / class doc |
| `<leader>cO` | Aerial outline |
| `<leader>cp` | breadcrumb picker (dropbar) |
| `<leader>cy` / `<leader>cY` | CodeSnap selection to clipboard / file |
| `<leader>cP` | paste clipboard image (markdown) |
| `<leader>th` / `<leader>tF` | toggle inlay hints / autoformat |
| `]d` `[d` | next / prev diagnostic |
| `]]` `[[` | next / prev LSP reference (snacks.words) |

### Refactor (`<leader>cr`) — works on visual selection where applicable
| key | action |
|---|---|
| `cre` / `crf` | extract function / to file |
| `crv` | extract variable |
| `cri` / `crI` | inline variable / function |
| `crb` / `crB` | extract block / to file |
| `crp` / `crV` / `crc` | print line / print var / cleanup prints |
| `crm` | refactor menu |

### Multi-cursor (`<leader>m`)
`<leader>m` (n) start at cursor · `<leader>m` (v) start from selection · `mw` word · `mP` pattern · `mc` clear

### AI (`<leader>a`)
| key | action |
|---|---|
| `<M-l>` `<M-]>` `<M-[>` | accept / next / prev Copilot ghost text |
| `<leader>aa` | CopilotChat toggle |
| `<leader>ae ar af ao ad at` | explain / review / fix / optimize / docs / tests |
| `<leader>am` | generate commit message |
| `<leader>aT` `<leader>aA` `<leader>aE` | Avante toggle / ask / edit |

### Git (`<leader>g`)
| key | action |
|---|---|
| `<leader>gn` / `<leader>gN` | Neogit / Neogit floating |
| `<leader>gc` / `<leader>gP` / `<leader>gp` / `<leader>gl` | commit / push / pull / log |
| `<leader>gg` | Fugitive `:Git` |
| `<leader>gG` | Lazygit (floating) |
| `<leader>gV` / `<leader>gh` / `<leader>gH` | Diffview / file history / repo history |
| `<leader>gA` | GitHub Actions panel |
| `]h` `[h` | next / prev hunk |
| `<leader>ghs ghr ghp ghb` | stage / reset / preview / blame hunk |
| `<leader>gxo gxt gxb gxn` | merge conflict: ours / theirs / both / none |
| `<leader>gx]` `<leader>gx[` | next / prev conflict |
| `<leader>gB` | open file/line on GitHub remote |

### GitHub via Octo (`<leader>O`)
`Op` PR list · `OP` new PR · `Oi` issue list · `OI` new issue · `Or` start review · `Oc` PR checks · `Os` search

### Tests (`<leader>t`)
`tn`/`tN` nearest / file · `ts` summary · `to` output · `tO` panel · `td` debug nearest · `tS` stop

### Debug (`<leader>d`)
`db` breakpoint · `dB` conditional · `dc` continue · `di`/`do`/`dO` step in/over/out · `dr` repl · `du` UI · `dl` run last · `dt` terminate

Per-language debug:
- Go: `<leader>dgt` debug test · `<leader>dgl` debug last test
- Python: `<leader>dpt` method · `<leader>dpc` class · `<leader>dps` selection (v)

### Tasks (`<leader>T`)
`Tt` panel · `Tr` run template · `Tc` run shell cmd · `Ta` quick action · `Ti` info · `Tb` build · `Tl`/`Ts` load/save bundle

### Diagnostics / Trouble (`<leader>x`)
`xx` workspace · `xX` buffer · `xs` symbols · `xr` LSP refs · `xq` quickfix · `xQ` Trouble quickfix · `xL` loclist

### Snacks QoL
`<leader>.` scratch · `<leader>S` pick scratch · `<leader>z` zen · `<leader>Z` zen+zoom · `<leader>un` dismiss notifications

### Sessions (`<leader>q`)
`qs` restore cwd session · `ql` restore last · `qd` stop saving

### Harpoon (pinned files)
`<leader>H` add · `<leader>h` menu · `<leader>1..4` jump · `<M-S-N>` / `<M-S-P>` next / prev

### Notes / Pomodoro (`<leader>n`)
| key | action |
|---|---|
| `nn` / `no` / `ns` | new note / open / search |
| `nt` / `ny` / `nT` | today / yesterday / tomorrow |
| `nb` / `nf` / `ng` | backlinks / follow link / tags |
| `nr` / `np` / `nx` | rename / paste image / toggle checkbox |
| `np1` / `np2` / `np3` | pomodoro 25m focus / 5m break / 15m long break |
| `nps` / `nph` / `npS` | stop / hide / show timer |

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
`<leader>mp` browser preview · `<leader>cP` paste image · `<leader>tP` pencil prose mode · `<leader>tw`/`<leader>tW` wordy on/off

### Toggles (`<leader>t`)
`tc` TS context · `tT` Twilight (dim) · `tm` minimap · `tM` focus minimap · `ta` autosave · `tF` autoformat · `th` inlay hints

### Fun
`<leader>Xr` make-it-rain · `<leader>Xg` game-of-life · `<leader>Xs` scramble

---

## The status bar

Reading left to right:

```
  NORMAL   main +3 ~1 -2     7   2   server.go  󰑊 @q   3/47  cmd:foo    fmt-off    pyright,gopls   TS  4.2K sp:2 utf-8     63%  120:34   14:32
└────────┘ └────────────┘ └───────────────┘ └─────────┘ └──────────────────┘ └─────────────┘ └─────────────┘ └──────────────────┘ └───────┘ └───────┘ └────────┘
   mode    branch+diff      diagnostics     macro/search/cmd   pomo/tasks/fmt    Copilot+LSP+TS    file size+indent+enc      progress    location   clock
```

Surfaces in real time:
- **Mode** — colored by vim mode (modicator also tints the line numbers)
- **Branch + diff** — gitsigns counts of added/modified/removed
- **Diagnostics** — error/warn/info/hint counts via LSP
- **File path** — 1-level truncated, with modified `●` and readonly indicators
- **Macro** — `󰑊 @q` while recording
- **Search count** — `n/N` when `/` is active
- **Noice cmd** — current command being built
- **Pomodoro** — `  24:31 focus` from pomo.nvim
- **Overseer tasks** — `󰑮 2  1` (running / failed) — live
- **Autoformat** — `  fmt-off` when disabled
- **Copilot status** — icon color: green=ready, yellow=in-progress, red=warning
- **LSP** — comma-joined list of attached servers (excluding null-ls/copilot)
- **TS** — appears when treesitter highlight is active on this buffer
- **Filesize · indent (sp:N / tab:N) · encoding · fileformat**
- **Progress · location · time** (refresh every 100ms)

Globalstatus is on — one statusline across the whole frame, not per-window.

---

## Layout / where things live

```
~/.config/nvim
├── init.lua                    # entry — loads core, then plugin specs
├── lua/core/
│   ├── options.lua             # vim options, leader, deprecation filter
│   ├── keymaps.lua             # global keymaps
│   ├── autocmds.lua            # highlight on yank, trim whitespace, etc.
│   └── lazy.lua                # lazy.nvim bootstrap + spec loader
│
└── lua/plugins/                # 29 files, ~123 plugins
    ├── colorscheme.lua         # Catppuccin Mocha
    ├── ui.lua                  # lualine, bufferline, noice, notify, alpha, which-key
    ├── visual.lua              # fidget, tiny-inline-diagnostic, incline, scrollbar, twilight
    ├── treesitter.lua          # main branch, textobjects, context, autotag
    ├── lsp.lua                 # Mason + lspconfig + conform + nvim-lint
    ├── completion.lua          # blink.cmp + LuaSnip + copilot source
    │
    ├── copilot.lua             # ghost text + CopilotChat
    ├── avante.lua              # Cursor-style Claude agent
    │
    ├── telescope.lua           # fuzzy finder (primary picker)
    ├── explorer.lua            # Neo-tree + Oil
    ├── yazi.lua                # Yazi TUI file manager
    │
    ├── git.lua                 # gitsigns, diffview, fugitive, lazygit (basics)
    ├── git-advanced.lua        # Neogit, git-conflict, gh-actions
    │
    ├── editor.lua              # mini.*, trouble, flash, ufo, terminal, sessions, colorizer
    ├── extras.lua              # snacks, harpoon, smear-cursor, aerial, dropbar, rainbow, codesnap
    ├── refactor.lua            # refactoring.nvim, multicursors, glance, neogen, symbol-usage
    │
    ├── dap.lua                 # core DAP + DAP-UI + virtual text
    ├── tasks.lua               # overseer (tasks.json parity)
    │
    ├── lang-rust.lua           # rustaceanvim + crates.nvim
    ├── lang-go.lua             # go.nvim + nvim-dap-go
    ├── lang-python.lua         # venv-selector, nvim-dap-python, neotest
    │
    ├── devtools.lua            # dadbod-DB, kulala-REST, octo-GitHub, kubectl, smart-splits
    ├── web.lua                 # live-server, ccc color picker, tailwind-tools
    ├── notebook.lua            # quarto + molten + jupytext (Jupyter, opt-in)
    │
    ├── markdown.lua            # img-clip, markdown-preview
    ├── notes.lua               # obsidian.nvim + pomo
    ├── writing.lua             # pencil, ltex (grammar), wordy
    │
    ├── fun.lua                 # cellular-automaton, mini.map, auto-save, modicator
    ├── terminal-hub.lua        # flatten, fzf-lua, devcontainer, cheat.sh, devdocs
    └── user-modules.lua        # pseudo-plugin spec that loads every lua/user/ module

lua/user/                       # 49 hand-rolled native modules (~9300 LOC)
├── (practical)         yankring · ai_cmd · perfhud · present · workspace · repl · coverage
├── (background)        jobs · heatmap · pulse · webhook · symtree · today
├── (power picker)      spotlight · smartpaste · tsplay · rextest · explain · timetravel · macroreg
├── (cockpit)           cockpit · compass · radar · throttle · checklist · blackbox · warnings · eject
├── (statusline)        starship
├── (artistic)          aurora · matrix · contribcal · constellation · synesthesia · zen · haiku
└── (occult)            dreams · synth · tarot · tiny_world · rift ·
                        glyph · cipher · seance · homunculus ·
                        quill · summon · oracle · mirror

scripts/
└── doctor.sh                   # headless :checkhealth + :messages capture
```

**Mental model — plugins/:** language tooling in `lang-*.lua`, UI in `ui.lua` and `visual.lua`, AI in `copilot.lua`/`avante.lua`, the rest splits by capability domain. Add a plugin by dropping a new file — lazy.nvim discovers it via `{ import = "plugins" }`.

**Mental model — user/:** each file is a single feature. Setup happens in `lua/plugins/user-modules.lua`'s `config = function()` block which requires every user module's `setup()`. Add a new module by writing `lua/user/<name>.lua` with a `setup()` that registers commands/autocmds, then add `require("user.<name>").setup()` to user-modules.lua and (optionally) a keymap entry in its `keys = {...}`.

---

## Customization tips

- **Change colorscheme** — edit `lua/plugins/colorscheme.lua` and the `theme = "catppuccin-mocha"` line in `lua/plugins/ui.lua` (lualine section). Note the theme name must match a file in `lua/lualine/themes/`; for Catppuccin that's `catppuccin-{mocha,latte,frappe,macchiato}`, *not* bare `catppuccin`.
- **Add a language** — append to `ensure_installed` in `lua/plugins/lsp.lua` (LSP), `lua/plugins/treesitter.lua` (parsers), and `lua/plugins/lsp.lua` formatters_by_ft for conform.
- **Add a custom snippet** — drop `.json` / `.code-snippets` files in `~/.config/nvim/snippets/` (auto-loaded by LuaSnip via friendly-snippets loader).
- **Point Obsidian at an existing vault** — edit the `workspaces` table in `lua/plugins/notes.lua`.
- **Disable a plugin** — set `enabled = false` on its spec, or comment out its file.
- **Pin a plugin version** — add `version = "x.y.z"` or `commit = "abc1234"` to its spec.

---

## Troubleshooting

**First step for any weirdness:** `./scripts/doctor.sh issues` — surfaces actionable items only, exit code = error count.

| Symptom | Fix |
|---|---|
| "I don't know what's broken" | Run `./scripts/doctor.sh issues` |
| Wall of treesitter errors on open | You're missing the tree-sitter CLI. `brew install tree-sitter-cli` then `:TSUpdate` |
| Icons look broken / question marks | Set your terminal font to a Nerd Font (`brew install --cask font-jetbrains-mono-nerd-font`) |
| `:checkhealth` complains about `magick` | Optional — only for `image.nvim` which is disabled in this config. Snacks.image handles inline images natively |
| Copilot says "not authenticated" | Run `:Copilot auth` and follow the OAuth link |
| Avante doesn't work | `echo $ANTHROPIC_API_KEY` — must be exported in your shell rc |
| LSP not attaching | `:Mason` — ensure the relevant server shows ◍ (installed). `:LspInfo` shows what's attached |
| LSP log growing huge | Already capped at WARN in `core/options.lua`. Truncate manually: `: > ~/.local/state/nvim/lsp.log` |
| Slow startup | `:Lazy profile` shows time per plugin. Most heavyweight plugins here are `event=VeryLazy` / `cmd` / `ft` lazy-loaded |
| Want to nuke and restart | `rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim` (your config in `~/.config/nvim` survives) |

---

Backups of any prior config land in `~/.config/nvim.bak-<timestamp>` — restore with `mv ~/.config/nvim.bak-<ts> ~/.config/nvim` if you want to roll back.
