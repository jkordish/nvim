# nvim — banger config

A modern Neovim setup built on lazy.nvim. Catppuccin Mocha, native LSP via Mason,
Treesitter with context highlighting, blink.cmp completion, Copilot inline +
CopilotChat + Avante (Claude), Telescope, Neo-tree, Gitsigns/Diffview/Lazygit,
Trouble, Flash, UFO folds.

## Install — one shot

Copy-paste this whole block. Safe to re-run; brew skips what's installed.

```bash
# ─── REQUIRED: editor + tools the config depends on ───
brew install neovim ripgrep fd tree-sitter tree-sitter-cli git node

# ─── HIGHLY RECOMMENDED (lots of features use these) ───
brew install lazygit pngpaste yazi gh jq
brew install --cask font-jetbrains-mono-nerd-font   # nerd font for icons
brew install --cask ghostty                          # for inline image rendering

# ─── LANGUAGE TOOLCHAINS (install only what you write) ───
brew install python go rustup                        # python + go + rust
rustup-init -y                                       # finishes rust install
brew install --cask docker                           # devcontainer.nvim

# ─── OPTIONAL: notebook support (Quarto + Molten) ───
brew install quarto
pip install --user pynvim jupyter_client cairosvg pnglatex plotly kaleido pyperclip nbformat
# then in nvim:  :UpdateRemotePlugins  + restart

# ─── OPTIONAL: devdocs preview renderer ───
brew install glow
```

## After install

```bash
nvim                      # lazy.nvim bootstraps + installs every plugin
# wait for :Lazy to finish; first launch takes ~60s

# inside nvim:
:Mason                    # auto-installs all LSPs/formatters/linters/DAP adapters
:checkhealth              # confirm everything is green

# auth:
:Copilot auth             # GitHub Copilot
gh auth login             # Octo (GitHub PRs/issues from your shell)

# Avante (Claude) — add to ~/.zshrc:
export ANTHROPIC_API_KEY=sk-ant-...
```

## What Mason handles for you (no brew needed)

Run `:Mason` once and these install automatically:

**LSPs:** `lua_ls`, `pyright`, `ruff`, `vtsls`, `eslint`, `gopls`, `bashls`, `jsonls`,
`yamlls`, `marksman`, `taplo`, `dockerls`, `emmet_language_server`, `tailwindcss`, `ltex` ·
**Formatters:** `stylua`, `shfmt`, `prettierd`, `black`, `isort`, `goimports` ·
**Linters:** `shellcheck`, `hadolint`, `markdownlint` ·
**DAP:** `debugpy`, `codelldb`, `delve`, `js-debug-adapter` ·
**Rust:** `rust_analyzer` installed by rustaceanvim, not Mason.

## Per-feature setup

| Feature | What you need beyond the brew block |
|---|---|
| Copilot | `:Copilot auth` |
| Avante (Claude) | `export ANTHROPIC_API_KEY=...` in shell rc |
| Octo / gh-actions | `gh auth login` |
| Lazygit (`<leader>gG`) | included in brew block |
| Yazi file manager (`<leader>fy`) | included in brew block |
| Inline images in markdown | Ghostty/WezTerm/Kitty terminal + Snacks.image (built-in, no install) |
| Markdown preview (`<leader>mp`) | node from brew block — plugin builds itself |
| Live server (`<leader>Wl`) | auto-installs `live-server` via npm |
| Database UI (`<leader>D`) | nothing extra; add connections via `:DBUIAddConnection` |
| REST client (`.http` files) | nothing extra |
| Devcontainers (`<leader>C`) | Docker Desktop or compatible runtime |
| Jupyter notebooks | the optional notebook block above; plugins stay dormant until then |
| Obsidian (`<leader>n*`) | nothing — `~/notes/{inbox,daily,assets}` auto-created on first launch. Edit `lua/plugins/notes.lua` to point at an existing vault. |
| cheat.sh (`<leader>?h`) | internet |
| devdocs (`<leader>?d`) | `glow` from optional block; pre-fetch with `:DevdocsFetch <slug>` |

## Verifying you're set up

```vim
:checkhealth              " everything green except the 'optional' items you skipped
:Lazy                     " all plugins should show ●  not ⏳
:Mason                    " LSPs/tools should all show ◍ (installed)
```

## Leader = Space

### General
| key | action |
|---|---|
| `<leader><space>` | find files |
| `<leader>w` / `<leader>q` | write / quit |
| `<leader>e` | toggle Neo-tree |
| `-` | open parent dir (Oil) |
| `<C-/>` | toggle terminal |
| `s` / `S` | Flash jump / Flash treesitter |

