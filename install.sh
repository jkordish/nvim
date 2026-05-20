#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# install.sh — bootstrap this Neovim config on macOS or Ubuntu LTS.
# Idempotent: safe to re-run. Pass --help for flags.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── colors / ui ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; MAGENTA=$'\e[35m'; CYAN=$'\e[36m'
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""
fi
say()    { printf '%s\n' "$*"; }
info()   { printf '%s%s ▸%s %s\n' "$BOLD" "$BLUE"  "$RESET" "$*"; }
ok()     { printf '%s%s ✓%s %s\n' "$BOLD" "$GREEN" "$RESET" "$*"; }
warn()   { printf '%s%s ⚠%s %s\n' "$BOLD" "$YELLOW" "$RESET" "$*" >&2; }
err()    { printf '%s%s ✗%s %s\n' "$BOLD" "$RED"   "$RESET" "$*" >&2; }
step()   { printf '\n%s%s═══ %s ═══%s\n\n' "$BOLD" "$MAGENTA" "$*" "$RESET"; }
banner() {
  printf '%s' "$CYAN"
  cat <<'BANNER'
   ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗
   ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║
   ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║
   ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║
   ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║
   ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝   banger config
BANNER
  printf '%s\n' "$RESET"
}

# ─── flags ───────────────────────────────────────────────────────────────────
ASSUME_YES=0      # --yes        skip prompts, accept all
MINIMAL=0         # --minimal    only REQUIRED + nvim bootstrap
SKIP_SYSTEM=0     # --skip-system  only run nvim plugin bootstrap
SKIP_BOOTSTRAP=0  # --skip-bootstrap  only install OS deps
DRY_RUN=0         # --dry-run    print commands, don't execute

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} ./install.sh [flags]

Sets up the system deps + Mason tools + Treesitter parsers required by this
Neovim config. Works on macOS (via Homebrew) and Ubuntu LTS (via apt + fallbacks).

${BOLD}Flags:${RESET}
  --yes              Accept every prompt (unattended install)
  --minimal          Only install REQUIRED tools, skip recommended + languages
  --skip-system      Skip OS package installs, only bootstrap nvim plugins
  --skip-bootstrap   Skip nvim plugin bootstrap, only install OS deps
  --dry-run          Print what would run, don't execute
  -h, --help         Show this help

${BOLD}Examples:${RESET}
  ./install.sh                       # interactive, recommended path
  ./install.sh --yes                 # fully unattended
  ./install.sh --minimal --yes       # quick start, no extras
  ./install.sh --skip-system         # re-bootstrap plugins after config change
EOF
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --yes|-y)         ASSUME_YES=1 ;;
    --minimal)        MINIMAL=1 ;;
    --skip-system)    SKIP_SYSTEM=1 ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help)        usage ;;
    *) err "unknown flag: $arg"; usage ;;
  esac
done

# ─── helpers ─────────────────────────────────────────────────────────────────
run() {
  if (( DRY_RUN )); then
    printf '%s$%s %s\n' "$DIM" "$RESET" "$*"
  else
    "$@"
  fi
}

confirm() {
  # confirm "Install X?"  → returns 0 yes, 1 no
  local prompt="${1:-Continue?}"
  (( ASSUME_YES )) && return 0
  local yn
  read -r -p "  $prompt [Y/n] " yn
  [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

# ─── os detection ────────────────────────────────────────────────────────────
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian|pop|linuxmint) echo "ubuntu" ;;
      *) echo "unsupported:${ID:-unknown}" ;;
    esac
  else
    echo "unsupported:unknown"
  fi
}

OS="$(detect_os)"

# ─── ensure package manager ──────────────────────────────────────────────────
ensure_pkg_mgr() {
  case "$OS" in
    macos)
      if ! have brew; then
        info "Installing Homebrew (you'll be prompted for sudo)…"
        run bash -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        # New Homebrew on Apple Silicon installs to /opt/homebrew; add to PATH.
        if [[ -x /opt/homebrew/bin/brew ]]; then
          eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
          eval "$(/usr/local/bin/brew shellenv)"
        fi
      fi
      ok "Homebrew ready: $(brew --version | head -1)"
      ;;
    ubuntu)
      info "Updating apt index…"
      run sudo apt-get update -qq
      ok "apt ready"
      ;;
    *)
      err "Unsupported OS: $OS"
      err "Supported: macOS (any), Ubuntu/Debian/Pop/Mint LTS"
      exit 1
      ;;
  esac
}

