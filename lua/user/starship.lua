-- Statusline: operator HUD. Three invariants:
--   1. No blocking shell-outs on the render path. External commands run via
--      async_memo() (vim.system + on_exit) and write back into a cache; a
--      scheduled lualine.refresh() repaints when results land.
--   2. Width tiers (<80, 80-119, ≥120) via pri(); action beats identity when
--      space is tight (diagnostics > branch at <80).
--   3. Color = signal. Surface bg is calm context; colored bg is reserved for
--      mode, branch (accent), diagnostics, macro REC, conflicts, save pulse,
--      failed tasks, and risk-tagged context (prod/admin → red; main/master →
--      amber; dev/test/stage → muted).
local M = {}

-- ─── color palette (catppuccin mocha) ───────────────────────────────────────
M.c = {
  base   = "#1e1e2e", surface = "#313244", overlay = "#6c7086", text = "#cdd6f4",
  red    = "#f38ba8", peach   = "#fab387", yellow  = "#f9e2af", green = "#a6e3a1",
  teal   = "#94e2d5", sky     = "#89dceb", sapphire= "#74c7ec", blue  = "#89b4fa",
  lavender = "#b4befe", mauve = "#cba6f7", pink = "#f5c2e7", flamingo = "#f2cdcd",
}

-- ─── opt-in providers (default off; setup({ ops = { ... } }) flips them) ───
M.opts = { ops = { k8s = false, terraform = false } }

-- ─── simple TTL cache (sync, for cheap pure-lua reads) ──────────────────────
local cache = {}
local function memo(key, ttl_ms, fn)
  local now = vim.uv.now()
  local entry = cache[key]
  if entry and (now - entry.t) < ttl_ms then return entry.v end
  local ok, v = pcall(fn)
  if not ok then v = "" end
  cache[key] = { t = now, v = v }
  return v
end

-- ─── async cache (vim.system; never blocks; one in-flight per key) ──────────
-- Hardened: argv only (never a shell string), explicit cwd/env, timeout kills
-- runaway jobs, neg_ttl back-off when the binary is missing or the call fails
-- so we don't respawn-loop on a broken tool. parse() runs under pcall — any
-- error caches "" for neg_ttl rather than exploding the statusline. on_exit
-- triggers a scheduled, pcall'd lualine.refresh({ place = { "statusline" } }).
local async_cache = {}
local function lualine_refresh()
  vim.schedule(function()
    local ok, lualine = pcall(require, "lualine")
    if ok and lualine.refresh then
      pcall(lualine.refresh, { place = { "statusline" } })
    end
  end)
end

local function async_memo(opts)
  local key = opts.key
  local now = vim.uv.now()
  local entry = async_cache[key]
  if entry then
    if entry.neg_until and now < entry.neg_until then return entry.v end
    if entry.t and (now - entry.t) < opts.ttl_ms then return entry.v end
    if entry.inflight then return entry.v end
  else
    entry = { v = "" }
    async_cache[key] = entry
  end
  entry.inflight = true
  local neg_ttl = opts.neg_ttl or 30000
  local ok = pcall(vim.system, opts.cmd, {
    text = true, cwd = opts.cwd, env = opts.env, timeout = opts.timeout or 2000,
  }, function(obj)
    entry.inflight = false
    entry.t = vim.uv.now()
    if obj.code == 0 then
      local pok, parsed = pcall(opts.parse, obj)
      if pok then
        entry.v = parsed or ""
        entry.neg_until = nil
      else
        entry.v = ""
        entry.neg_until = entry.t + neg_ttl
      end
    else
      entry.v = ""
      entry.neg_until = entry.t + neg_ttl
    end
    lualine_refresh()
  end)
  if not ok then
    entry.inflight = false
    entry.v = ""
    entry.t = now
    entry.neg_until = now + neg_ttl
  end
  return entry.v
end

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function file_exists(p) return vim.uv.fs_stat(p) ~= nil end

-- Walk up from cwd (not buffer) up to 8 levels looking for `name`. Used for
-- existence checks where buffer-context (vim.fs.root) is wrong: we want the
-- workspace marker, not "anywhere above the current file".
local function find_up(name)
  local dir = vim.fn.getcwd()
  for _ = 1, 8 do
    if file_exists(dir .. "/" .. name) then return dir .. "/" .. name end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then return nil end
    dir = parent
  end
end

-- Project root via vim.fs.root — marker order matters. Nested table means
-- "equal priority among these"; trailing markers are lower-priority fallbacks.
-- Language manifests beat .git so a sub-project root wins over an outer repo.
local function proj_root()
  local r = vim.fs.root(0, {
    { "Cargo.toml", "go.mod", "pyproject.toml", "package.json",
      "deno.json", "mix.exs", "Gemfile", "build.zig", "composer.json" },
    "flake.nix", "Makefile", ".git",
  })
  return r or vim.fn.getcwd()
end

-- Severity-driven color for context-name chips (k8s, terraform, aws, git
-- branch). Three tiers:
--   red    — prod / admin / root contexts: alarm
--   amber  — main / master: notice (NOT alarm; escalation to red happens at
--            the call site by combining with a prod-tagged ops chip)
--   muted  — dev / test / stage / staging / sandbox / local: calm
-- Returns nil for benign / unmatched contexts so the caller falls back to its
-- own palette (typically surface bg).
local function risk_color(name)
  local n = (name or ""):lower()
  if n:find("prod") or n:find("production") or n:find("live")
     or n:find("admin") or n:find("root") then
    return { bg = M.c.red, fg = M.c.base, gui = "bold" }
  end
  if n == "main" or n == "master" then
    return { bg = M.c.yellow, fg = M.c.base, gui = "bold" }
  end
  if n:match("^dev") or n:match("^test") or n:match("^stage")
     or n:find("staging") or n:find("sandbox") or n:match("^local") then
    return { bg = M.c.surface, fg = M.c.overlay }
  end
  return nil
end

-- Last path-like segment, then ellipsize. Defends against full kubeconfig
-- ARNs, /etc/aws/... paths, or AWS access-key-shaped strings leaking in.
local function abbrev(s, max)
  if not s or s == "" then return "" end
  max = max or 18
  local tail = s:match("([^/:]+)$") or s
  if #tail > max then tail = tail:sub(1, max - 1) .. "…" end
  return tail