### Find / Search (`<leader>f` / `<leader>s`)
| key | action |
|---|---|
| `ff` / `fg` / `fr` / `fb` | files / git files / recent / buffers |
| `sg` / `sw` / `sb` | live grep / word / current buffer |
| `sd` / `sk` / `sc` | diagnostics / keymaps / commands |
| `sR` | project search & replace (grug-far) |

### LSP / Code (`<leader>c`)
| key | action |
|---|---|
| `gd` `gr` `gI` `gy` `K` | def / refs / impl / type / hover |
| `<leader>cr` `<leader>ca` `<leader>cf` | rename / code action / format |
| `<leader>cs` `<leader>cS` | document / workspace symbols |
| `<leader>th` `<leader>tF` | toggle inlay hints / autoformat |
| `]d` `[d` | next / prev diagnostic |

### Git (`<leader>g`)
| key | action |
|---|---|
| `<leader>gg` | Fugitive |
| `<leader>gG` | Lazygit (floating) |
| `<leader>gd` `<leader>gV` `<leader>gh` | diff this / Diffview / file history |
| `]h` `[h` | next / prev hunk |
| `<leader>ghs` `<leader>ghr` `<leader>ghp` `<leader>ghb` | stage / reset / preview / blame |

### AI (`<leader>a`)
| key | action |
|---|---|
| `<M-l>` | accept Copilot suggestion (insert) |
| `<M-]>` / `<M-[>` | next / prev suggestion |
| `<leader>aa` | CopilotChat toggle |
| `<leader>ae` `ar` `af` `ao` `ad` `at` | explain / review / fix / optimize / docs / tests |
| `<leader>am` | generate commit message |
| `<leader>aT` `<leader>aA` `<leader>aE` | Avante toggle / ask / edit |

### Diagnostics / Trouble (`<leader>x`)
| key | action |
|---|---|
| `xx` `xX` | workspace / buffer diagnostics |
| `xs` `xr` | symbols / LSP refs |
| `xq` `xQ` | open quickfix / Trouble quickfix |

### Debug (`<leader>d`)
`db` breakpoint · `dc` continue · `di/do/dO` step in/over/out · `du` UI · `dr` repl

### Sessions (`<leader>q`)
`qs` restore cwd session · `ql` restore last · `qd` stop saving

### Harpoon (pinned files)
| key | action |
|---|---|
| `<leader>H` | add current file to harpoon |
| `<leader>h` | show harpoon menu |
| `<leader>1..4` | jump to pinned file 1-4 |
| `<M-S-N>` / `<M-S-P>` | next / prev pinned file |

### Snacks (folke's QoL)
| key | action |
|---|---|
| `<leader>.` / `<leader>S` | scratch buffer / pick scratch |
| `<leader>z` / `<leader>Z` | zen mode / zen + zoom |
| `<leader>gB` | open file/line on GitHub |
| `<leader>un` | dismiss notifications |
| `]]` / `[[` | next / prev LSP reference |

### Windows & outline
| key | action |
|---|---|
| `<leader>wp` / `<leader>ws` | pick window / swap window |
| `<leader>cO` | toggle Aerial outline |
| `<leader>cp` | pick from breadcrumb (dropbar) |
| `<leader>cy` / `<leader>cY` | CodeSnap selection to clipboard / file |
| `<leader>tT` | toggle Twilight (dim non-focused code) |

### Language-specific

**Rust** (via `rustaceanvim` — overrides `K`/`<leader>c*` in rust buffers)
| key | action |
|---|---|
| `K` | hover with code actions |
| `<leader>cR` / `<leader>cE` | rust code action / expand macro |
| `<leader>cC` / `<leader>cP` | open Cargo.toml / parent module |
| `<leader>tr` / `<leader>tD` | runnables / debuggables picker |

**Go** (via `go.nvim` — only active in go buffers)
| key | action |
|---|---|
| `<leader>cgt` / `<leader>cgT` | add / remove struct tags |
| `<leader>cgi` | impl interface |
| `<leader>cgf` / `<leader>cgs` | fill struct / fill switch |
| `<leader>cge` | add `if err != nil` block |
| `<leader>cgr` | `go run` |
| `<leader>dgt` / `<leader>dgl` | debug nearest test / debug last test |

**Python**
| key | action |
|---|---|
| `<leader>cv` | select venv (auto-detects .venv/poetry/conda/pyenv) |
| `<leader>dpt` / `<leader>dpc` | debug method / class |
| `<leader>dps` | debug selection (visual) |

**Neotest** (Go, Rust, Python — same keymap surface)
| key | action |
|---|---|
| `<leader>tn` / `<leader>tN` | run nearest / file |
| `<leader>ts` / `<leader>to` / `<leader>tO` | summary / output / panel |
| `<leader>td` | debug nearest test |
| `<leader>tS` | stop |

### Dev tools