# ─── pkg install helpers ─────────────────────────────────────────────────────
brew_install() {
  for pkg in "$@"; do
    if brew list --formula "$pkg" >/dev/null 2>&1 || brew list --cask "$pkg" >/dev/null 2>&1; then
      ok "$pkg already installed"
    else
      info "brew install $pkg"
      run brew install "$pkg" || warn "brew install $pkg failed"
    fi
  done
}

brew_cask() {
  for pkg in "$@"; do
    if brew list --cask "$pkg" >/dev/null 2>&1; then
      ok "$pkg (cask) already installed"
    else
      info "brew install --cask $pkg"
      run brew install --cask "$pkg" || warn "brew install --cask $pkg failed"
    fi
  done
}

apt_install() {
  local missing=()
  for pkg in "$@"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      ok "$pkg already installed"
    else
      missing+=("$pkg")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    info "apt install ${missing[*]}"
    run sudo apt-get install -y -qq "${missing[@]}"
  fi
}

# ─── nvim install (the one tricky case on ubuntu) ────────────────────────────
install_nvim_macos() { brew_install neovim; }

install_nvim_ubuntu() {
  # Ubuntu's apt repos rarely have nvim 0.11+. Use the official AppImage.
  if have nvim && nvim --version | head -1 | grep -qE 'v0\.(1[1-9]|[2-9][0-9])'; then
    ok "nvim already installed: $(nvim --version | head -1)"
    return
  fi
  info "Installing latest stable Neovim from official AppImage"
  local url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  run curl -fsSL "$url" -o "$tmp/nvim.tgz"
  run tar -xzf "$tmp/nvim.tgz" -C "$tmp"
  run sudo rm -rf /opt/nvim
  run sudo mv "$tmp"/nvim-linux64 /opt/nvim
  run sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
  rm -rf "$tmp"
  ok "Neovim installed: $(nvim --version | head -1)"
}

install_neovim() {
  case "$OS" in
    macos)  install_nvim_macos ;;
    ubuntu) install_nvim_ubuntu ;;
  esac
}

# ─── REQUIRED tools ──────────────────────────────────────────────────────────
install_required() {
  step "REQUIRED packages"
  install_neovim
  case "$OS" in
    macos)
      brew_install ripgrep fd git node tree-sitter tree-sitter-cli jq curl wget
      ;;
    ubuntu)
      apt_install ripgrep fd-find git nodejs npm jq curl wget build-essential pkg-config
      # apt's fd binary is `fdfind` — symlink for the world's sanity
      if have fdfind && ! have fd; then
        info "Symlinking fdfind → fd in /usr/local/bin"
        run sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
      fi
      # tree-sitter & cli aren't in apt; install via cargo OR npm OR github release
      if ! have tree-sitter; then
        if have cargo; then
          info "cargo install tree-sitter-cli"
          run cargo install tree-sitter-cli
        elif have npm; then
          info "npm install -g tree-sitter-cli"
          run sudo npm install -g tree-sitter-cli
        else
          warn "Need cargo or npm for tree-sitter-cli; install one and re-run"
        fi
      else
        ok "tree-sitter-cli already installed"
      fi
      ;;
  esac
}