end

-- ─── visual helpers (sparklines, gauges, dots) — retained for reuse ────────
-- These power callers outside this module (compass HUD, future panels).
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local BAR_LEVELS = { " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local DOT_ON, DOT_OFF = "●", "○"

M._spark = {}
function M.spark(key, value, cap, max)
  cap = cap or 10
  local s = M._spark[key]
  if not s then s = { samples = {} }; M._spark[key] = s end
  s.samples[#s.samples + 1] = value
  while #s.samples > cap do table.remove(s.samples, 1) end
  local scale = max
  if not scale then
    scale = 0.0001
    for _, v in ipairs(s.samples) do if v > scale then scale = v end end
  end
  if scale <= 0 then scale = 0.0001 end
  local out = {}
  for i, v in ipairs(s.samples) do
    local norm = math.max(0, math.min(1, v / scale))
    local idx = math.min(#SPARK, math.floor(norm * #SPARK) + 1)
    out[i] = SPARK[idx]
  end
  return table.concat(out, "")
end

function M.bar(value, max, width)
  width = width or 4
  if not max or max == 0 then max = 1 end
  local norm = math.max(0, math.min(1, value / max))
  local idx = math.floor(norm * #BAR_LEVELS) + 1
  if idx > #BAR_LEVELS then idx = #BAR_LEVELS end
  return string.rep(BAR_LEVELS[idx], width)
end

function M.dots(filled, total)
  total = total or 5
  filled = math.max(0, math.min(total, filled))
  return string.rep(DOT_ON, filled) .. string.rep(DOT_OFF, total - filled)
end

-- ─── modules (segments). Each returns {text, fg, bg, gui} or {text=""} ─────
M.modules = {}

-- ─── MODE ──────────────────────────────────────────────────────────────────
local MODE_DEFS = {
  ["n"]   = { label = "NORMAL",   icon = "●",  bg = "blue"     },
  ["no"]  = { label = "O-PEND",   icon = "◐",  bg = "blue"     },
  ["nov"] = { label = "O-PEND",   icon = "◐",  bg = "blue"     },
  ["noV"] = { label = "O-PEND",   icon = "◐",  bg = "blue"     },
  ["niI"] = { label = "NORMAL·i", icon = "●",  bg = "blue"     },
  ["niR"] = { label = "NORMAL·R", icon = "●",  bg = "blue"     },
  ["i"]   = { label = "INSERT",   icon = "",  bg = "green"    },
  ["ic"]  = { label = "INSERT",   icon = "",  bg = "green"    },
  ["ix"]  = { label = "INSERT",   icon = "",  bg = "green"    },
  ["v"]   = { label = "VISUAL",   icon = "󰒉",  bg = "mauve"    },
  ["V"]   = { label = "V·LINE",   icon = "󰒉",  bg = "mauve"    },
  ["\22"] = { label = "V·BLOCK",  icon = "󰒉",  bg = "mauve"    },
  ["s"]   = { label = "SELECT",   icon = "󰒉",  bg = "mauve"    },
  ["S"]   = { label = "S·LINE",   icon = "󰒉",  bg = "mauve"    },
  ["\19"] = { label = "S·BLOCK",  icon = "󰒉",  bg = "mauve"    },
  ["R"]   = { label = "REPLACE",  icon = "",  bg = "red"      },
  ["Rv"]  = { label = "V·REPL",   icon = "",  bg = "red"      },
  ["Rx"]  = { label = "REPLACE",  icon = "",  bg = "red"      },
  ["c"]   = { label = "COMMAND",  icon = "",  bg = "peach"    },
  ["cv"]  = { label = "EX",       icon = "",  bg = "peach"    },
  ["r"]   = { label = "PROMPT",   icon = "",  bg = "sapphire" },
  ["rm"]  = { label = "MORE",     icon = "",  bg = "sapphire" },
  ["r?"]  = { label = "CONFIRM",  icon = "",  bg = "sapphire" },
  ["!"]   = { label = "SHELL",    icon = "",  bg = "yellow"   },
  ["t"]   = { label = "TERMINAL", icon = "",  bg = "teal"     },
  ["nt"]  = { label = "TERMINAL", icon = "",  bg = "teal"     },
}
M._mode_defs = MODE_DEFS  -- exposed for compass.lua

function M.modules.mode()
  local m = vim.api.nvim_get_mode().mode
  local def = MODE_DEFS[m] or MODE_DEFS[m:sub(1, 1)] or MODE_DEFS["n"]
  return { text = (" %s %s "):format(def.icon, def.label),
           fg = M.c.base, bg = M.c[def.bg], gui = "bold" }
end

-- DIR — project root basename (not raw cwd). Risk-colored if the project name
-- itself trips the prod/admin filter (rare but real for repo-per-env layouts).
function M.modules.dir()
  local name = vim.fn.fnamemodify(proj_root(), ":t")
  if name == "" then return { text = "" } end
  local risk = risk_color(name)
  if risk then
    return { text = ("  %s "):format(name), fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = ("  %s "):format(name), fg = M.c.text, bg = M.c.surface }
end

-- FILE — width-aware:
--   <80 cols  → icon + basename + modmarks
--   ≥80 cols  → icon + relative path (`:.`) + modmarks, pathshorten if >36 chars
-- Special buffers (help, term, qf, lazy, mason, oil/netrw) get friendly labels.
local SPECIAL_FT_LABEL = {
  lazy = "  lazy", mason = "  mason", oil = "  oil",
  ["neo-tree"] = "  files", trouble = "  trouble", aerial = "  aerial",
  TelescopePrompt = "  telescope", help = "  help",
}
function M.modules.file()
  local bt = vim.bo.buftype
  local ft = vim.bo.filetype
  local name = vim.api.nvim_buf_get_name(0)

  if bt == "help" then
    local topic = vim.fn.fnamemodify(name, ":t:r")
    return { text = ("   %s "):format(topic ~= "" and topic or "help"),
             fg = M.c.text, bg = M.c.surface }
  end
  if bt == "terminal" then
    return { text = "   term ", fg = M.c.text, bg = M.c.surface }
  end
  if bt == "quickfix" then
    local is_loc = vim.fn.getloclist(0, { winid = 0 }).winid ~= 0
    return { text = ("  %s "):format(is_loc and " loclist" or " qf"),
             fg = M.c.text, bg = M.c.surface }
  end
  if ft == "netrw" or name:match("^oil://") then
    local d = vim.fn.fnamemodify(name:gsub("^oil://", ""), ":t")
    if d == "" then d = vim.fn.fnamemodify(vim.fn.getcwd(), ":t") end
    return { text = ("   %s "):format(d), fg = M.c.text, bg = M.c.surface }
  end
  if SPECIAL_FT_LABEL[ft] then
    return { text = SPECIAL_FT_LABEL[ft] .. " ", fg = M.c.text, bg = M.c.surface }
  end
  if bt ~= "" then return { text = "" } end
  if name == "" then
    return { text = "  [No Name] ", fg = M.c.overlay, bg = M.c.surface }
  end

  local label
  if vim.o.columns >= 80 then
    label = vim.fn.fnamemodify(name, ":.")
    if #label > 36 then label = vim.fn.pathshorten(label, 1) end
    if #label > 36 then label = "…" .. label:sub(-35) end
  else
    label = vim.fn.fnamemodify(name, ":t")
  end
  if label == "" then return { text = "" } end

  local ok, icons = pcall(require, "user.icons")
  local glyph = ok and icons.ft(name, ft).icon or ""
  local mod = vim.bo.modified and " ●" or ""
  local ro  = (vim.bo.readonly or not vim.bo.modifiable) and "  " or ""
  return { text = (" %s %s%s%s "):format(glyph, label, mod, ro),
           fg = M.c.text, bg = M.c.surface }
end

-- GIT BRANCH (+ ahead/behind via async). Branch from gitsigns buffer var; if
-- absent, the chip is empty (no shell-out fallback — gitsigns covers the cases
-- we care about). Ahead/behind is one async call cached for 60s; appears once
-- the call returns, hidden until then.
function M.modules.git()
  local buf = vim.api.nvim_get_current_buf()
  local branch = vim.b[buf].gitsigns_head
  if not branch or branch == "" then return { text = "" } end
  local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
  local counts = async_memo({
    key = "git:counts:" .. root,
    ttl_ms = 60000,
    cmd = { "git", "-C", root, "rev-list", "--left-right", "--count",
            "@{upstream}...HEAD" },
    cwd = root,
    timeout = 1500,
    neg_ttl = 60000,
    parse = function(obj)
      local first = (obj.stdout or ""):match("[^\n]+") or ""
      local behind, ahead = first:match("(%d+)%s+(%d+)")
      return { ahead = tonumber(ahead) or 0, behind = tonumber(behind) or 0 }
    end,
  })
  local out = " " .. branch
  if type(counts) == "table" then
    if counts.ahead  and counts.ahead  > 0 then out = out .. " ↑" .. counts.ahead  end
    if counts.behind and counts.behind > 0 then out = out .. " ↓" .. counts.behind end
  end
  local risk = risk_color(branch)
  if risk then
    return { text = " " .. out .. " ", fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = " " .. out .. " ", fg = M.c.base, bg = M.c.mauve, gui = "bold" }
end

-- GIT DIFF — file-local (gitsigns buffer var). Semantic shift from the old
-- repo-wide `git status --porcelain`: this is "lines changed in THIS file",
-- not "the repo has untracked files somewhere". For an operator HUD, file-
-- local is more actionable.
function M.modules.gitdiff()
  local sd = vim.b[vim.api.nvim_get_current_buf()].gitsigns_status_dict
  if type(sd) ~= "table" then return { text = "" } end
  local a, m, d = sd.added or 0, sd.changed or 0, sd.removed or 0
  if a + m + d == 0 then return { text = "" } end
  local parts = {}
  if a > 0 then parts[#parts + 1] = ("%d"):format(a) end
  if m > 0 then parts[#parts + 1] = ("%d"):format(m) end
  if d > 0 then parts[#parts + 1] = ("%d"):format(d) end
  return { text = " " .. table.concat(parts, " ") .. " ", fg = M.c.text, bg = M.c.surface }
end

-- ─── Runtime / toolchain chips ──────────────────────────────────────────────
-- Filetype-gated only (no project-marker fallback). In practice you're in one
-- filetype at a time, so only one fires. Keeps the chain quiet in mixed repos.

function M.modules.python()
  if vim.bo.filetype ~= "python" then return { text = "" } end
  local tag = ""
  local venv = vim.env.VIRTUAL_ENV
  if venv then tag = " " .. abbrev(vim.fn.fnamemodify(venv, ":t"), 12) end
  return { text = (" 🐍%s "):format(tag), fg = M.c.text, bg = M.c.surface }
end

function M.modules.node()
  local ft = vim.bo.filetype
  local is_js = ft == "javascript" or ft == "typescript" or ft == "javascriptreact"
             or ft == "typescriptreact" or ft == "vue" or ft == "svelte"
  if not is_js then return { text = "" } end
  return { text = "   ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.go()
  if vim.bo.filetype ~= "go" then return { text = "" } end
  return { text = " 🐹 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.rust()
  if vim.bo.filetype ~= "rust" then return { text = "" } end
  return { text = " 🦀 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.lua()
  if vim.bo.filetype ~= "lua" then return { text = "" } end
  return { text = " 󰢱 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.ruby()
  if vim.bo.filetype ~= "ruby" then return { text = "" } end
  return { text = " 💎 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.elixir()
  if vim.bo.filetype ~= "elixir" then return { text = "" } end
  return { text = " 💧 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.deno()
  if vim.bo.filetype ~= "typescript" or not find_up("deno.json") then return { text = "" } end
  return { text = " 󰟔 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.bun()
  local ft = vim.bo.filetype
  if (ft ~= "javascript" and ft ~= "typescript") or not find_up("bun.lock") then
    return { text = "" }
  end
  return { text = " 󰳏 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.java()
  if vim.bo.filetype ~= "java" then return { text = "" } end
  return { text = " 󰬷 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.zig()
  if vim.bo.filetype ~= "zig" then return { text = "" } end
  return { text = " ↯ ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.php()
  if vim.bo.filetype ~= "php" then return { text = "" } end
  return { text = " 🐘 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.docker()
  local ft = vim.bo.filetype
  if ft ~= "dockerfile" and ft ~= "yaml.docker-compose" then return { text = "" } end
  return { text = "   ", fg = M.c.text, bg = M.c.surface }
end

-- ─── Ops context (opt-in async) ─────────────────────────────────────────────

-- KUBERNETES — opt-in (M.opts.ops.k8s). Only renders for infra-shaped buffers
-- (yaml/helm filetype OR Chart.yaml / kustomization.yaml in the tree) so it
-- doesn't bleed into every editor session. Context name abbreviated + risk-
-- colored.
function M.modules.k8s()
  if not M.opts.ops.k8s then return { text = "" } end
  local ft = vim.bo.filetype
  local infra = (ft == "yaml" or ft == "helm")
    or find_up("Chart.yaml") or find_up("kustomization.yaml")
  if not infra then return { text = "" } end
  local ctx = async_memo({
    key = "k8s:ctx",
    ttl_ms = 60000,
    cmd = { "kubectl", "config", "current-context" },
    timeout = 1500,
    neg_ttl = 120000,
    parse = function(obj) return trim(obj.stdout or "") end,
  })
  if not ctx or ctx == "" then return { text = "" } end
  local short = abbrev(ctx, 18)
  local risk = risk_color(ctx)
  if risk then
    return { text = (" 󱃾 %s "):format(short), fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = (" 󱃾 %s "):format(short), fg = M.c.text, bg = M.c.surface }
end

-- TERRAFORM — opt-in (M.opts.ops.terraform). Filetype-gated. Async workspace.
function M.modules.terraform()
  if not M.opts.ops.terraform then return { text = "" } end
  if vim.bo.filetype ~= "terraform" and not find_up("main.tf") then return { text = "" } end
  local root = vim.fs.root(0, "main.tf") or vim.fn.getcwd()
  local ws = async_memo({
    key = "tf:ws:" .. root,
    ttl_ms = 60000,
    cmd = { "terraform", "workspace", "show" },
    cwd = root,
    timeout = 2000,
    neg_ttl = 120000,
    parse = function(obj) return trim(obj.stdout or "") end,
  })
  if not ws or ws == "" then return { text = "" } end
  local short = abbrev(ws, 14)
  local risk = risk_color(ws)
  if risk then
    return { text = (" 󱁢 %s "):format(short), fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = (" 󱁢 %s "):format(short), fg = M.c.text, bg = M.c.surface }
end

-- AWS profile — env-var only (no shell). Defensive: reject access-key-shaped
-- strings (someone exported a session token into AWS_PROFILE by accident) and
-- absurdly long values (likely an ARN).
function M.modules.aws()
  local p = vim.env.AWS_PROFILE
  if not p or p == "" then return { text = "" } end
  if p:match("^A[KS]IA[A-Z0-9]+$") or #p > 40 then return { text = "" } end
  local short = abbrev(p, 16)
  local risk = risk_color(p)
  if risk then
    return { text = (" 󰸏 %s "):format(short), fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = (" 󰸏 %s "):format(short), fg = M.c.text, bg = M.c.surface }
end

-- ─── Identity / environment ────────────────────────────────────────────────

-- SSH HOSTNAME — only when connected via SSH (flamingo bg = "remote session").
function M.modules.ssh()
  if not vim.env.SSH_CLIENT and not vim.env.SSH_TTY then return { text = "" } end
  local host = memo("hostname", 60000, function() return trim(vim.fn.hostname() or "") end):match("^[^.]+") or "?"
  return { text = ("  %s "):format(host), fg = M.c.base, bg = M.c.flamingo, gui = "bold" }
end

-- USER PROMPT — `# root` in red when running as root, plain otherwise.
function M.modules.user_short()
  local user = vim.env.USER or "user"
  local is_root = vim.uv.os_getenv("USER") == "root"
    or (vim.uv.os_getuid and vim.uv.os_getuid() == 0)
  local bg = is_root and M.c.red or M.c.lavender
  local prefix = is_root and "# " or " "
  return { text = (prefix .. "%s "):format(user), fg = M.c.base, bg = bg, gui = "bold" }
end

-- DIRENV — when .envrc was sourced in this shell
function M.modules.direnv()
  if not vim.env.DIRENV_DIR then return { text = "" } end
  return { text = "  direnv ", fg = M.c.base, bg = M.c.green }
end

-- CMD DURATION — populated by _hook_cmd_timing; shows only when >500ms.
M._last_cmd_ms = 0
function M.modules.cmd_duration()
  local ms = M._last_cmd_ms
  if ms < 500 then return { text = "" } end
  local txt
  if ms < 1000 then txt = ms .. "ms"
  elseif ms < 60000 then txt = string.format("%.1fs", ms / 1000)
  else txt = string.format("%dm%ds", math.floor(ms / 60000), math.floor((ms % 60000) / 1000)) end
  return { text = ("  took %s "):format(txt), fg = M.c.yellow, bg = M.c.surface, gui = "italic" }
end

-- AI STATUS — Copilot indicator (icon-only).
function M.modules.ai()
  local cop_ok, cop_api = pcall(require, "copilot.api")
  if not cop_ok then return { text = "" } end
  local s = cop_api.status.data.status
  local fg
  if s == "InProgress" then fg = M.c.yellow
  elseif s == "Warning" then fg = M.c.red
  else fg = M.c.green end
  return { text = "   ", fg = fg, bg = M.c.surface }
end

-- POMO — current pomodoro timer
function M.modules.pomo()
  local ok, pomo = pcall(require, "pomo")
  if not ok then return { text = "" } end
  local t = pomo.get_first_to_finish()
  if not t then return { text = "" } end
  return { text = ("  %s %s "):format(t:remaining_time_str(), t.name or ""),
           fg = M.c.base, bg = M.c.peach, gui = "bold" }
end

-- ─── SPINNER ──────────────────────────────────────────────────────────────
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local function spin_frame()
  return SPINNER[(math.floor(vim.uv.now() / 80) % #SPINNER) + 1]
end

function M.modules.spinner()
  local ok, jobs = pcall(require, "user.jobs")
  if not ok or not jobs.tasks then return { text = "" } end
  local STATUS = jobs.STATUS or {}
  local running = 0
  for _, t in pairs(jobs.tasks()) do
    if t.status == (STATUS.RUNNING or "running") then running = running + 1 end
  end
  if running == 0 then return { text = "" } end
  return { text = (" %s %d job%s "):format(spin_frame(), running, running > 1 and "s" or ""),
           fg = M.c.base, bg = M.c.sapphire, gui = "bold" }
end

-- ─── LSP CLIENTS ──────────────────────────────────────────────────────────
function M.modules.lsp()
  local bt = vim.api.nvim_get_option_value("buftype", { buf = 0 })
  if bt ~= "" then return { text = "" } end
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then return { text = "" } end
  local names = {}
  for _, c in ipairs(clients) do
    local n = (c.name or "?"):gsub("_ls$", "")
    names[#names + 1] = n
  end
  local label
  if #names > 3 then
    label = table.concat({ names[1], names[2], "+" .. (#names - 2) }, "·")
  else
    label = table.concat(names, "·")
  end
  if #label > 24 then label = label:sub(1, 23) .. "…" end
  return { text = (" 󰒋 %s "):format(label), fg = M.c.text, bg = M.c.surface }
end

-- ─── DIAGNOSTICS ──────────────────────────────────────────────────────────
function M.modules.diag()
  local d = vim.diagnostic.count(0)
  local e, w, i, h = d[1] or 0, d[2] or 0, d[3] or 0, d[4] or 0
  if e + w + i + h == 0 then return { text = "" } end
  local parts = {}
  if e > 0 then parts[#parts + 1] = ("  %d"):format(e) end
  if w > 0 then parts[#parts + 1] = ("  %d"):format(w) end
  if i > 0 then parts[#parts + 1] = ("  %d"):format(i) end
  if h > 0 then parts[#parts + 1] = (" 󰌵 %d"):format(h) end
  local bg
  if e > 0 then bg = M.c.red
  elseif w > 0 then bg = M.c.yellow
  elseif i > 0 then bg = M.c.sky
  else bg = M.c.teal end
  return { text = " " .. table.concat(parts, " ") .. " ",
           fg = M.c.base, bg = bg, gui = "bold" }
end

-- Quick predicate used by the chain to mute branch at <80 cols when any diag
-- exists (action beats identity when space is tight).
local function diag_active()
  local d = vim.diagnostic.count(0)
  return (d[1] or 0) + (d[2] or 0) + (d[3] or 0) + (d[4] or 0) > 0
end

-- ─── MACRO RECORDING ──────────────────────────────────────────────────────
function M.modules.macro()
  local reg = vim.fn.reg_recording()
  if reg == "" then return { text = "" } end
  local lit = (math.floor(vim.uv.now() / 500) % 2) == 0
  local icon = lit and "" or ""
  return { text = (" %s REC @%s "):format(icon, reg),
           fg = M.c.base, bg = M.c.red, gui = "bold" }
end

-- ─── SAVE PULSE ───────────────────────────────────────────────────────────
M._save_pulse = nil
local PULSE_MS = 1600

function M._hook_save_pulse()
  local grp = vim.api.nvim_create_augroup("user_starship_save_pulse", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = grp,
    callback = function(ev)
      local name = vim.fn.fnamemodify(ev.file or "", ":t")
      if name == "" then return end
      M._save_pulse = { until_ms = vim.uv.now() + PULSE_MS, name = name, ok = true }
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = grp,
    callback = function()
      if M._save_pulse and (vim.uv.now() > M._save_pulse.until_ms) then
        M._save_pulse = nil
      end
    end,
  })
end

function M.modules.save_pulse()
  local p = M._save_pulse
  if not p then return { text = "" } end
  local remaining = p.until_ms - vim.uv.now()
  if remaining <= 0 then
    M._save_pulse = nil
    return { text = "" }
  end
  local pct = remaining / PULSE_MS
  local bg
  if p.ok then
    if pct > 0.66 then bg = M.c.green
    elseif pct > 0.33 then bg = M.c.teal
    else bg = M.c.sapphire end
  else
    bg = M.c.red
  end
  local icon = p.ok and "" or ""
  local name = p.name
  if #name > 22 then name = name:sub(1, 20) .. "…" end
  return { text = (" %s saved · %s "):format(icon, name),
           fg = M.c.base, bg = bg, gui = "bold" }
end

-- ─── DIAGNOSTIC SIGN CHIPS ────────────────────────────────────────────────
function M._hook_diag_chips()
  local grp = vim.api.nvim_create_augroup("user_starship_diag_chips", { clear = true })
  local function apply()
    local set = function(g, opts) pcall(vim.api.nvim_set_hl, 0, g, opts) end
    set("DiagnosticSignError", { fg = M.c.base, bg = M.c.red,    bold = true })
    set("DiagnosticSignWarn",  { fg = M.c.base, bg = M.c.yellow, bold = true })
    set("DiagnosticSignInfo",  { fg = M.c.base, bg = M.c.sky,    bold = true })
    set("DiagnosticSignHint",  { fg = M.c.base, bg = M.c.teal,   bold = true })
    set("DiagnosticError",     { fg = M.c.red })
    set("DiagnosticWarn",      { fg = M.c.yellow })
    set("DiagnosticInfo",      { fg = M.c.sky })
    set("DiagnosticHint",      { fg = M.c.teal })
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = apply })
  vim.schedule(apply)
end

-- ─── PLAYBOOK LED ─────────────────────────────────────────────────────────
local function fmt_age(secs)
  if secs < 60 then return tostring(secs) .. "s" end
  if secs < 3600 then return tostring(math.floor(secs / 60)) .. "m" end
  return tostring(math.floor(secs / 3600)) .. "h"
end

function M.modules.playbook_led()
  local ok, pb = pcall(require, "user.playbooks")
  if not ok or not pb.last_fired then return { text = "" } end
  local last = pb.last_fired()
  if not last then return { text = "" } end
  local age = os.time() - last.ts
  local bg, icon
  if last.status == "running" then bg, icon = M.c.sapphire, "▶"
  elseif last.status == "error" then bg, icon = M.c.red, "✗"
  else bg, icon = M.c.green, "✓" end
  local name = last.name or "playbook"
  if #name > 20 then name = name:sub(1, 18) .. "…" end
  return { text = (" %s %s · %s "):format(icon, name, fmt_age(age)),
           fg = M.c.base, bg = bg, gui = "bold" }
end

-- ─── OVERSEER TASKS ───────────────────────────────────────────────────────
function M.modules.tasks()
  local ok, overseer = pcall(require, "overseer"); if not ok then return { text = "" } end
  local statuses_ok, statuses = pcall(function() return require("overseer.constants").STATUS end)
  local running = 0
  local failed  = 0
  for _, t in ipairs(overseer.list_tasks({})) do
    if statuses_ok and t.status == statuses.RUNNING then running = running + 1
    elseif statuses_ok and t.status == statuses.FAILURE then failed = failed + 1 end
  end
  if running == 0 and failed == 0 then return { text = "" } end
  local txt, bg
  if running > 0 then
    txt = (" %s %d task%s "):format(spin_frame(), running, running > 1 and "s" or "")
    bg = M.c.sapphire
  else
    txt = (" ✗ %d failed "):format(failed)
    bg = M.c.red
  end
  return { text = txt, fg = M.c.base, bg = bg, gui = "bold" }
end

-- ─── CONTEXT CHIPS (todos / conflicts / dap) ──────────────────────────────
local _todo_cache, _conflict_cache = {}, {}

local function _bufprep()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then return nil end
  return buf, vim.api.nvim_buf_get_changedtick(buf)
end

function M.modules.todos()
  local buf, tick = _bufprep(); if not buf then return { text = "" } end
  local hit = _todo_cache[buf]
  if not (hit and hit.tick == tick) then
    local count = 0
    local lc = math.min(vim.api.nvim_buf_line_count(buf), 5000)
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, lc, false)) do
      if l:find("TODO", 1, true) or l:find("FIXME", 1, true)
         or l:find("HACK", 1, true) or l:find("XXX", 1, true) then
        count = count + 1
      end
    end
    hit = { tick = tick, count = count }; _todo_cache[buf] = hit
  end
  if hit.count == 0 then return { text = "" } end
  return { text = (" 󱅄 %d "):format(hit.count), fg = M.c.base, bg = M.c.yellow, gui = "bold" }
end

function M.modules.conflicts()
  local buf, tick = _bufprep(); if not buf then return { text = "" } end
  local hit = _conflict_cache[buf]
  if not (hit and hit.tick == tick) then
    local count = 0
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:sub(1, 7) == "<<<<<<<" then count = count + 1 end
    end
    hit = { tick = tick, count = count }; _conflict_cache[buf] = hit
  end
  if hit.count == 0 then return { text = "" } end
  return { text = (" 󰦓 %d conflict%s "):format(hit.count, hit.count > 1 and "s" or ""),
           fg = M.c.base, bg = M.c.red, gui = "bold" }
end

function M.modules.dap_state()
  local ok, dap = pcall(require, "dap"); if not ok then return { text = "" } end
  local session = dap.session and dap.session(); if not session then return { text = "" } end
  local status = session.stopped_thread_id and "stopped" or "running"
  if status == "stopped" then
    return { text = "  paused ", fg = M.c.base, bg = M.c.mauve, gui = "bold" }
  else
    return { text = (" %s  debug "):format(spin_frame()), fg = M.c.base, bg = M.c.teal, gui = "bold" }
  end
end

-- Tab-undo affordance: zero state = zero ink. One soft `↺N` chip when there's
-- recovery available; click opens the picker.
function M.modules.tab_undo()
  local ok, tabs = pcall(require, "user.tabs"); if not ok then return { text = "" } end
  local n = (tabs.closed_count and tabs.closed_count()) or 0
  if n == 0 then return { text = "" } end
  return { text = (" ↺%d "):format(n), fg = M.c.base, bg = M.c.green, gui = "bold" }
end

local function _flush_buf_cache(args)
  _todo_cache[args.buf] = nil
  _conflict_cache[args.buf] = nil
end

-- JIRA — delegates to user.jira's in-memory cache (never HTTPs from here).
function M.modules.jira()
  local ok, jira = pcall(require, "user.jira"); if not ok then return { text = "" } end
  local seg = jira.statusline_segment(M.c)
  return seg or { text = "" }
end

-- SEARCH — n/N while /-search is active.
function M.modules.search()
  if vim.v.hlsearch == 0 then return { text = "" } end
  local ok, sc = pcall(vim.fn.searchcount, { recompute = 1, maxcount = 999 })
  if not ok or not sc or not sc.total or sc.total == 0 then return { text = "" } end
  return { text = (" 󰍉 %d/%d "):format(sc.current or 0, sc.total),
           fg = M.c.base, bg = M.c.flamingo, gui = "bold" }
end

-- ─── mode-reactive bufferline accent (mode color flows through whole UI) ──
function M._hook_mode_accent()
  local grp = vim.api.nvim_create_augroup("user_starship_mode_accent", { clear = true })
  local function apply()
    local mode = vim.api.nvim_get_mode().mode
    local def = MODE_DEFS[mode] or MODE_DEFS[mode:sub(1, 1)] or MODE_DEFS.n
    local accent = M.c[def.bg]
    local set = function(group, opts) pcall(vim.api.nvim_set_hl, 0, group, opts) end
    set("BufferLineBufferSelected",      { fg = M.c.text,  sp = accent, underline = true, bold = true })
    set("BufferLineIndicatorSelected",   { fg = accent,    sp = accent })
    set("BufferLineNumbersSelected",     { fg = M.c.text,  sp = accent, underline = true, bold = true })
    set("BufferLineModifiedSelected",    { fg = M.c.peach, sp = accent, underline = true })
    set("BufferLineDiagnosticSelected",  { fg = accent,    sp = accent, underline = true, bold = true })
    set("BufferLineErrorSelected",       { fg = M.c.red,   sp = accent, underline = true, bold = true })
    set("BufferLineWarningSelected",     { fg = M.c.yellow,sp = accent, underline = true, bold = true })
    set("BufferLineInfoSelected",        { fg = M.c.sky,   sp = accent, underline = true })
    set("BufferLineHintSelected",        { fg = M.c.teal,  sp = accent, underline = true })
    set("BufferLineErrorDiagnosticSelected",   { fg = M.c.red,    sp = accent, underline = true, bold = true })
    set("BufferLineWarningDiagnosticSelected", { fg = M.c.yellow, sp = accent, underline = true, bold = true })
    set("BufferLineInfoDiagnosticSelected",    { fg = M.c.sky,    sp = accent, underline = true })
    set("BufferLineHintDiagnosticSelected",    { fg = M.c.teal,   sp = accent, underline = true })
    set("BufferLineCloseButtonSelected", { fg = accent,    sp = accent, underline = true })
    set("BufferLinePickSelected",        { fg = accent,    sp = accent, underline = true, bold = true })
    set("BufferLineSeparatorSelected",   { fg = M.c.base,  bg = M.c.base })
    set("Cursor",      { fg = M.c.base, bg = accent })
    set("iCursor",     { fg = M.c.base, bg = accent })
    set("vCursor",     { fg = M.c.base, bg = accent })
    set("rCursor",     { fg = M.c.base, bg = accent })
    set("cCursor",     { fg = M.c.base, bg = accent })
    set("lCursor",     { fg = M.c.base, bg = accent })
    set("TermCursor",  { fg = M.c.base, bg = accent })
    set("FloatBorder",          { fg = accent })
    set("FloatTitle",           { fg = accent, bold = true })
    set("NormalFloatBorder",    { fg = accent })
    set("DiagnosticFloatingError", { fg = M.c.red })
    set("BlinkCmpMenuBorder",        { fg = accent })
    set("BlinkCmpDocBorder",         { fg = accent })
    set("BlinkCmpSignatureHelpBorder", { fg = accent })
    set("BlinkCmpMenuSelection",     { bg = M.c.surface, fg = accent, bold = true })
    set("LspSignatureActiveParameter", { fg = accent, bold = true })
    set("TelescopeBorder",         { fg = accent })
    set("TelescopePromptBorder",   { fg = accent })
    set("TelescopeResultsBorder",  { fg = accent })
    set("TelescopePreviewBorder",  { fg = accent })
    set("TelescopePromptTitle",    { fg = M.c.base, bg = accent, bold = true })
  end
  vim.api.nvim_create_autocmd("ModeChanged", { group = grp, callback = apply })
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = apply })
  vim.schedule(apply)
end

-- ─── cmd_duration timing hook ─────────────────────────────────────────────
local _cmd_start
function M._hook_cmd_timing()
  local grp = vim.api.nvim_create_augroup("user_starship_cmd_timing", { clear = true })
  vim.api.nvim_create_autocmd("CmdlineEnter", { group = grp, callback = function() _cmd_start = vim.uv.now() end })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = grp,
    callback = function() if _cmd_start then M._last_cmd_ms = vim.uv.now() - _cmd_start; _cmd_start = nil end end,
  })
end

-- ─── refresh hook (cheap event-driven repaints; async jobs do their own) ──
-- We deliberately exclude LspProgress here: it can fire 30+ times/sec during
-- workspace indexing and the lualine timer already catches it on the next tick.
function M._hook_refresh()
  local grp = vim.api.nvim_create_augroup("user_starship_refresh", { clear = true })
  vim.api.nvim_create_autocmd({
    "DiagnosticChanged", "LspAttach", "LspDetach",
    "BufWritePost", "BufEnter", "FileType", "VimResized",
  }, { group = grp, callback = lualine_refresh })
end

-- ─── render a chain of segments with powerline separators ──────────────────
local hl_cache = {}
local function hl(fg, bg, gui)
  local key = (fg or "") .. ":" .. (bg or "") .. ":" .. (gui or "")
  if hl_cache[key] then return hl_cache[key] end
  local name = "Starship_" .. tostring(vim.tbl_count(hl_cache))
  local attrs = { fg = fg, bg = bg }
  if gui and gui ~= "" then
    for a in tostring(gui):gmatch("[^,%s]+") do attrs[a] = true end
  end
  vim.api.nvim_set_hl(0, name, attrs)
  hl_cache[key] = name
  return name
end

local function sep_hl(prev_bg, next_bg)
  return hl(prev_bg, next_bg, nil)
end

-- ─── click dispatcher ─────────────────────────────────────────────────────
M._click_handlers = {}
local _next_click_id = 0

function M.on_click(id, clicks, button, mods)
  local fn = M._click_handlers[id]
  if fn then pcall(fn, button or "l", mods or "", clicks or 1) end
end
_G._user_starship_on_click = M.on_click

local function register_click(fn)
  _next_click_id = _next_click_id + 1
  local id = _next_click_id
  M._click_handlers[id] = fn
  return id
end

local function reset_clicks()
  M._click_handlers = {}
  _next_click_id = 0
end

function M.chain(segments, opts)
  opts = opts or {}
  if opts.side == "left" then reset_clicks() end
  local sep_l = opts.sep_l or ""
  local sep_r = opts.sep_r or ""
  local side = opts.side or "left"
  local prev_bg = nil
  local out = {}
  for _, seg in ipairs(segments) do
    if seg.text and seg.text ~= "" then
      local seg_hl = hl(seg.fg, seg.bg, seg.gui)
      local safe_text = (seg.text:gsub("%%", "%%%%"))
      if seg.on_click then
        local id = register_click(seg.on_click)
        safe_text = string.format("%%%d@v:lua._user_starship_on_click@%s%%X",
          id, safe_text)
      end
      if side == "left" then
        if prev_bg then
          table.insert(out, "%#" .. sep_hl(prev_bg, seg.bg) .. "#" .. sep_l)
        end
        table.insert(out, "%#" .. seg_hl .. "#" .. safe_text)
      else
        if prev_bg then
          table.insert(out, "%#" .. sep_hl(seg.bg, prev_bg) .. "#" .. sep_r)
        end
        table.insert(out, "%#" .. seg_hl .. "#" .. safe_text)
      end
      prev_bg = seg.bg
    end
  end
  if prev_bg then
    table.insert(out, "%#" .. hl(prev_bg, nil, nil) .. "#" .. (side == "left" and sep_l or sep_r))
  end
  table.insert(out, "%*")
  return table.concat(out)
end

-- ─── adaptive layout helpers ───────────────────────────────────────────────
-- Three tiers (per width brief):
--   <80   : critical only (mode, file:t, diag, location, save_pulse, conflicts,
--           dap_state, tasks; branch only if diag is empty)
--   80-119: + dir, file:., gitdiff, lsp, jira, todos, tab_undo, playbook_led,
--           one ops chip (aws)
--   ≥120  : + runtime/toolchain chips, k8s/terraform (when opt-in), ssh,
--           direnv, ambient context
local function pri(min_cols, fn)
  if vim.o.columns < min_cols then return { text = "" } end
  return fn()
end

local function clk(seg, fn)
  if seg and seg.text and seg.text ~= "" then
    seg.on_click = fn
    if seg.gui and seg.gui ~= "" then
      if not tostring(seg.gui):find("underline") then
        seg.gui = seg.gui .. ",underline"
      end
    else
      seg.gui = "underline"
    end
  end
  return seg
end

-- ─── click handler factories ──────────────────────────────────────────────
local function cmd(c) return function() pcall(vim.cmd, c) end end
local function lua(fn) return function() pcall(fn) end end
local function first_of(...)
  local cands = { ... }
  return function()
    for _, c in ipairs(cands) do
      if vim.fn.exists(":" .. (c:match("^(%w+)") or "")) > 0 then
        pcall(vim.cmd, c); return
      end
    end
  end
end
local function jump_first_conflict()
  local buf = vim.api.nvim_get_current_buf()
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:sub(1, 7) == "<<<<<<<" then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      vim.cmd("normal! zz")
      return
    end
  end
end

-- ─── left half ────────────────────────────────────────────────────────────
function M.left()
  -- Branch is suppressed at <80 cols when diagnostics are active, so the
  -- single-chip slot goes to the action signal, not the identity signal.
  local function git_or_skip()
    if vim.o.columns < 80 and diag_active() then return { text = "" } end
    return M.modules.git()
  end
  return M.chain({
    -- critical (always)
    M.modules.mode(),
    M.modules.macro(),
    M.modules.search(),
    clk(M.modules.conflicts(),              jump_first_conflict),
    -- normal tier: project root + relative path (file module is width-aware)
    clk(pri( 80, M.modules.dir),            lua(function() require("user.spotlight").open() end)),
    clk(    M.modules.file(),               lua(function() vim.cmd("e %") end)),
    -- git
    clk(    git_or_skip(),                  first_of("LazyGit", "Neogit")),
    clk(pri( 80, M.modules.gitdiff),        cmd("Gitsigns preview_hunk")),
    -- problems / language servers (diag is critical, lsp is normal)
    clk(    M.modules.diag(),               first_of("Trouble diagnostics toggle", "TroubleToggle", "Telescope diagnostics")),
    clk(pri( 80, M.modules.lsp),            cmd("Mason")),
    -- live indicators
    clk(pri( 80, M.modules.spinner),        lua(function() require("user.jobs").list() end)),
    clk(    M.modules.tasks(),              lua(function() require("user.dock").open("tasks") end)),
            M.modules.save_pulse(),
    clk(    M.modules.dap_state(),          first_of("DapContinue")),
    -- secondary
    clk(pri( 80, M.modules.jira),           lua(function() require("user.jira").show_issue() end)),
    clk(pri( 80, M.modules.todos),          first_of("TodoTrouble", "TodoTelescope")),
    clk(pri( 80, M.modules.tab_undo),       lua(function() require("user.tabs").pick() end)),
    clk(pri( 80, M.modules.playbook_led),   lua(function() require("user.playbooks").show() end)),
    -- ambient (wide tier)
    pri(120, M.modules.user_short),
            M.modules.ssh(),
    pri(120, M.modules.direnv),
  }, { side = "left" })
end

-- ─── right half ───────────────────────────────────────────────────────────
function M.right()
  return M.chain({
    -- assistants / timers
    clk(pri(120, M.modules.ai),             cmd("AI")),
    clk(pri(120, M.modules.pomo),           first_of("TimerStop", "TimerSession")),
    pri(120, M.modules.cmd_duration),
    -- runtime / toolchain (filetype-gated, one chip in practice; wide tier)
    pri(120, M.modules.lua),
    pri(120, M.modules.python),
    pri(120, M.modules.node),
    pri(120, M.modules.deno),
    pri(120, M.modules.bun),
    pri(120, M.modules.go),
    pri(120, M.modules.rust),
    pri(120, M.modules.ruby),
    pri(120, M.modules.elixir),
    pri(120, M.modules.java),
    pri(120, M.modules.zig),
    pri(120, M.modules.php),
    pri(120, M.modules.docker),
    -- ops context — opt-in async (k8s/terraform default off); aws always
    -- allowed at ≥80 since it's just an env var.
    pri( 80, M.modules.aws),
    pri(120, M.modules.k8s),
    pri(120, M.modules.terraform),
  }, { side = "right" })
end

function M.setup(opts)
  if type(opts) == "table" then
    if type(opts.ops) == "table" then
      M.opts.ops.k8s = opts.ops.k8s == true
      M.opts.ops.terraform = opts.ops.terraform == true
    end
  end
  M._hook_cmd_timing()
  M._hook_mode_accent()
  M._hook_save_pulse()
  M._hook_diag_chips()
  M._hook_refresh()
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = vim.api.nvim_create_augroup("user_starship_chip_cache", { clear = true }),
    callback = _flush_buf_cache,
  })
end

return M