**Database** — `<leader>D` opens dadbod-UI side panel; write SQL, run with `<leader>S` inside a .sql buffer. Add connections via `:DBUIAddConnection`.

**REST client** — open a `.http` file, place cursor in a request block:
| key | action |
|---|---|
| `<leader>Rs` / `<leader>Ra` | send current / send all |
| `<leader>Rl` / `<leader>RI` | replay last / inspect |
| `<leader>Rn` / `<leader>Rp` | next / prev request |
| `<leader>Rc` / `<leader>Rf` | copy as curl / paste from curl |

**GitHub** (Octo — uses your `gh auth`):
| key | action |
|---|---|
| `<leader>Op` / `<leader>OP` | list PRs / new PR |
| `<leader>Oi` / `<leader>OI` | list issues / new issue |
| `<leader>Or` / `<leader>Oc` | start review / view checks |
| `<leader>Os` | search |

**Kubernetes** — `<leader>k` opens kubectl panel (pods, logs, exec, port-forward).

**Projects** — `<leader>fp` lists known projects (auto-detected by .git/Cargo.toml/go.mod/etc).

**Splits** — `<A-h/j/k/l>` jumps across nvim splits AND tmux/wezterm panes; add `<S>` to resize.

### Refactor (`<leader>cr` / `<leader>m`)

| key | action |
|---|---|
| `<leader>cre` | extract function (visual) |
| `<leader>crf` | extract function to file |
| `<leader>crv` | extract variable (visual) |
| `<leader>cri` / `<leader>crI` | inline variable / inline function |
| `<leader>crb` / `<leader>crB` | extract block / to file |
| `<leader>crp` / `<leader>crV` / `<leader>crc` | print line / print var / cleanup |
| `<leader>crm` | refactor menu |
| `<leader>cn` / `<leader>cN` | generate docstring / class doc |
| `<leader>m` (n/v) | start multicursor / from selection |
| `<leader>mw` / `<leader>mP` / `<leader>mc` | word / pattern / clear |
| `gpd` `gpr` `gpt` `gpi` | Glance peek def/refs/type/impl |

### Markdown
| key | action |
|---|---|
| `<leader>mp` | live markdown preview (browser) |
| `<leader>cP` | paste clipboard image into buffer |

Image rendering, headlined headers, and live preview all activate on `.md` filetypes.

### Fun / extras
| key | action |
|---|---|
| `<leader>Xr` / `<leader>Xg` / `<leader>Xs` | make-it-rain / game-of-life / scramble |
| `<leader>tm` / `<leader>tM` | toggle / focus minimap |
| `<leader>ta` | toggle autosave |

---

## VSCode replacement layer

### Git, the magit way (`<leader>g`)
| key | action |
|---|---|
| `<leader>gn` / `<leader>gN` | Neogit / Neogit floating |
| `<leader>gc` / `<leader>gP` / `<leader>gp` | commit / push / pull |
| `<leader>gl` | log graph |
| `<leader>gA` | GitHub Actions panel |
| `<leader>gxo` / `gxt` / `gxb` / `gxn` | merge conflict: take ours/theirs/both/none |
| `<leader>gx]` / `<leader>gx[` | next / prev conflict |

### Tasks runner — VSCode `tasks.json` parity (`<leader>T`)
| key | action |
|---|---|
| `<leader>Tt` / `<leader>Tr` / `<leader>Tc` | task panel toggle / run template / run shell cmd |
| `<leader>Ta` / `<leader>Ti` / `<leader>Tb` | quick action / info / build |
| `<leader>Tl` / `<leader>Ts` | load / save task bundle |

Status bar shows live counts: `󰑮 running` /  ` failed` /  ` ok`.

### Jupyter notebooks (`<leader>Q` Quarto / `<leader>J` Molten kernel)
| key | action |
|---|---|
| `<leader>Qp` / `<leader>Qq` | Quarto preview / stop |
| `<leader>Qa` / `<leader>Qh` | activate / help |
| `<leader>Qe` / `<leader>QE` / `<leader>Qr` | run above / all / from cursor |
| `<leader>Ji` | init Molten kernel for buffer |
| `<leader>Je` (n) / `<leader>Jr` (v) | eval operator / eval selection |
| `<leader>Jl` / `<leader>Jc` | eval line / re-eval cell |
| `<leader>Jh` / `<leader>Jo` | hide output / enter output window |
| `<leader>Jd` | delete output |

`.ipynb` files auto-convert to markdown for editing via jupytext.

