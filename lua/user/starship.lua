-- Starship-style dynamic statusline. Three rules:
--   1. Conditional segments — each module returns "" unless its context
--      applies, so the chain is naturally sparse when nothing's happening.
--   2. Three width tiers — critical (always), normal (≥80 cols),
--      wide (≥120 cols). Slim windows keep mode/file/diag/branch/cursor.
--   3. Color = signal — most chips render on `surface` bg so the eye treats
--      them as scannable context. Colored backgrounds are reserved for mode,
--      branch (accent), diagnostics, macro REC, conflicts, save pulse,
--      failed tasks, and risky context (prod/admin/main via risk_color()).
-- All shell-outs are cached via memo() so we don't fork on every redraw.
local M = {}

-- ─── color palette (catppuccin mocha) ───────────────────────────────────────
M.c = {
  base   = "#1e1e2e", surface = "#313244", overlay = "#6c7086", text = "#cdd6f4",
  red    = "#f38ba8", peach   = "#fab387", yellow  = "#f9e2af", green = "#a6e3a1",
  teal   = "#94e2d5", sky     = "#89dceb", sapphire= "#74c7ec", blue  = "#89b4fa",
  lavender = "#b4befe", mauve = "#cba6f7", pink = "#f5c2e7", flamingo = "#f2cdcd",
}

-- ─── simple TTL cache ───────────────────────────────────────────────────────
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

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function file_exists(p) return vim.uv.fs_stat(p) ~= nil end
local function find_up(name)
  local dir = vim.fn.getcwd()
  for _ = 1, 8 do
    if file_exists(dir .. "/" .. name) then return dir .. "/" .. name end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then return nil end
    dir = parent
  end
end

-- Severity-driven color for context-name chips (k8s, terraform, aws, cloud,
-- git branch). Order matters: "prod-admin" → critical, not warn.
-- Returns nil for benign contexts so the caller can fall back to its
-- calm/surface palette.
local function risk_color(name)
  local n = (name or ""):lower()
  if n:find("prod") or n:find("production") or n:find("live")
     or n:find("admin") or n:find("root") then
    return { bg = M.c.red,   fg = M.c.base, gui = "bold" }
  end
  if n == "main" or n == "master" then
    return { bg = M.c.peach, fg = M.c.base, gui = "bold" }
  end
  return nil
end

-- Trim a context string to last-path-segment, then ellipsize at `max`.
-- Defends against full kubeconfig ARNs, /etc/aws/... paths, etc. leaking
-- into the chain.
local function abbrev(s, max)
  if not s or s == "" then return "" end
  max = max or 18
  -- keep only the last path-like segment so cluster ARNs collapse to the bare name
  local tail = s:match("([^/:]+)$") or s
  if #tail > max then tail = tail:sub(1, max - 1) .. "…" end
  return tail
end

