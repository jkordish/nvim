#!/usr/bin/env bash
# doctor.sh — headless nvim diagnostic capture.
#
# Usage:
#   doctor.sh                  # full report: stats + messages + checkhealth
#   doctor.sh messages         # just :messages
#   doctor.sh health           # just :checkhealth (full)
#   doctor.sh errors           # checkhealth filtered to ❌/✗ lines + context
#   doctor.sh warns            # checkhealth filtered to ⚠ lines + context
#   doctor.sh issues           # errors + warns combined
#   doctor.sh stats            # lazy plugin stats only
#   doctor.sh section <name>   # one checkhealth section, e.g. snacks, lsp, dap
#   doctor.sh -- <args...>     # extra nvim args (file to open etc.)
#
# Exit code: number of ERROR lines in checkhealth output (0 = clean).

set -euo pipefail

MODE="${1:-full}"; shift || true
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
  stats)
    section STATS
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
    echo "modes: full | messages | health | errors | warns | issues | stats | section <name>" >&2
    exit 2
    ;;
esac

rm -rf "$TMP"
exit "$(count_errors 2>/dev/null || echo 0)"