# ─── HIGHLY RECOMMENDED ──────────────────────────────────────────────────────
install_recommended() {
  step "RECOMMENDED packages"
  case "$OS" in
    macos)
      brew_install lazygit yazi gh pngpaste
      brew_cask font-jetbrains-mono-nerd-font
      ;;
    ubuntu)
      # lazygit via official PPA / github release
      if ! have lazygit; then
        info "Installing lazygit from GitHub release"
        local v; v="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r .tag_name | sed 's/^v//')"
        local arch; arch="$(uname -m)"
        case "$arch" in x86_64) arch="x86_64" ;; aarch64|arm64) arch="arm64" ;; esac
        local tmp; tmp="$(mktemp -d)"
        run curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${v}/lazygit_${v}_Linux_${arch}.tar.gz" -o "$tmp/lg.tgz"
        run tar -xzf "$tmp/lg.tgz" -C "$tmp" lazygit
        run sudo install -m 0755 "$tmp/lazygit" /usr/local/bin/lazygit
        rm -rf "$tmp"
      else
        ok "lazygit already installed"
      fi
      # yazi via prebuilt binary or cargo fallback
      if ! have yazi; then
        if have cargo; then
          info "cargo install yazi-fm yazi-cli (this may take a few minutes)"
          run cargo install --locked yazi-fm yazi-cli
        else
          warn "yazi requires cargo — skipping. Install rust to get it."
        fi
      else
        ok "yazi already installed"
      fi
      # gh via official Debian repo
      if ! have gh; then
        info "Installing GitHub CLI from official apt repo"
        run sudo mkdir -p -m 755 /etc/apt/keyrings
        run bash -c 'wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null'
        run sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        run bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null'
        run sudo apt-get update -qq
        apt_install gh
      else
        ok "gh already installed"
      fi
      # xclip for the clipboard (no pngpaste on linux; img-clip falls back to xclip)
      apt_install xclip wl-clipboard
      # Nerd font via getnf or manual download
      info "Nerd Font installation"
      shopt -s nullglob nocaseglob
      local _nf_glob=("$HOME/.local/share/fonts"/*jetbrains*nerd*)
      shopt -u nullglob nocaseglob
      if (( ${#_nf_glob[@]} > 0 )); then
        ok "JetBrainsMono Nerd Font already installed"
      else
        if confirm "Download JetBrainsMono Nerd Font?"; then
          info "Downloading and installing JetBrainsMono Nerd Font"
          local tmp; tmp="$(mktemp -d)"
          run curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$tmp/nf.zip"
          run mkdir -p "$HOME/.local/share/fonts"
          run unzip -oq "$tmp/nf.zip" -d "$HOME/.local/share/fonts"
          run fc-cache -f
          rm -rf "$tmp"
          ok "JetBrainsMono Nerd Font installed; set it as your terminal font"
        fi
      fi
      ;;
  esac
}

# ─── LANGUAGE TOOLCHAINS (interactive) ───────────────────────────────────────
install_languages() {
  step "LANGUAGE TOOLCHAINS"
  say "    Pick which languages you write — installs their toolchain so the"
  say "    matching LSP/formatter/linter/DAP works out of the box."
  echo

  if confirm "Install Python (python3 + pip)?"; then
    case "$OS" in
      macos)  brew_install python ;;
      ubuntu) apt_install python3 python3-pip python3-venv ;;
    esac
  fi

  if confirm "Install Go?"; then
    case "$OS" in
      macos)  brew_install go ;;
      ubuntu)
        # apt's golang is sometimes old; the official tarball is safer
        if ! have go; then
          info "Installing Go from official release"
          local v; v="$(curl -fsSL https://go.dev/VERSION?m=text | head -1 | sed 's/^go//')"
          local arch; arch="$(uname -m)"
          case "$arch" in x86_64) arch="amd64" ;; aarch64|arm64) arch="arm64" ;; esac
          local tmp; tmp="$(mktemp -d)"
          run curl -fsSL "https://go.dev/dl/go${v}.linux-${arch}.tar.gz" -o "$tmp/go.tgz"
          run sudo rm -rf /usr/local/go
          run sudo tar -C /usr/local -xzf "$tmp/go.tgz"
          run sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
          run sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
          rm -rf "$tmp"
        else
          ok "go already installed"
        fi
        ;;
    esac
  fi

  if confirm "Install Rust (rustup + cargo + clippy)?"; then
    if have rustc; then
      ok "rust already installed"
    else
      case "$OS" in
        macos)
          brew_install rustup
          run rustup-init -y --no-modify-path
          ;;
        ubuntu)
          info "Installing rust via rustup"
          run bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path'
          ;;
      esac
      # Ensure ~/.cargo/bin in PATH for this script's remaining steps
      export PATH="$HOME/.cargo/bin:$PATH"
    fi
  fi

  if confirm "Install Docker (for devcontainer.nvim)?"; then
    case "$OS" in
      macos)  brew_cask docker ;;
      ubuntu)
        if have docker; then
          ok "docker already installed"
        else
          info "Installing docker.io via apt"
          apt_install docker.io docker-compose-v2
          run sudo usermod -aG docker "$USER"
          warn "Log out + back in for docker group membership to take effect"
        fi
        ;;
    esac
  fi
}

# ─── OPTIONAL extras ─────────────────────────────────────────────────────────
install_optional() {
  step "OPTIONAL extras"

  if confirm "Install Ghostty terminal (for inline image rendering)?"; then
    case "$OS" in
      macos)  brew_cask ghostty ;;
      ubuntu)
        warn "Ghostty has no official deb yet — skipping. Build from source or wait for upstream packaging."
        ;;
    esac
  fi

  if confirm "Install Jupyter stack (Quarto + Molten notebook support)?"; then
    case "$OS" in
      macos)  brew_install quarto ;;
      ubuntu)
        if ! have quarto; then
          info "Installing Quarto from GitHub release"
          local v; v="$(curl -fsSL https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest | jq -r .tag_name | sed 's/^v//')"
          local arch; arch="$(uname -m)"
          case "$arch" in x86_64) arch="amd64" ;; aarch64|arm64) arch="arm64" ;; esac
          local tmp; tmp="$(mktemp -d)"
          run curl -fsSL "https://github.com/quarto-dev/quarto-cli/releases/download/v${v}/quarto-${v}-linux-${arch}.deb" -o "$tmp/quarto.deb"
          run sudo dpkg -i "$tmp/quarto.deb" || sudo apt-get install -fy
          rm -rf "$tmp"
        fi
        ;;
    esac
    if have pip3 || have pip; then
      local pip; pip="$(command -v pip3 || command -v pip)"
      info "Installing Python notebook dependencies"
      run "$pip" install --user --quiet pynvim jupyter_client cairosvg pnglatex plotly kaleido pyperclip nbformat
    else
      warn "pip not available — skipping Python notebook deps. Install Python first."
    fi
  fi

  if confirm "Install glow (for devdocs preview rendering)?"; then
    case "$OS" in
      macos)  brew_install glow ;;
      ubuntu)
        if ! have glow; then
          info "Installing glow from GitHub release"
          local v; v="$(curl -fsSL https://api.github.com/repos/charmbracelet/glow/releases/latest | jq -r .tag_name | sed 's/^v//')"
          local arch; arch="$(uname -m)"
          case "$arch" in x86_64) arch="amd64" ;; aarch64|arm64) arch="arm64" ;; esac
          local tmp; tmp="$(mktemp -d)"
          run curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v${v}/glow_${v}_Linux_${arch}.tar.gz" -o "$tmp/glow.tgz"
          run tar -xzf "$tmp/glow.tgz" -C "$tmp"
          run sudo install -m 0755 "$tmp/glow" /usr/local/bin/glow
          rm -rf "$tmp"
        fi
        ;;
    esac
  fi

  # kubectl CLI itself (kubectl.nvim needs it to actually contact a cluster;
  # the plugin's bundled Rust client is the API layer, kubectl is the auth
  # config + kubeconfig parser).
  if confirm "Install kubectl + kubediff CLIs (for kubectl.nvim panel)?"; then
    case "$OS" in
      macos)
        brew_install kubectl kubediff
        ;;
      ubuntu)
        if ! have kubectl; then
          info "Installing kubectl from official Kubernetes apt repo"
          run sudo mkdir -p -m 755 /etc/apt/keyrings
          run bash -c 'curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg'
          run bash -c 'echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null'
          run sudo apt-get update -qq
          apt_install kubectl
        else
          ok "kubectl already installed"
        fi
        # kubediff via cargo (no debian package)
        if ! have kubediff && have cargo; then
          info "cargo install kubediff"
          run cargo install kubediff
        fi
        ;;
    esac
  fi
}

# ─── nvim config placement ───────────────────────────────────────────────────
setup_config() {
  step "Neovim config placement"
  local target="$HOME/.config/nvim"
  local source; source="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ "$source" == "$target" ]]; then
    ok "Already running from \$HOME/.config/nvim — no copy needed"
    return
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local backup
    backup="$target.bak-$(date +%Y%m%d-%H%M%S)"
    warn "Existing $target → backing up to $backup"
    run mv "$target" "$backup"
  fi

  info "Copying $source → $target"
  run mkdir -p "$(dirname "$target")"
  run cp -a "$source" "$target"
  ok "Config in place"
}

# ─── plugin + parser + mason bootstrap ───────────────────────────────────────
bootstrap_nvim() {
  step "Bootstrapping Neovim plugins"
  if ! have nvim; then
    err "nvim not on PATH — installation failed"
    exit 1
  fi

  # Warn if kubectl.nvim's build deps are missing — its `make build` hook
  # needs Go + Cargo on PATH. lazy will still try and silently fail; better
  # to flag it up front so the user knows what to do.
  if ! have go || ! have cargo; then
    warn "Go or Cargo not on PATH — kubectl.nvim's Rust client will fail to build."
    warn "Either install Go + Rust now (re-run with the language prompts), then"
    warn "re-run \`:Lazy build kubectl.nvim\` from inside nvim."
  fi

  # Cargo's default 30s HTTP timeout dies on the ~80MB k8s-openapi crate that
  # kubectl.nvim depends on. Export longer timeouts for the build hook step.
  export CARGO_HTTP_TIMEOUT="${CARGO_HTTP_TIMEOUT:-300}"
  export CARGO_NET_RETRY="${CARGO_NET_RETRY:-10}"

  info "Running Lazy sync (downloads ~120 plugins + compiles build hooks; takes 2-6 min)"
  run nvim --headless "+Lazy! sync" +qa 2>&1 | tail -3

  info "Installing all Treesitter parsers (compiles ~30 grammars)"
  run nvim --headless "+lua require('nvim-treesitter').install({'bash','c','cpp','css','diff','dockerfile','go','gomod','gosum','html','javascript','json','lua','luadoc','luap','markdown','markdown_inline','python','query','regex','rust','scss','sql','toml','tsx','typescript','vim','vimdoc','yaml','gitcommit','gitignore','git_config','git_rebase'}):wait(180000)" +qa 2>&1 | tail -3

  info "Installing Mason tools (LSPs/formatters/linters/DAP adapters)"
  # mason-tool-installer auto-runs on VimEnter, but we trigger it explicitly
  # so the headless session waits for it.
  run nvim --headless "+MasonToolsInstallSync" "+lua vim.defer_fn(function() vim.cmd('qa!') end, 60000)" 2>&1 | tail -3 || true

  ok "Plugin bootstrap complete"
}

# ─── post-install verification + next steps ──────────────────────────────────
verify() {
  step "Verification"
  local fails=0
  for tool in nvim git rg fd tree-sitter; do
    if have "$tool"; then
      ok "$tool: $(command -v "$tool")"
    else
      err "$tool: MISSING"
      fails=$((fails + 1))
    fi
  done

  if have nvim; then
    local count
    count="$(nvim --headless "+lua print(require('lazy').stats().count)" +qa 2>&1 | tail -1 | tr -d '\r')"
    if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 50 )); then
      ok "Lazy reports $count plugins installed"
    else
      warn "Could not read plugin count from nvim"
    fi
  fi

  return $fails
}

next_steps() {
  step "Next steps"
  cat <<EOF
  ${BOLD}1.${RESET} Authenticate GitHub Copilot — open nvim and run:
       ${CYAN}:Copilot auth${RESET}

  ${BOLD}2.${RESET} Set your Anthropic API key for Avante (add to your shell rc):
       ${CYAN}export ANTHROPIC_API_KEY=sk-ant-...${RESET}

  ${BOLD}3.${RESET} Authenticate gh CLI for Octo PR review:
       ${CYAN}gh auth login${RESET}

  ${BOLD}4.${RESET} Set your terminal font to ${CYAN}JetBrainsMono Nerd Font${RESET} so icons render.

  ${BOLD}5.${RESET} Open nvim and run ${CYAN}:checkhealth${RESET} to confirm everything is green.

  ${BOLD}Files:${RESET}
       Config: ${CYAN}~/.config/nvim${RESET}
       Plugin state: ${CYAN}~/.local/share/nvim${RESET}
       Sessions: ${CYAN}~/.local/state/nvim${RESET}

  Re-run this script anytime with ${CYAN}--skip-system${RESET} to rebuild plugins after a config change.
EOF
}

# ─── main flow ───────────────────────────────────────────────────────────────
main() {
  banner

  info "Detected OS: ${BOLD}${OS}${RESET}"
  case "$OS" in
    macos|ubuntu) ;;
    *) err "$OS isn't supported"; exit 1 ;;
  esac

  if (( SKIP_SYSTEM )); then
    info "Skipping system packages (--skip-system)"
  else
    ensure_pkg_mgr
    install_required
    if (( ! MINIMAL )); then
      install_recommended
      install_languages
      install_optional
    fi
    setup_config
  fi

  if (( SKIP_BOOTSTRAP )); then
    info "Skipping nvim plugin bootstrap (--skip-bootstrap)"
  else
    bootstrap_nvim
  fi

  verify || warn "Some required tools are missing — see above"
  next_steps

  echo
  ok "${BOLD}Done.${RESET} Launch ${CYAN}nvim${RESET} to start."
}

main "$@"