### Notes / second brain (`<leader>n`)
| key | action |
|---|---|
| `<leader>nn` / `<leader>no` / `<leader>ns` | new note / open / search |
| `<leader>nt` / `<leader>ny` / `<leader>nT` | today / yesterday / tomorrow |
| `<leader>nb` / `<leader>nf` / `<leader>ng` | backlinks / follow link / tags |
| `<leader>nr` / `<leader>np` / `<leader>nx` | rename / paste image / toggle checkbox |
| `<leader>np1` / `<leader>np2` / `<leader>np3` | pomodoro: 25m focus / 5m break / 15m long break |
| `<leader>nps` / `<leader>nph` / `<leader>npS` | stop / hide / show timer |

Active pomodoro renders in the statusline (peach color).

### File manager (`<leader>f`)
| key | action |
|---|---|
| `<leader>fy` / `<leader>fY` | Yazi at file / cwd |
| `<C-y>` | resume yazi |

### Web / frontend (`<leader>W`)
| key | action |
|---|---|
| `<leader>Wl` | live-server toggle (browser auto-reload) |
| `<leader>Wp` / `<leader>Wc` | color picker / convert color |

Emmet + Tailwind LSP attach automatically in HTML/CSS/JSX/TSX/Vue/Svelte/Astro buffers.

### Devcontainer (`<leader>C`) — VSCode Remote Containers parity
| key | action |
|---|---|
| `<leader>Cu` / `<leader>Cd` | up / down |
| `<leader>Ca` / `<leader>Cx` | attach / exec |
| `<leader>Cl` | logs |

### Lookups & docs (`<leader>?`)
| key | action |
|---|---|
| `<leader>?h` | cheat.sh quick lookup |
| `<leader>?d` / `<leader>?D` | devdocs for current ft / search |

### Alternate fast picker (`<leader>z`)
fzf-lua, faster than Telescope for huge repos:
`zf` files · `zg`/`zG` live grep / resume · `zb` buffers · `zh` help · `zs`/`zS` doc/workspace symbols · `zc` commands

### Writing (`<leader>tP/tw/tW`)
| key | action |
|---|---|
| `<leader>tP` | toggle pencil prose mode (soft wrap + smart j/k) |
| `<leader>tw` / `<leader>tW` | wordy: weak words / off |

ltex-ls auto-attaches in `markdown`/`tex`/`text`/`gitcommit` for grammar checking.

## Layout

```
~/.config/nvim
├── init.lua                    # entry
├── lua/core/                   # options, keymaps, autocmds, lazy bootstrap
└── lua/plugins/                # one file per concern
    ├── colorscheme.lua         # Catppuccin Mocha
    ├── ui.lua                  # lualine, bufferline, noice, notify, alpha, which-key, indent
    ├── treesitter.lua          # parsers + textobjects + context + autotag
    ├── lsp.lua                 # Mason + lspconfig + conform (format) + nvim-lint
    ├── completion.lua          # blink.cmp + LuaSnip + copilot source
    ├── copilot.lua             # copilot.lua (ghost text) + CopilotChat
    ├── avante.lua              # Avante (Claude) Cursor-style agent
    ├── telescope.lua           # fuzzy finder
    ├── explorer.lua            # Neo-tree + Oil
    ├── git.lua                 # gitsigns, diffview, fugitive, lazygit
    ├── editor.lua              # mini.*, trouble, flash, ufo, terminal, sessions, colorizer
    ├── dap.lua                 # debug adapter protocol
    ├── extras.lua              # snacks, harpoon, smear-cursor, aerial, dropbar, rainbow, codesnap
    ├── visual.lua              # fidget, tiny-inline-diagnostic, incline, scrollbar, twilight
    ├── lang-rust.lua           # rustaceanvim + crates.nvim
    ├── lang-go.lua             # go.nvim + nvim-dap-go
    ├── lang-python.lua         # venv-selector + nvim-dap-python + neotest
    ├── devtools.lua            # dadbod-DB, kulala-REST, octo-GitHub, kubectl, project, smart-splits
    ├── refactor.lua            # refactoring.nvim, multicursors, glance, neogen, symbol-usage
    ├── markdown.lua            # image.nvim, img-clip, headlines, markdown-preview
    ├── fun.lua                 # cellular-automaton, mini.map, auto-save, modicator
    ├── git-advanced.lua        # neogit, git-conflict, gh-actions
    ├── tasks.lua               # overseer (VSCode tasks.json parity)
    ├── notebook.lua            # quarto + molten + jupytext (Jupyter)
    ├── notes.lua               # obsidian.nvim + pomo
    ├── yazi.lua                # yazi.nvim TUI file manager
    ├── web.lua                 # live-server, ccc color picker, tailwind-tools
    ├── writing.lua             # pencil, ltex (grammar), wordy
    └── terminal-hub.lua        # flatten, fzf-lua, devcontainer, cheat.sh, devdocs
```

Backups of prior config land in `~/.config/nvim.bak-<timestamp>`.
