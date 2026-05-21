#!/usr/bin/env bash
# doctor.sh — headless nvim diagnostic capture.
#
# Usage:
#   doctor.sh                  # default: actionable issues only (curated noise filter)
#   doctor.sh full             # full report: stats + messages + checkhealth
#   doctor.sh messages         # just :messages
#   doctor.sh health           # just :checkhealth (full)
#   doctor.sh errors           # checkhealth filtered to ❌/✗ lines + context
#   doctor.sh warns            # checkhealth filtered to ⚠ lines + context
#   doctor.sh issues           # all errors + warns (no noise filter)
#   doctor.sh actionable       # issues with known-benign patterns suppressed
#   doctor.sh keymaps          # static scan for <leader> collisions across all specs
#   doctor.sh stats            # lazy plugin stats only
#   doctor.sh section <name>   # one checkhealth section, e.g. snacks, lsp, dap
#   doctor.sh -- <args...>     # extra nvim args (file to open etc.)
#
# Exit code: number of ERROR lines in checkhealth output (0 = clean).

set -euo pipefail

MODE="${1:-actionable}"; shift || true   # default: just surface the actionable items
EXTRA=()
if [[ "${1:-}" == "--" ]]; then shift; EXTRA=("$@"); fi

# Use a real Python file so language-aware plugins (treesitter, LSP) load.
SMOKE="/tmp/.doctor-smoke.py"
cat > "$SMOKE" <<'EOF'
def hello():
    """A tiny file so plugins get to attach."""
    return "world"
EOF

TMP=$(mktemp -d)
LUA="$TMP/probe.lua"
OUT="$TMP/out.txt"

cat > "$LUA" <<LUA
-- 1) wait briefly for plugins to attach
vim.defer_fn(function()
  pcall(vim.cmd, 'silent checkhealth')

  -- 2) poll for the checkhealth buffer to fill, then snapshot
  local deadline = vim.uv.now() + 12000  -- up to 12s
  local last_len, stable_ticks = 0, 0

  local function find_health_buf()
    -- There can be multiple checkhealth buffers; pick the largest populated one.
    local best, best_len = nil, 0
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == 'checkhealth' then
        local len = vim.api.nvim_buf_line_count(b)
        if len > best_len then best, best_len = b, len end
      end
    end
    return best
  end

  local function snapshot_and_quit()
    local stats = require('lazy').stats()
    local msgs  = vim.api.nvim_exec2('messages', { output = true }).output
    local health = ''
    local b = find_health_buf()
    if b then health = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), '\n') end

    local out = io.open('$OUT', 'w')
    out:write('===STATS===\n')
    out:write(string.format('plugins:%d loaded:%d startup_ms:%.1f\n',
      stats.count, stats.loaded, stats.startuptime or 0))
    out:write('===MESSAGES===\n')
    out:write(msgs or '')
    out:write('\n===CHECKHEALTH===\n')
    out:write(health)
    out:write('\n===END===\n')
    out:close()
    vim.cmd('qa!')
  end

  local timer = vim.uv.new_timer()
  timer:start(500, 500, vim.schedule_wrap(function()
    local b = find_health_buf()
    local len = b and vim.api.nvim_buf_line_count(b) or 0
    if len == last_len and len > 0 then
      stable_ticks = stable_ticks + 1
      -- 2 stable polls (~1s of no growth) means async filling is done
      if stable_ticks >= 2 then timer:stop(); timer:close(); snapshot_and_quit(); return end
    else
      stable_ticks = 0; last_len = len
    end
    if vim.uv.now() > deadline then timer:stop(); timer:close(); snapshot_and_quit() end
  end))
end, 1500)
LUA

nvim --headless "$SMOKE" ${EXTRA[@]+"${EXTRA[@]}"} "+luafile $LUA" >/dev/null 2>&1 || true

if [[ ! -f "$OUT" ]]; then
  echo "doctor: nvim exited without writing output (check $LUA)" >&2
  exit 99
fi

# Helpers --------------------------------------------------------------------
section() {  # $1 = STATS|MESSAGES|CHECKHEALTH
  awk -v s="===$1===" '
    $0 == s                          { capture = 1; next }
    capture && /^===[A-Z]+===$/      { capture = 0 }
    capture                          { print }
  ' "$OUT"
}

filter_health_issues() {
  local pattern="$1"
  awk -v pat="$pattern" '
    /^===END===/ { next }
    /^=====+$/   { next }
    /^[a-z][a-zA-Z0-9._-]*:/ {
      current_section = $0
      next
    }
    $0 ~ pat {
      if (current_section != last_section) {
        if (last_section != "") print ""
        print "  ▸ " (current_section ? current_section : "(general)")
        last_section = current_section
      }
      print "    " $0
    }
  ' <(section CHECKHEALTH)
}