-- ─── visual helpers (sparklines, gauges, dots) ────────────────────────────
-- Reusable shape primitives. All cheap; no allocation in hot path except a
-- single table.concat per call.
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local BAR_LEVELS = { " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local DOT_ON, DOT_OFF = "●", "○"

-- History-based sparkline. Push `value` into the per-key ring buffer of size
-- `cap`, then render normalized to `max`. If `max` is omitted, normalizes
-- to the buffer's own peak — fine for trend-only signals but bad for steady
-- absolutes (a flat 99% RAM would render as all █). Pass `max` when the
-- value has a natural ceiling (100 for %, ncores*1.5 for load avg, etc).
M._spark = {}
function M.spark(key, value, cap, max)
  cap = cap or 10
  local s = M._spark[key]
  if not s then s = { samples = {} }; M._spark[key] = s end
  s.samples[#s.samples + 1] = value
  while #s.samples > cap do table.remove(s.samples, 1) end
  -- Determine scale: fixed if provided, else use the running max in the buffer
  local scale = max
  if not scale then
    scale = 0.0001
    for _, v in ipairs(s.samples) do if v > scale then scale = v end end
  end
  if scale <= 0 then scale = 0.0001 end
  local out = {}
  for i, v in ipairs(s.samples) do
    -- floor + 1 ensures equal-spaced bands (0..0.125 → ▁, 0.125..0.25 → ▂, …),
    -- so a steady 99% reads as `▇` and a flat 1% reads as `▁`, not all `█`.
    local norm = math.max(0, math.min(1, v / scale))
    local idx = math.min(#SPARK, math.floor(norm * #SPARK) + 1)
    out[i] = SPARK[idx]
  end
  return table.concat(out, "")
end

-- N-cell horizontal gauge for a single value 0..max. Returns `width` chars.
function M.bar(value, max, width)
  width = width or 4
  if not max or max == 0 then max = 1 end
  local norm = math.max(0, math.min(1, value / max))
  local idx = math.floor(norm * #BAR_LEVELS) + 1
  if idx > #BAR_LEVELS then idx = #BAR_LEVELS end
  return string.rep(BAR_LEVELS[idx], width)
end

-- ●●●○○ progress: `filled` of `total` dots filled. Clamps to [0, total].
function M.dots(filled, total)
  total = total or 5
  filled = math.max(0, math.min(total, filled))
  return string.rep(DOT_ON, filled) .. string.rep(DOT_OFF, total - filled)
end

-- ─── modules (segments). Each returns {text, fg} or {"", nil} when inactive ──
M.modules = {}

-- ─── MODE ─────────────────────────────────────────────────────────────────
-- Per-mode capsule: glyph + label + mode color. Replaces lualine's built-in
-- so the mode lives inside the same powerline chain as everything else.
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
M._mode_defs = MODE_DEFS  -- expose for other modules (e.g. for mode-aware accents)

function M.modules.mode()
  local m = vim.api.nvim_get_mode().mode
  local def = MODE_DEFS[m] or MODE_DEFS[m:sub(1, 1)] or MODE_DEFS["n"]
  return { text = (" %s %s "):format(def.icon, def.label),
           fg = M.c.base, bg = M.c[def.bg], gui = "bold" }
end

-- USERNAME / HOST (always visible)
function M.modules.user()
  local user = vim.env.USER or "user"
  local host = memo("hostname", 60000, function() return trim(vim.fn.hostname() or "") end):match("^[^.]+") or "?"
  return { text = (" %s@%s "):format(user, host), fg = M.c.base, bg = M.c.lavender, gui = "bold" }
end

-- DIR (cwd basename) — surface bg; this is scannable context, not an alert.
function M.modules.dir()
  local cwd = vim.fn.getcwd()
  local name = vim.fn.fnamemodify(cwd, ":t")
  return { text = ("  %s "):format(name), fg = M.c.text, bg = M.c.surface }
end

-- FILE — filename + modified/readonly markers for normal buffers. For
-- special buffers (help/term/qf/lazy/mason/oil/netrw) emits a friendly
-- label so the file slot stays meaningful instead of going blank.
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
  local short = vim.fn.fnamemodify(name, ":t")
  if short == "" then return { text = "" } end
  local ok, icons = pcall(require, "user.icons")
  local glyph = ok and icons.ft(name, ft).icon or ""
  local mod = vim.bo.modified and " ●" or ""
  local ro  = (vim.bo.readonly or not vim.bo.modifiable) and "  " or ""
  return { text = (" %s %s%s%s "):format(glyph, short, mod, ro),
           fg = M.c.text, bg = M.c.surface }
end

-- GIT BRANCH + AHEAD/BEHIND
function M.modules.git()
  local cwd = vim.fn.getcwd()
  local s = memo("git:" .. cwd, 5000, function()
    if vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --is-inside-work-tree 2>/dev/null")[1] ~= "true" then
      return ""
    end
    local branch = trim(vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --abbrev-ref HEAD")[1] or "")
    local ab = trim(vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-list --left-right --count @{upstream}...HEAD 2>/dev/null")[1] or "")
    local behind, ahead = ab:match("(%d+)%s+(%d+)")
    local stash = #vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " stash list 2>/dev/null")
    local out = " " .. branch
    if ahead and tonumber(ahead) > 0 then out = out .. " ↑" .. ahead end
    if behind and tonumber(behind) > 0 then out = out .. " ↓" .. behind end
    if stash > 0 then out = out .. "  " .. stash end
    return out
  end)
  if s == "" then return { text = "" } end
  -- main/master earns peach (warn) so you notice you're on the integration
  -- branch; everything else stays mauve (the global accent).
  local branch = s:match("^%s*([%S]+)") or ""
  local risk = risk_color(branch)
  if risk then
    return { text = " " .. s .. " ", fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = " " .. s .. " ", fg = M.c.base, bg = M.c.mauve, gui = "bold" }
end

-- GIT DIFF STATS (added / modified / deleted, with nerd-font glyphs)
function M.modules.gitdiff()
  local cwd = vim.fn.getcwd()
  local s = memo("gd:" .. cwd, 4000, function()
    local porcelain = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " status --porcelain 2>/dev/null")
    local a, m, d = 0, 0, 0
    for _, line in ipairs(porcelain) do
      local code = line:sub(1, 2)
      if code:match("[?A]") then a = a + 1
      elseif code:match("M") then m = m + 1
      elseif code:match("D") then d = d + 1 end
    end
    if a + m + d == 0 then return "" end
    local parts = {}
    if a > 0 then table.insert(parts, ("%d"):format(a)) end
    if m > 0 then table.insert(parts, ("%d"):format(m)) end
    if d > 0 then table.insert(parts, ("%d"):format(d)) end
    return table.concat(parts, " ")
  end)
  if s == "" then return { text = "" } end
  return { text = " " .. s .. " ", fg = M.c.text, bg = M.c.surface }
end

-- Runtime chips: icon-only at ≥120, surface bg. Version strings were dropped
-- to cut visual noise and remove ~9 background `vim.fn.system()` calls.
-- A short env tag (venv name, etc.) is allowed where it actually disambiguates.

function M.modules.python()
  local ft = vim.bo.filetype
  if ft ~= "python" and not find_up("pyproject.toml") and not find_up("requirements.txt") then
    return { text = "" }
  end
  local tag = ""
  local venv = vim.env.VIRTUAL_ENV
  if venv then tag = " " .. abbrev(vim.fn.fnamemodify(venv, ":t"), 12)
  elseif find_up(".venv/bin/python") then tag = " .venv" end
  return { text = (" 🐍%s "):format(tag), fg = M.c.text, bg = M.c.surface }
end

function M.modules.node()
  local ft = vim.bo.filetype
  local is_js = ft == "javascript" or ft == "typescript" or ft == "javascriptreact"
             or ft == "typescriptreact" or ft == "vue" or ft == "svelte"
  if not is_js and not find_up("package.json") then return { text = "" } end
  return { text = "   ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.go()
  if vim.bo.filetype ~= "go" and not find_up("go.mod") then return { text = "" } end
  return { text = " 🐹 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.rust()
  if vim.bo.filetype ~= "rust" and not find_up("Cargo.toml") then return { text = "" } end
  return { text = " 🦀 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.lua()
  if vim.bo.filetype ~= "lua" then return { text = "" } end
  return { text = " 󰢱 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.ruby()
  if vim.bo.filetype ~= "ruby" and not find_up("Gemfile") then return { text = "" } end
  return { text = " 💎 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.elixir()
  if vim.bo.filetype ~= "elixir" and not find_up("mix.exs") then return { text = "" } end
  return { text = " 💧 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.deno()
  if not find_up("deno.json") and not find_up("deno.jsonc") then return { text = "" } end
  return { text = " 󰟔 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.bun()
  if not find_up("bun.lock") and not find_up("bun.lockb") then return { text = "" } end
  return { text = " 󰳏 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.java()
  if vim.bo.filetype ~= "java"
     and not find_up("pom.xml") and not find_up("build.gradle")
     and not find_up("build.gradle.kts") then return { text = "" } end
  return { text = " 󰬷 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.zig()
  if vim.bo.filetype ~= "zig" and not find_up("build.zig") then return { text = "" } end
  return { text = " ↯ ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.php()
  if vim.bo.filetype ~= "php" and not find_up("composer.json") then return { text = "" } end
  return { text = " 🐘 ", fg = M.c.text, bg = M.c.surface }
end

function M.modules.docker()
  if not find_up("Dockerfile") and not find_up("docker-compose.yml") and not find_up("compose.yaml") then
    return { text = "" }
  end
  return { text = "   ", fg = M.c.text, bg = M.c.surface }
end

-- KUBERNETES (when k8s yaml in project, shows current kubectl context).
-- Context name is abbreviated to defang full cluster ARNs, then run through
-- risk_color so prod/admin clusters render red+bold.
function M.modules.k8s()
  local cwd = vim.fn.getcwd()
  local ctx = memo("k8s_proj:" .. cwd, 60000, function()
    if not find_up("Chart.yaml") and not find_up("kustomization.yaml") then
      local out = vim.fn.systemlist("grep -l --max-count=1 'kind:' " .. cwd .. "/*.yaml " .. cwd .. "/*.yml 2>/dev/null")
      if #out == 0 then return "" end
    end
    return trim(vim.fn.system("kubectl config current-context 2>/dev/null"))
  end)
  if ctx == "" then return { text = "" } end
  local short = abbrev(ctx, 18)
  local risk = risk_color(ctx)
  if risk then
    return { text = (" 󱃾 %s "):format(short), fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = (" 󱃾 %s "):format(short), fg = M.c.text, bg = M.c.surface }
end

-- TERRAFORM — workspace name, with risk coloring for prod-named workspaces.
function M.modules.terraform()
  if vim.bo.filetype ~= "terraform" and not find_up("main.tf") then return { text = "" } end
  local ws = memo("tfws", 30000, function()
    return trim(vim.fn.system("terraform workspace show 2>/dev/null"))
  end)
  local short = abbrev(ws ~= "" and ws or "tf", 14)
  local risk = risk_color(ws)
  if risk then
    return { text = (" 󱁢 %s "):format(short), fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = (" 󱁢 %s "):format(short), fg = M.c.text, bg = M.c.surface }
end

-- AWS profile — never renders raw access-key shaped strings (defense in depth
-- against $AWS_PROFILE being set to a session token by mistake).
function M.modules.aws()
  local p = vim.env.AWS_PROFILE
  if not p or p == "" then return { text = "" } end
  if p:match("^A[KS]IA[A-Z0-9]+$") or #p > 40 then return { text = "" } end
  local short = abbrev(p, 18)
  local risk = risk_color(p)
  if risk then
    return { text = (" 󰸏 %s "):format(short), fg = risk.fg, bg = risk.bg, gui = risk.gui }
  end
  return { text = (" 󰸏 %s "):format(short), fg = M.c.text, bg = M.c.surface }
end

-- BATTERY (macOS) — 11-step gradient on discharge, distinct charging glyphs
-- when on AC. Color escalates: red < 20%, peach < 40%, default otherwise.
-- Hidden when fully charged + plugged so it doesn't waste a slot.
local BATT_DISCHARGE = {  -- index 1..11 = 0%, 10%, 20%, ..., 100%
  "󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹",
}
local BATT_CHARGING  = {  -- charging variants (lightning bolt embedded)
  "󰢟", "󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅",
}

function M.modules.battery()
  if vim.fn.has("mac") ~= 1 then return { text = "" } end
  local s = memo("battery", 30000, function()
    local out = vim.fn.systemlist("pmset -g batt 2>/dev/null")[2] or ""
    local pct = tonumber(out:match("(%d+)%%"))
    local charging = out:match("AC Power") ~= nil
    if not pct then return "" end
    return string.format("%d|%s", pct, charging and "ac" or "bat")
  end)
  if s == "" then return { text = "" } end
  local pct, mode = s:match("(%d+)|(%w+)")
  pct = tonumber(pct)
  if mode == "ac" and pct >= 99 then return { text = "" } end  -- hide when fully charged + plugged
  local idx = math.max(1, math.min(11, math.floor(pct / 10) + 1))
  local icon = (mode == "ac" and BATT_CHARGING or BATT_DISCHARGE)[idx]
  local fg, bg = M.c.text, M.c.surface
  if mode == "bat" then
    if pct < 20      then fg, bg = M.c.base, M.c.red
    elseif pct < 40  then fg = M.c.peach end
  elseif mode == "ac" then
    fg = M.c.green   -- charging always reads positive
  end
  return { text = (" %s %d%% "):format(icon, pct), fg = fg, bg = bg, gui = (pct < 20 and "bold" or nil) }
end

-- TIME — glyph cycles with time of day: sunrise → midday → sunset → moon.
-- Small detail but the chip changes character through the day, marking
-- passage subtly without being a clock.
function M.modules.time()
  local h = tonumber(os.date("%H"))
  local glyph
  if     h >= 5  and h < 8  then glyph = "󰖜"      -- sunrise
  elseif h >= 8  and h < 17 then glyph = "󰖙"      -- midday sun
  elseif h >= 17 and h < 20 then glyph = "󰖚"      -- sunset
  else                            glyph = "󰖔" end  -- moon / night
  return { text = (" %s %s "):format(glyph, os.date("%H:%M")),
           fg = M.c.text, bg = M.c.surface }
end

-- ─── EXTENDED MODULES ──────────────────────────────────────────────────────

-- OS — show only on first render OR if SSH (else clutter)
function M.modules.os()
  local k = vim.uv.os_uname()
  local sys = (k.sysname or ""):lower()
  local icon, fg = "  ", M.c.text
  if sys:find("darwin") then icon = "  "; fg = M.c.text
  elseif sys:find("linux") then
    local distro = ""
    local f = io.open("/etc/os-release", "r")
    if f then distro = (f:read("*a") or ""):lower(); f:close() end
    if distro:find("ubuntu") then icon = "  "; fg = "#e95420"
    elseif distro:find("arch") then icon = "  "; fg = M.c.sapphire
    elseif distro:find("debian") then icon = "  "; fg = M.c.red
    elseif distro:find("fedora") then icon = "  "; fg = M.c.blue
    elseif distro:find("nix") then icon = "  "; fg = M.c.sapphire
    else icon = "  "; fg = M.c.text end
  elseif sys:find("windows") then icon = "  "; fg = M.c.sky end
  return { text = icon, fg = fg, bg = M.c.surface }
end

-- SSH HOSTNAME — only when connected via SSH
function M.modules.ssh()
  if not vim.env.SSH_CLIENT and not vim.env.SSH_TTY then return { text = "" } end
  local host = memo("hostname", 60000, function() return trim(vim.fn.hostname() or "") end):match("^[^.]+") or "?"
  return { text = ("  %s "):format(host), fg = M.c.base, bg = M.c.flamingo, gui = "bold" }
end

-- PROJECT TYPE — autodetect (npm/cargo/go/poetry/etc.)
function M.modules.project_type()
  local cwd = vim.fn.getcwd()
  local kind = memo("ptype:" .. cwd, 30000, function()
    if find_up("Cargo.toml") then return "rust"
    elseif find_up("go.mod") then return "go"
    elseif find_up("pyproject.toml") then return "poetry"
    elseif find_up("package.json") then return "node"
    elseif find_up("Gemfile") then return "ruby"
    elseif find_up("mix.exs") then return "elixir"
    elseif find_up("Makefile") then return "make"
    elseif find_up("CMakeLists.txt") then return "cmake"
    elseif find_up("BUILD.bazel") or find_up("BUILD") then return "bazel"
    elseif find_up("flake.nix") then return "nix"
    end
    return ""
  end)
  if kind == "" then return { text = "" } end
  local icons = { rust = "  ", go = " 󰟓 ", poetry = "  ", node = "  ",
    ruby = "  ", elixir = "  ", make = " 󱁤 ", cmake = " 󰔷 ", bazel = "  ", nix = "  " }
  return { text = (icons[kind] or "  ") .. kind .. " ", fg = M.c.text, bg = M.c.surface }
end

-- PACKAGE VERSION — reads this project's own version
function M.modules.package_version()
  local cwd = vim.fn.getcwd()
  local v = memo("pkgver:" .. cwd, 30000, function()
    local cargo = find_up("Cargo.toml")
    if cargo then
      for line in io.lines(cargo) do
        local m = line:match('^version%s*=%s*"([^"]+)"'); if m then return m end
        if line:match("^%[%w") and not line:match("^%[package%]") then break end
      end
    end
    local pyproj = find_up("pyproject.toml")
    if pyproj then
      for line in io.lines(pyproj) do
        local m = line:match('^version%s*=%s*"([^"]+)"'); if m then return m end
      end
    end
    local pkg = find_up("package.json")
    if pkg then
      local f = io.open(pkg, "r"); if f then
        local data = f:read("*a"); f:close()
        local ok, parsed = pcall(vim.json.decode, data)
        if ok and parsed.version then return parsed.version end
      end
    end
    return ""
  end)
  if v == "" then return { text = "" } end
  return { text = (" 󰏗 v%s "):format(v), fg = M.c.text, bg = M.c.surface }
end

-- CMD DURATION — populated by hook in setup(), shows last cmd's runtime
M._last_cmd_ms = 0
function M.modules.cmd_duration()
  local ms = M._last_cmd_ms
  if ms < 500 then return { text = "" } end  -- only show if >500ms (starship default)
  local txt
  if ms < 1000 then txt = ms .. "ms"
  elseif ms < 60000 then txt = string.format("%.1fs", ms / 1000)
  else txt = string.format("%dm%ds", math.floor(ms / 60000), math.floor((ms % 60000) / 1000)) end
  return { text = ("  took %s "):format(txt), fg = M.c.yellow, bg = M.c.surface, gui = "italic" }
end

-- CPU LOAD — rolling sparkline of normalized 1-min load (last 10 samples)
function M.modules.cpu()
  local s = memo("cpu", 4000, function()
    local out = trim(vim.fn.system("uptime 2>/dev/null"))
    local one = tonumber(out:match("load averages?:%s*([%d%.]+)") or out:match("load average:%s*([%d%.]+)"))
    if not one then return "" end
    local cores = tonumber(vim.fn.system("getconf _NPROCESSORS_ONLN 2>/dev/null") or "1") or 1
    return ("%.2f|%d"):format(one, cores)
  end)
  if s == "" then return { text = "" } end
  local one_str, cores_str = s:match("([%d%.]+)|(%d+)")
  local one, cores = tonumber(one_str) or 0, tonumber(cores_str) or 1
  local norm = one / math.max(1, cores)   -- 0 = idle, 1 = fully loaded
  -- Fixed scale 0..1.5 so a flat 50%-loaded box reads as ▅, not █.
  local spark = M.spark("cpu", norm, 6, 1.5)
  local fg = M.c.text
  if norm > 1 then fg = M.c.red elseif norm > 0.75 then fg = M.c.peach end
  return { text = (" 󰍛 %s %.2f "):format(spark, one), fg = fg, bg = M.c.surface }
end

-- RAM USAGE — % used
function M.modules.ram()
  local s = memo("ram", 5000, function()
    if vim.fn.has("mac") == 1 then
      local pages = trim(vim.fn.system("vm_stat 2>/dev/null"))
      local free = tonumber(pages:match("Pages free:%s*(%d+)") or "0")
      local active = tonumber(pages:match("Pages active:%s*(%d+)") or "0")
      local wired = tonumber(pages:match("Pages wired down:%s*(%d+)") or "0")
      local compressed = tonumber(pages:match("Pages occupied by compressor:%s*(%d+)") or "0")
      local total = free + active + wired + compressed
      if total == 0 then return "" end
      local used = active + wired + compressed
      return tostring(math.floor((used / total) * 100))
    end
    -- linux /proc/meminfo
    local f = io.open("/proc/meminfo", "r"); if not f then return "" end
    local data = f:read("*a"); f:close()
    local total = tonumber(data:match("MemTotal:%s+(%d+)") or "0")
    local avail = tonumber(data:match("MemAvailable:%s+(%d+)") or "0")
    if total == 0 then return "" end
    return tostring(math.floor((1 - avail / total) * 100))
  end)
  if s == "" then return { text = "" } end
  local pct = tonumber(s) or 0
  -- Fixed 0..100 scale: 99% → ▇, 50% → ▄, 12% → ▁, never all `█` from
  -- buffer-relative normalization on a steady metric.
  local spark = M.spark("ram", pct, 6, 100)
  local fg = M.c.text
  if pct > 90 then fg = M.c.red elseif pct > 75 then fg = M.c.peach end
  return { text = (" 󰘚 %s %d%% "):format(spark, pct), fg = fg, bg = M.c.surface }
end

-- CLOUD ACCOUNT — gcloud / aws (whichever is set). Surface bg unless the
-- account name itself flags risk (e.g. prod-admin@…).
function M.modules.cloud()
  if vim.env.CLOUDSDK_ACTIVE_CONFIG_NAME or vim.fn.executable("gcloud") == 1 then
    local acct = memo("gcloud", 60000, function()
      return trim(vim.fn.system("gcloud config get-value account 2>/dev/null"))
    end)
    if acct ~= "" and not acct:find("ERROR") then
      local short = abbrev(acct:match("([^@]+)") or acct, 18)
      local risk = risk_color(acct)
      if risk then return { text = (" 󱇶 %s "):format(short), fg = risk.fg, bg = risk.bg, gui = risk.gui } end
      return { text = (" 󱇶 %s "):format(short), fg = M.c.text, bg = M.c.surface }
    end
  end
  return { text = "" }
end

-- DIRENV — when .envrc was sourced in this shell
function M.modules.direnv()
  if not vim.env.DIRENV_DIR then return { text = "" } end
  return { text = "  direnv ", fg = M.c.base, bg = M.c.green }
end

-- UPDATE AVAILABLE — shows ↓N when local is behind upstream
function M.modules.update()
  local cwd = vim.fn.getcwd()
  local s = memo("upstream:" .. cwd, 60000, function()
    -- background fetch (don't block) once per minute
    vim.fn.jobstart("git -C " .. vim.fn.shellescape(cwd) .. " fetch --quiet 2>/dev/null", { detach = true })
    local out = trim(vim.fn.system("git -C " .. vim.fn.shellescape(cwd) .. " rev-list --count HEAD..@{upstream} 2>/dev/null"))
    return out
  end)
  local n = tonumber(s)
  if not n or n == 0 then return { text = "" } end
  return { text = (" ↓%d "):format(n), fg = M.c.base, bg = M.c.red, gui = "bold" }
end

-- AI STATUS — combined Copilot ✓/⏳ + Avante ✦ indicator
function M.modules.ai()
  local parts = {}
  local cop_ok, cop_api = pcall(require, "copilot.api")
  if cop_ok then
    local s = cop_api.status.data.status
    if s == "InProgress" then table.insert(parts, { "  ", M.c.yellow })
    elseif s == "Warning" then table.insert(parts, { "  ", M.c.red })
    else table.insert(parts, { "  ", M.c.green }) end
  end
  if vim.env.ANTHROPIC_API_KEY then
    table.insert(parts, { " ✦ ", M.c.mauve })
  end
  if #parts == 0 then return { text = "" } end
  -- Combine — return a multi-color via composed text (simplified: pick first color)
  local txt = ""
  for _, p in ipairs(parts) do txt = txt .. p[1] end
  return { text = txt, fg = parts[1][2], bg = M.c.surface }
end

-- POMO — current pomodoro timer
function M.modules.pomo()
  local ok, pomo = pcall(require, "pomo")
  if not ok then return { text = "" } end
  local t = pomo.get_first_to_finish()
  if not t then return { text = "" } end
  return { text = ("  %s %s "):format(t:remaining_time_str(), t.name or ""), fg = M.c.base, bg = M.c.peach, gui = "bold" }
end

-- ─── SPINNER ──────────────────────────────────────────────────────────────
-- Animated frames when user.jobs has running tasks. Frame index derives from
-- vim.uv.now() so all callers stay phase-locked. Lualine's refresh tick is
-- what advances it visually (see refresh.statusline = 100 in ui.lua).
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
-- Connected LSP servers for the current buffer, dot-separated. Hidden in
-- special buftypes (terminal, prompt, etc.).
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
  -- More than 3 attached clients → "lua·tsserver·+2" form. Total label
  -- capped at 24 chars before the chip padding so a noisy ecosystem
  -- (linters + formatters + null_ls) doesn't blow up the chain.
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
-- Buffer-scoped diagnostic capsule. Bg = highest severity color so the line
-- visually escalates with problem severity.
function M.modules.diag()
  local d = vim.diagnostic.count(0)
  local e, w, i, h = d[1] or 0, d[2] or 0, d[3] or 0, d[4] or 0
  if e + w + i + h == 0 then return { text = "" } end
  local parts = {}
  if e > 0 then table.insert(parts, ("  %d"):format(e)) end
  if w > 0 then table.insert(parts, ("  %d"):format(w)) end
  if i > 0 then table.insert(parts, ("  %d"):format(i)) end
  if h > 0 then table.insert(parts, (" 󰌵 %d"):format(h)) end
  local bg
  if e > 0 then bg = M.c.red
  elseif w > 0 then bg = M.c.yellow
  elseif i > 0 then bg = M.c.sky
  else bg = M.c.teal end
  return { text = " " .. table.concat(parts, " ") .. " ",
           fg = M.c.base, bg = bg, gui = "bold" }
end

-- ─── MACRO RECORDING ──────────────────────────────────────────────────────
-- Pulsing red capsule while recording. Pulse period = 500ms (slower than the
-- spinner) so the eye reads it as urgent but not jittery.
function M.modules.macro()
  local reg = vim.fn.reg_recording()
  if reg == "" then return { text = "" } end
  local lit = (math.floor(vim.uv.now() / 500) % 2) == 0
  local icon = lit and "" or ""   -- nerd-font record glyph / empty circle
  return { text = (" %s REC @%s "):format(icon, reg),
           fg = M.c.base, bg = M.c.red, gui = "bold" }
end

-- ─── SAVE PULSE ───────────────────────────────────────────────────────────
-- Brief "✓ saved · file.lua" chip after every BufWritePost. Fades after
-- PULSE_MS via lualine's own refresh tick (no separate timer needed). Color
-- flips red+message on save errors so it doubles as a write-failed indicator.
M._save_pulse = nil  -- { until_ms, name, ok }
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
  -- Catch failed writes too (BufWriteCmd errors / readonly attempts)
  vim.api.nvim_create_autocmd({ "BufWritePre" }, {
    group = grp,
    callback = function(ev)
      -- Sentinel: clear stale pulse so failed writes start clean
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
  -- Three-phase fade: green (full) → teal (mid) → sapphire (dim). On error,
  -- stays red the whole window so the eye locks onto the failure. The eye
  -- reads the color shift as a smooth fade even though it's discrete steps.
  local total = PULSE_MS
  local pct_remaining = remaining / total
  local bg
  if p.ok then
    if pct_remaining > 0.66 then bg = M.c.green
    elseif pct_remaining > 0.33 then bg = M.c.teal
    else bg = M.c.sapphire end
  else
    bg = M.c.red
  end
  local icon = p.ok and "" or ""   -- nerd-font check / cross
  local name = p.name
  if #name > 22 then name = name:sub(1, 20) .. "…" end
  return { text = (" %s saved · %s "):format(icon, name),
           fg = M.c.base, bg = bg, gui = "bold" }
end

-- ─── ENGAGEMENT ───────────────────────────────────────────────────────────
-- "⌨ 2.4k · 47m" chip: keystrokes today (persisted across sessions, resets
-- daily) + minutes since this nvim's VimEnter. vim.on_key counts every typed
-- key; writes batch to disk every 5s to avoid thrash.
M._engage = { keys_today = 0, date = nil, session_start_ms = nil,
               streak = 0, last_active = nil }
local function _engage_path() return vim.fn.stdpath("state") .. "/engagement.json" end

-- Returns true if `b_date` is the calendar day immediately after `a_date`.
-- Strict day-after means: dates parse as 1 day apart (handles month boundaries
-- via os.time + 86400 round-trip).
local function _day_after(a, b)
  if not a or not b then return false end
  local ay, am, ad = a:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
  if not ay then return false end
  local a_ts = os.time({ year = tonumber(ay), month = tonumber(am), day = tonumber(ad), hour = 12 })
  local expected = os.date("%Y-%m-%d", a_ts + 86400)
  return expected == b
end

local function _engage_load()
  local f = io.open(_engage_path(), "r")
  if not f then return end
  local raw = f:read("*a") or "{}"
  f:close()
  local ok, data = pcall(vim.json.decode, raw)
  if not (ok and type(data) == "table") then return end
  local today = os.date("%Y-%m-%d")
  if data.date == today then M._engage.keys_today = tonumber(data.keys) or 0 end
  M._engage.date = today
  -- Streak bookkeeping. Bump on first load of a new day, reset if a day gapped.
  local last = data.last_active
  local prev_streak = tonumber(data.streak) or 0
  if last == today then
    M._engage.streak = prev_streak                 -- already counted today
  elseif _day_after(last, today) then
    M._engage.streak = prev_streak + 1             -- continuous: extend
  else
    M._engage.streak = 1                           -- first day or gap: restart
  end
  M._engage.last_active = today
end

local function _engage_save()
  local f = io.open(_engage_path(), "w")
  if not f then return end
  f:write(vim.json.encode({
    date        = M._engage.date,
    keys        = M._engage.keys_today,
    streak      = M._engage.streak,
    last_active = M._engage.last_active,
  }))
  f:close()
end

local _engage_save_pending = false
local function _engage_schedule_save()
  if _engage_save_pending then return end
  _engage_save_pending = true
  vim.defer_fn(function() _engage_save(); _engage_save_pending = false end, 5000)
end

function M._hook_engagement()
  _engage_load()
  if not M._engage.date then M._engage.date = os.date("%Y-%m-%d") end
  M._engage.session_start_ms = vim.uv.now()
  vim.on_key(function(_, typed)
    if not typed or #typed == 0 then return end
    -- Roll over at midnight
    local today = os.date("%Y-%m-%d")
    if today ~= M._engage.date then
      _engage_save()  -- persist yesterday's final count before reset
      M._engage.date = today
      M._engage.keys_today = 0
    end
    M._engage.keys_today = M._engage.keys_today + 1
    _engage_schedule_save()
  end)
  vim.api.nvim_create_autocmd("VimLeavePre", { callback = _engage_save })
end

local function _fmt_count(n)
  if n < 1000 then return tostring(n) end
  if n < 10000 then return string.format("%.1fk", n / 1000) end  -- 1.5k, 9.9k
  return string.format("%dk", math.floor(n / 1000))              -- 10k, 47k, 234k
end

-- Daily keystroke target. Drives the ●●●○○ progress dots in the engage chip.
-- Anything reasonable; 5k is roughly a sustained writing day.
local ENGAGE_DAILY_GOAL = 5000

function M.modules.engage()
  if not M._engage.session_start_ms then return { text = "" } end
  local mins = math.floor((vim.uv.now() - M._engage.session_start_ms) / 60000)
  local filled = math.floor(M._engage.keys_today / ENGAGE_DAILY_GOAL * 5 + 0.001)
  local dots = M.dots(filled, 5)
  -- Color the chip mauve once you've hit the goal; otherwise stays neutral.
  local bg, fg = M.c.surface, M.c.text
  if filled >= 5 then bg, fg = M.c.mauve, M.c.base end
  return { text = (" 󰌌 %s %s · %dm "):format(_fmt_count(M._engage.keys_today), dots, mins),
           fg = fg, bg = bg }
end

-- Streak chip — consecutive days used. Hidden at streak ≤ 1 (no gloating on
-- day 0/1; chip emerges day 2 onward to mark genuine continuity).
function M.modules.streak()
  local s = M._engage.streak or 0
  if s <= 1 then return { text = "" } end
  -- Color escalates with streak length so longer streaks pop visually.
  local bg
  if s >= 30 then bg = M.c.mauve         -- "month+" — top tier
  elseif s >= 14 then bg = M.c.peach     -- "two weeks" — hot
  elseif s >= 7 then bg = M.c.yellow     -- "week" — warm
  else bg = M.c.surface end              -- 2-6 days — subtle
  return { text = (" 󰈸 %dd "):format(s),    -- nerd-font flame
           fg = (bg == M.c.surface) and M.c.text or M.c.base, bg = bg, gui = "bold" }
end

-- ─── DIAGNOSTIC SIGN CHIPS ────────────────────────────────────────────────
-- Override default DiagnosticSign* groups so the gutter signs render as
-- severity-colored chips (base fg + severity bg, bold) instead of fg-only
-- glyphs. The existing diagnostic config in lsp.lua provides the icons;
-- this hook just retints them. Re-applied on ColorScheme so theme reloads
-- don't strip the chips.
function M._hook_diag_chips()
  local grp = vim.api.nvim_create_augroup("user_starship_diag_chips", { clear = true })
  local function apply()
    local set = function(g, opts) pcall(vim.api.nvim_set_hl, 0, g, opts) end
    set("DiagnosticSignError", { fg = M.c.base, bg = M.c.red,    bold = true })
    set("DiagnosticSignWarn",  { fg = M.c.base, bg = M.c.yellow, bold = true })
    set("DiagnosticSignInfo",  { fg = M.c.base, bg = M.c.sky,    bold = true })
    set("DiagnosticSignHint",  { fg = M.c.base, bg = M.c.teal,   bold = true })
    -- Older Catppuccin uses the *_Sign suffix or no suffix; cover both.
    set("DiagnosticError",     { fg = M.c.red })
    set("DiagnosticWarn",      { fg = M.c.yellow })
    set("DiagnosticInfo",      { fg = M.c.sky })
    set("DiagnosticHint",      { fg = M.c.teal })
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = apply })
  vim.schedule(apply)
end

-- ─── HEARTBEAT ────────────────────────────────────────────────────────────
-- Once a minute, a faint ♥/♡ pulses in the chain for 200ms. Pure delight
-- detail — signals "the editor is alive" without ever demanding attention.
-- The 200ms window is anchored on a 60s minute mark from vim.uv.now() so it
-- fires deterministically (not on every 0.1s tick).
function M.modules.heartbeat()
  local now = vim.uv.now()
  local since_minute = now % 60000
  if since_minute > 200 then return { text = "" } end
  -- Two frames inside the 200ms window: ♥ for first half, ♡ for second half
  local lit = since_minute < 100
  return { text = " " .. (lit and "♥" or "♡") .. " ",
           fg = M.c.red, bg = M.c.surface }
end

-- ─── PLAYBOOK LED ─────────────────────────────────────────────────────────
-- Shows the most recently fired playbook name + age, color-coded by outcome
-- (running=sapphire, done=green, error=red). Fades from the chain after 10
-- minutes (driven by playbooks.last_fired() returning nil past TTL).
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
  -- Truncate long playbook names so the chain doesn't explode
  local name = last.name or "playbook"
  if #name > 20 then name = name:sub(1, 18) .. "…" end
  return { text = (" %s %s · %s "):format(icon, name, fmt_age(age)),
           fg = M.c.base, bg = bg, gui = "bold" }
end

-- ─── OVERSEER TASKS ───────────────────────────────────────────────────────
-- Running task count from overseer, color-coded. Hidden when no tasks run.
-- Click → opens the Dock's Tasks tab.
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
-- All three cache per (buf, changedtick) so they cost ~one table lookup per
-- redraw on unchanged buffers. They auto-hide when their count is zero or
-- the context doesn't apply, so the chain stays tight when nothing's wrong.

local _todo_cache, _conflict_cache = {}, {}

local function _bufprep()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then return nil end
  return buf, vim.api.nvim_buf_get_changedtick(buf)
end

-- TODO / FIXME / HACK / XXX in current buffer. Capped scan at 5000 lines so
-- enormous generated files don't slow the redraw.
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

-- Unresolved merge-conflict markers in current buffer. Promoted to red bg
-- because this is exactly the "OH" moment — you don't want to commit yet.
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

-- DAP session state — only present when a debug session is active.
-- Stopped → mauve+icon highlight; running → teal; everything else hidden.
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

-- Ambient transparency (Pousman & Stasko 2006 "A Taxonomy of Ambient
-- Information Systems"; Hassenzahl 2010 "Experience Design"; modern:
-- explainable AI / transparent automation 2020s applied to any system
-- holding state for the user). The persistent undo stack quietly carries
-- closed-tab recovery across sessions — without surfacing that state in
-- the periphery, the user has no way to *know* the tool is holding work
-- for them. Risko & Gilbert (2016) explicitly call this out as the trust
-- gap that makes cognitive offloading fail in practice.
--
-- Invisible when the stack is empty (zero state = zero ink — calm tech
-- preserved). One soft `↺N` chip when there's recovery available. Click
-- opens the picker, which shows ghost rows for every closed tab.
function M.modules.tab_undo()
  local ok, tabs = pcall(require, "user.tabs"); if not ok then return { text = "" } end
  local n = (tabs.closed_count and tabs.closed_count()) or 0
  if n == 0 then return { text = "" } end
  return { text = (" ↺%d "):format(n), fg = M.c.base, bg = M.c.green, gui = "bold" }
end

-- Drop cached entries when the buffer is wiped so the tables don't leak.
local function _flush_buf_cache(args)
  _todo_cache[args.buf] = nil
  _conflict_cache[args.buf] = nil
end

-- ─── JIRA TICKET CHIP ─────────────────────────────────────────────────────
-- Shows the branch's ticket key + status. Cheap: never makes an HTTP call —
-- only reads jira's in-memory cache (populated when you open a ticket via
-- :JiraIssue or <leader>ji). Branch parse is cached for 3s in user.jira.
function M.modules.jira()
  local ok, jira = pcall(require, "user.jira"); if not ok then return { text = "" } end
  local seg = jira.statusline_segment(M.c)
  return seg or { text = "" }
end

-- ─── SEARCH MATCHES ───────────────────────────────────────────────────────
-- "[3/47]" while a /-search is active. Cheap; reuses searchcount.
function M.modules.search()
  if vim.v.hlsearch == 0 then return { text = "" } end
  local ok, sc = pcall(vim.fn.searchcount, { recompute = 1, maxcount = 999 })
  if not ok or not sc or not sc.total or sc.total == 0 then return { text = "" } end
  return { text = (" 󰍉 %d/%d "):format(sc.current or 0, sc.total),
           fg = M.c.base, bg = M.c.flamingo, gui = "bold" }
end

-- USER PROMPT (root indicator)
function M.modules.user_short()
  local user = vim.env.USER or "user"
  local is_root = vim.uv.os_getenv("USER") == "root" or (vim.uv.os_getuid and vim.uv.os_getuid() == 0)
  local bg = is_root and M.c.red or M.c.lavender
  local prefix = is_root and "# " or " "
  return { text = (prefix .. "%s "):format(user), fg = M.c.base, bg = bg, gui = "bold" }
end

-- ─── mode-reactive bufferline accent ──────────────────────────────────────
-- Retints the bufferline's selected-buffer underline + indicator to match the
-- current mode color. So switching to INSERT shifts the active tab's
-- underline green, REPLACE shifts it red, VISUAL shifts it mauve — the whole
-- UI (statusline + compass + bufferline) breathes together with mode.
function M._hook_mode_accent()
  local grp = vim.api.nvim_create_augroup("user_starship_mode_accent", { clear = true })
  local function apply()
    local mode = vim.api.nvim_get_mode().mode
    local def = MODE_DEFS[mode] or MODE_DEFS[mode:sub(1, 1)] or MODE_DEFS.n
    local accent = M.c[def.bg]
    -- All highlights via pcall so plugin order doesn't break us.
    local set = function(group, opts)
      pcall(vim.api.nvim_set_hl, 0, group, opts)
    end
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
    -- Cursor itself — most-watched pixel on screen. Retinting Cursor +
    -- per-mode variants means the cursor shifts color with mode along with
    -- statusline/bufferline/compass. Default guicursor maps every mode to
    -- one of these so a single autocmd covers all of them.
    set("Cursor",                        { fg = M.c.base,  bg = accent })
    set("iCursor",                       { fg = M.c.base,  bg = accent })
    set("vCursor",                       { fg = M.c.base,  bg = accent })
    set("rCursor",                       { fg = M.c.base,  bg = accent })
    set("cCursor",                       { fg = M.c.base,  bg = accent })
    set("lCursor",                       { fg = M.c.base,  bg = accent })
    set("TermCursor",                    { fg = M.c.base,  bg = accent })
    -- Popup / float borders — completes the color-flow story by extending it
    -- into hover docs, signature help, diagnostics floats, completion menu,
    -- and signature popups. fg-only so backgrounds stay readable, and floats
    -- that set their own winhighlight (compass, brand panels) are unaffected.
    set("FloatBorder",                   { fg = accent })
    set("FloatTitle",                    { fg = accent, bold = true })
    set("NormalFloatBorder",             { fg = accent })
    set("DiagnosticFloatingError",       { fg = M.c.red })
    set("BlinkCmpMenuBorder",            { fg = accent })
    set("BlinkCmpDocBorder",             { fg = accent })
    set("BlinkCmpSignatureHelpBorder",   { fg = accent })
    set("BlinkCmpMenuSelection",         { bg = M.c.surface, fg = accent, bold = true })
    set("LspSignatureActiveParameter",   { fg = accent, bold = true })
    -- Telescope (if installed) — only border fg, never background
    set("TelescopeBorder",               { fg = accent })
    set("TelescopePromptBorder",         { fg = accent })
    set("TelescopeResultsBorder",        { fg = accent })
    set("TelescopePreviewBorder",        { fg = accent })
    set("TelescopePromptTitle",          { fg = M.c.base, bg = accent, bold = true })
  end
  vim.api.nvim_create_autocmd("ModeChanged", { group = grp, callback = apply })
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = apply })
  vim.schedule(apply)
end

-- ─── cmd_duration timing hook (CmdlineEnter → CmdlineLeave) ────────────────
local _cmd_start
function M._hook_cmd_timing()
  local grp = vim.api.nvim_create_augroup("user_starship_cmd_timing", { clear = true })
  vim.api.nvim_create_autocmd("CmdlineEnter", { group = grp, callback = function() _cmd_start = vim.uv.now() end })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = grp,
    callback = function() if _cmd_start then M._last_cmd_ms = vim.uv.now() - _cmd_start; _cmd_start = nil end end,
  })
end

-- ─── render a chain of segments with powerline separators ──────────────────
-- Renders into a lualine component string using %#hl#...%* tags. We
-- pre-register highlight groups for each (fg, bg) pair we use.
-- `gui` may be a single attribute ("bold") or comma-separated list
-- ("bold,underline") so that clk() can append an interactivity signifier
-- without clobbering an existing weight (see clk() below for the rationale
-- — Norman 2013 affordance ≠ signifier reapplied to dense ambient displays).
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
  -- A separator's foreground = the previous segment's background, blended
  -- on top of the next segment's background. So fg=prev_bg, bg=next_bg.
  return hl(prev_bg, next_bg, nil)
end

-- chain {...segments} -> "%#hlA# text %#sepAB# %#hlB# text %*"
-- ─── click dispatcher ─────────────────────────────────────────────────────
-- A statusline segment can include `on_click = function(button, mods) ... end`.
-- chain() wraps that segment in vim's `%@FuncName@text%X` click escape, so
-- the cell becomes clickable. `M.on_click(id)` looks the function up and
-- invokes it.
--
-- Implementation note: the %@ escape only fires the dispatcher with no args
-- (the function name is fixed: `v:lua.require'user.starship'.on_click`). We
-- bridge by stashing the id in the URL slot. The id comes from a per-render
-- table flushed before each rebuild so it never grows.
M._click_handlers = {}
local _next_click_id = 0

-- Vim invokes %@v:lua.NAME@text%X with (minwid, clicks, button, mods).
-- We stash the handler id in minwid and look it up here. Exposed as a
-- bare global so the %@ escape can resolve it without a `require()` parse.
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
  -- Reset per-render so old handler tables don't accumulate. Both halves of
  -- the line are rebuilt every redraw, so flushing on left() entry covers both.
  if opts.side == "left" then reset_clicks() end
  local sep_l = opts.sep_l or ""    -- powerline left   (filled wedge)
  local sep_r = opts.sep_r or ""    -- powerline right  (filled wedge)
  local side = opts.side or "left"
  local prev_bg = nil
  local out = {}
  for _, seg in ipairs(segments) do
    if seg.text and seg.text ~= "" then
      local seg_hl = hl(seg.fg, seg.bg, seg.gui)
      -- Defense in depth: escape literal `%` inside chip text so user-supplied
      -- strings (filenames, branch names, playbook names) can never produce a
      -- malformed statusline format directive ("% " → E539). Our `%#hl#`
      -- markers are added BY this function, after escaping, so they survive.
      local safe_text = (seg.text:gsub("%%", "%%%%"))
      -- Wrap the colored text in a click region when the segment ships one.
      -- The `id` round-trips: `%<id>@func@text%X` calls `func(id, ...)`.
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
  -- Trailing transition into default bg
  if prev_bg then
    table.insert(out, "%#" .. hl(prev_bg, nil, nil) .. "#" .. (side == "left" and sep_l or sep_r))
  end
  table.insert(out, "%*")
  return table.concat(out)
end

-- ─── public helpers: pre-composed left/right halves ─────────────────────────
-- Anchor with the per-mode capsule so the whole left half flows from the
-- mode color outward. Macro/search/diag/lsp/spinner appear conditionally —
-- the chain skips empty segments so the visual rhythm stays tight.
--
-- Adaptive layout: `pri(min_cols, module_fn)` returns an empty segment
-- (skipping the actual module call) when the terminal is narrower than
-- `min_cols`. So peripheral chips vanish on small windows but urgent ones
-- (mode, conflicts, save_pulse, diag, dap_state) always render.
local function pri(min_cols, fn)
  if vim.o.columns < min_cols then return { text = "" } end
  return fn()
end

-- Attach a click handler to a segment + signify clickability in-place.
-- Norman 2013 *Design of Everyday Things* revised edition: an affordance
-- is wasted if it is not signified. Half of the chips in the chain are
-- clickable (git → LazyGit, diag → Trouble, tab_undo → picker, etc.) but
-- without a visible cue the user has to try each one to discover which.
-- A thin underline is the canonical "in-place interactivity" signifier
-- from the web's earliest UI conventions — survives monochrome rendering,
-- works under color blindness, doesn't clobber the chip's color identity
-- or weight (we merge into existing gui rather than replace).
--
-- Hassenzahl 2010 *Experience Design* + 2020s NN/g discoverability work:
-- the signifier must live IN the affordance, not in a separate help panel
-- or tooltip. Terminals can't show hover states or cursor changes, but
-- underline is universal and preserves the rest of the chip's design.
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

-- ─── click handlers (closures over the relevant API) ──────────────────────
-- Defined once, reused across renders. pcall'd so a missing plugin doesn't
-- explode the statusline (it does silently swallow the click — the chip is
-- still visible, just inert).
local function cmd(c)            return function() pcall(vim.cmd, c) end end
local function lua(fn)           return function() pcall(fn) end end
local function first_of(...)
  -- Run the first command that exists. Lets us try :LazyGit then :Neogit
  -- without depending on either being present.
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
local function show_battery_detail()
  local out = vim.fn.system("pmset -g batt 2>/dev/null")
  vim.notify(out, vim.log.levels.INFO, { title = "battery" })
end

-- Three width tiers: 0 (critical, always), 80 (normal), 120 (wide/ambient).
-- The old `pri()` function still handles the conditional dispatch — we just
-- collapse the eight prior thresholds into these three.
function M.left()
  return M.chain({
    -- critical: always present, anchor the line
    M.modules.mode(),
    M.modules.macro(),
    M.modules.search(),
    clk(M.modules.conflicts(),              jump_first_conflict),
    -- file context
    clk(pri( 80, M.modules.dir),            lua(function() require("user.spotlight").open() end)),
    clk(    M.modules.file(),               lua(function() vim.cmd("e %") end)),
    -- git
    clk(    M.modules.git(),                first_of("LazyGit", "Neogit")),
    clk(pri( 80, M.modules.gitdiff),        cmd("Gitsigns preview_hunk")),
    -- problems / language servers
    clk(    M.modules.diag(),               first_of("Trouble diagnostics toggle", "TroubleToggle", "Telescope diagnostics")),
    clk(pri( 80, M.modules.lsp),            cmd("Mason")),
    -- live indicators
    clk(pri( 80, M.modules.spinner),        lua(function() require("user.jobs").list() end)),
    clk(    M.modules.tasks(),              lua(function() require("user.dock").open("tasks") end)),
            M.modules.save_pulse(),
    clk(    M.modules.dap_state(),          first_of("DapContinue")),
    -- secondary (normal tier)
    clk(pri( 80, M.modules.jira),           lua(function() require("user.jira").show_issue() end)),
    clk(pri( 80, M.modules.todos),          first_of("TodoTrouble", "TodoTelescope")),
    clk(pri( 80, M.modules.tab_undo),       lua(function() require("user.tabs").pick() end)),
    clk(pri( 80, M.modules.playbook_led),   lua(function() require("user.playbooks").show() end)),
    clk(pri( 80, M.modules.update),         cmd("Git fetch")),
    -- ambient (wide tier)
    pri(120, M.modules.os),
    pri(120, M.modules.user_short),
            M.modules.ssh(),
    pri(120, M.modules.project_type),
    pri(120, M.modules.package_version),
    pri(120, M.modules.direnv),
  }, { side = "left" })
end

function M.right()
  return M.chain({
    -- ambient signals — wide tier only
    pri(120, M.modules.heartbeat),
    clk(pri(120, M.modules.engage),         lua(function() require("user.state").show() end)),
    clk(pri(120, M.modules.streak),         lua(function() require("user.today").show() end)),
    pri(120, M.modules.cmd_duration),
    -- assistants / timers
    clk(pri( 80, M.modules.ai),             cmd("AI")),
    clk(pri(120, M.modules.pomo),           first_of("TimerStop", "TimerSession")),
    -- runtimes — icon-only at ≥120
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
    -- ops context — risky-colored when prod/admin/etc.
    pri(120, M.modules.terraform),
    pri(120, M.modules.docker),
    pri(120, M.modules.k8s),
    pri(120, M.modules.cloud),
    pri(120, M.modules.aws),
    -- machine / clock
    clk(pri(120, M.modules.cpu),            cmd("PerfHud")),
    clk(pri(120, M.modules.ram),            cmd("PerfHud")),
    clk(pri(120, M.modules.battery),        show_battery_detail),
    clk(pri(120, M.modules.time),           cmd("Today")),
  }, { side = "right" })
end

function M.setup()
  M._hook_cmd_timing()
  M._hook_mode_accent()
  M._hook_save_pulse()
  M._hook_engagement()
  M._hook_diag_chips()
  -- per-buf chip caches: free entries when their buffer goes away so we
  -- don't accumulate state across long sessions.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = vim.api.nvim_create_augroup("user_starship_chip_cache", { clear = true }),
    callback = _flush_buf_cache,
  })
end

return M