count_errors() {
  section CHECKHEALTH | grep -cE '(❌|ERROR| ✗ )' || true
}

# Scan every <leader> binding declared in lua/plugins/*.lua and lua/core/*.lua
# and report any key whose modes overlap between two real bindings (which-key
# `group = "..."` entries are skipped because they're labels, not actions).
# lazy.nvim silently last-wins on collisions, so without this they only show
# up when someone tries the docs-promised key and gets the wrong feature.
keymap_collisions() {
  local repo
  repo=$(cd "$(dirname "$0")/.." && pwd)
  python3 - "$repo" <<'PY'
import re, sys, pathlib
from collections import defaultdict

repo = pathlib.Path(sys.argv[1])
roots = [repo / "lua/plugins", repo / "lua/core"]

spec_re = re.compile(r'\{\s*"(<leader>[^"]*)"')
map_re  = re.compile(r'\bmap\s*\(\s*(\{[^}]+\}|"[^"]+")\s*,\s*"(<leader>[^"]*)"')

def parse_modes(s):
    found = set(re.findall(r'"([nivxotcsl])"', s))
    return found or {"n"}

bindings = []  # (key, file, line, modes, is_group, raw)
for root in roots:
    if not root.is_dir():
        continue
    for path in sorted(root.rglob("*.lua")):
        with open(path) as f:
            for n, raw in enumerate(f, 1):
                m = map_re.search(raw)
                if m:
                    bindings.append((m.group(2), str(path.relative_to(repo)), n,
                                     parse_modes(m.group(1)), False, raw.rstrip()))
                    continue
                m = spec_re.search(raw)
                if not m:
                    continue
                is_group = bool(re.search(r'\bgroup\s*=', raw))
                mm = re.search(r'\bmode\s*=\s*("[^"]+"|\{[^}]+\})', raw)
                modes = parse_modes(mm.group(1)) if mm else {"n"}
                bindings.append((m.group(1), str(path.relative_to(repo)), n,
                                 modes, is_group, raw.rstrip()))

by_key = defaultdict(list)
for b in bindings:
    by_key[b[0]].append(b)

collisions = []
for key, entries in by_key.items():
    real = [e for e in entries if not e[4]]
    if len(real) < 2:
        continue
    bad_files = set()
    for i, a in enumerate(real):
        for b in real[i+1:]:
            if a[3] & b[3]:
                bad_files.add((a[1], a[2], frozenset(a[3])))
                bad_files.add((b[1], b[2], frozenset(b[3])))
    if bad_files:
        collisions.append((key, sorted(bad_files)))

if not collisions:
    print("✓ no <leader> keymap collisions")
    sys.exit(0)

print(f"⚠ {len(collisions)} <leader> keymap collision(s):\n")
for key, locs in sorted(collisions):
    print(f"  ▸ {key}")
    for f, n, modes in locs:
        print(f"      {f}:{n}  [{','.join(sorted(modes))}]")
    print()
sys.exit(1)
PY
}

# Patterns the user has knowingly accepted — surfacing them on every run
# just trains the eye to skip past warnings. Anything that's a deliberate
# config choice, an environmental fact, or a headless-only artifact lives
# here. Real regressions (new plugin breakage, missing required tool) will
# still appear because they won't match any of these lines.
NOISE_PATTERNS=(
  # snacks modules we intentionally disabled in extras.lua (notifier/picker/input)
  'setup \{disabled\}'
  "'convert' .WARNING: The convert command is deprecated"  # imagemagick v7 cosmetic notice
  'kitty graphics protocol'                                  # depends on terminal, irrelevant in headless
  '`latex` treesitter parser'                                # math rendering is disabled in snacks.image
  'Missing Treesitter languages:'                            # only listed because of latex above
  'Image rendering in docs with missing treesitter'          # same root cause
  # snacks reports these in headless because the dashboard never finishes init
  '❌ ERROR setup did not run'
  '❌ ERROR is not ready'
  'vim.ui.select. for .Snacks.picker'                        # picker disabled on purpose
  # overseer scans every adapter; the "no such file" lines just enumerate
  # build systems this project doesn't use
  'No Cargo.toml file found'
  'No justfile found'
  'No Makefile found'
  'No mix.exs file found'
  'No package.json file found'
  'No Rakefile found'
  'No tox.ini file found'
  'No .vscode/tasks.json file found'
  'Command "cargo-make" not found'
  'Command "devenv" not found'
  'Command "mage" not found'
  'Command "mise" not found'
  'Command "task" not found'
  'executable composer not found'
  'executable deno not found'
  # mason missing langs the user doesn't write
  'Composer: not available'
  'PHP: not available'
  'julia: not available'
  # vim.lsp registers handlers for filetypes that exist on systems that use
  # them; an unknown-filetype warning here just means "you don't write django
  # templates / razor / helm-values on this box."
  "Unknown filetype 'yaml.ansible'"
  "Unknown filetype 'yaml.docker-compose'"
  "Unknown filetype 'yaml.gitlab'"
  "Unknown filetype 'yaml.helm-values'"
  "Unknown filetype 'gotmpl'"
  "Unknown filetype 'gohtml'"
  "Unknown filetype 'gohtmltmpl'"
  "Unknown filetype 'helm'"
  "Unknown filetype 'markdown.mdx'"
  "Unknown filetype 'mdx'"
  "Unknown filetype 'aspnetcorerazor'"
  "Unknown filetype 'astro-markdown'"
  "Unknown filetype 'django-html'"
  "Unknown filetype 'edge'"
  "Unknown filetype 'ejs'"
  "Unknown filetype 'erb'"
  "Unknown filetype 'hbs'"
  "Unknown filetype 'html-eex'"
  "Unknown filetype 'jade'"
  "Unknown filetype 'leaf'"
  "Unknown filetype 'njk'"
  "Unknown filetype 'nunjucks'"
  "Unknown filetype 'slim'"
  "Unknown filetype 'postcss'"
  "Unknown filetype 'sugarss'"
  "Unknown filetype 'reason'"
  # lazy false-positive: luajit reports as 5.1-compatible, the warning is wrong
  'lua. version .5\.1. needed, but found .Lua 5\.'
  '\{lua5\.1\} or \{lua\} or \{lua-5\.1\} version .5\.1. not installed'
  # blink.cmp's informational note about dynamic providers
  'Some providers may show up as "disabled" but are enabled dynamically'
)

filter_actionable() {
  # Drop the noise lines, then re-collapse into ▸-prefixed sections so the
  # output reads identically to `issues` minus the curated noise.
  local noise_re
  noise_re=$(IFS='|'; echo "${NOISE_PATTERNS[*]}")

  awk -v pat='(❌|⚠|ERROR|WARNING| ✗ )' '
    /^===END===/ { next }
    /^=====+$/   { next }
    /^[a-z][a-zA-Z0-9._-]*:/ { current_section = $0; next }
    $0 ~ pat {
      printf "%s\t%s\n", current_section, $0
    }
  ' <(section CHECKHEALTH) \
    | grep -vE "$noise_re" \
    | awk -F'\t' '
        {
          if ($1 != last) {
            if (last != "") print ""
            print "  ▸ " ($1 ? $1 : "(general)")
            last = $1
          }
          print "    " $2
        }
      '
}

# Dispatch -------------------------------------------------------------------
case "$MODE" in
  full)
    section STATS
    echo
    echo "─── MESSAGES ──────────────────────────────────────────────"
    section MESSAGES | sed '/^$/d'
    echo
    echo "─── CHECKHEALTH ───────────────────────────────────────────"
    section CHECKHEALTH
    ;;
  messages|msgs)
    section MESSAGES | sed '/^$/d' || echo "(no messages)"
    ;;
  health|check)
    section CHECKHEALTH
    ;;
  errors|err)
    filter_health_issues '(❌|ERROR| ✗ )'
    ;;
  warns|warn|warning|warnings)
    filter_health_issues '(⚠|WARNING| ⚠ )'
    ;;
  issues)
    filter_health_issues '(❌|⚠|ERROR|WARNING| ✗ )'
    ;;
  actionable|signal)
    out=$(filter_actionable)
    if [[ -z "$out" ]]; then
      echo "✓ no actionable issues — checkhealth is clean (run \`doctor.sh issues\` for full warn list)"
    else
      echo "$out"
    fi
    ;;
  stats)
    section STATS
    ;;
  keymaps|keys)
    keymap_collisions
    ;;
  section)
    name="${1:-}"
    if [[ -z "$name" ]]; then echo "usage: doctor.sh section <name>" >&2; exit 2; fi
    awk -v target="$name" '
      /^={2,}$/    { in_marker = 1; next }
      in_marker    {
        in_marker = 0
        keep = (tolower($0) ~ "^" tolower(target) ":")
      }
      /^={4,}/     { keep = 0 }
      keep         { print }
    ' <(section CHECKHEALTH)
    ;;
  *)
    echo "doctor.sh: unknown mode '$MODE'" >&2
    echo "modes: full | messages | health | errors | warns | issues | actionable | keymaps | stats | section <name>" >&2
    exit 2
    ;;
esac

rm -rf "$TMP"
exit "$(count_errors 2>/dev/null || echo 0)"
