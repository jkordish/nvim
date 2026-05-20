-- Starship-style dynamic statusline segments. Each segment is conditional:
-- it returns "" unless its context applies (e.g. python_venv only when a venv
-- is active, k8s only when a kubeconfig exists in the project, etc.).
-- All shell-outs are cached so we don't fork on every redraw.
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

-- DIR (cwd basename)
function M.modules.dir()
  local cwd = vim.fn.getcwd()
  local name = vim.fn.fnamemodify(cwd, ":t")
  return { text = ("  %s "):format(name), fg = M.c.base, bg = M.c.sky, gui = "bold" }
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
  return { text = " " .. s .. " ", fg = M.c.base, bg = M.c.mauve, gui = "bold" }
end

-- GIT DIFF STATS (+ ~ -)
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
    return string.format("+%d ~%d -%d", a, m, d)
  end)
  if s == "" then return { text = "" } end
  return { text = " " .. s .. " ", fg = M.c.base, bg = M.c.peach }
end

-- PYTHON VENV (only in python contexts)
function M.modules.python()
  local ft = vim.bo.filetype
  if ft ~= "python" and not find_up("pyproject.toml") and not find_up("requirements.txt") then
    return { text = "" }
  end
  local venv = vim.env.VIRTUAL_ENV
  local name = venv and vim.fn.fnamemodify(venv, ":t") or nil
  -- Try to detect .venv even if not activated
  if not name then
    if find_up(".venv/bin/python") then name = ".venv" end
  end
  if not name then name = "py" end
  local ver = memo("pyver", 60000, function()
    local v = trim(vim.fn.system("python3 --version 2>/dev/null")):match("Python ([%d.]+)") or ""
    return v
  end)
  return { text = (" %s %s "):format(name, ver), fg = M.c.base, bg = M.c.yellow, gui = "bold" }
end

-- NODE (only in JS/TS contexts)
function M.modules.node()
  local ft = vim.bo.filetype
  local is_js = ft == "javascript" or ft == "typescript" or ft == "javascriptreact" or ft == "typescriptreact" or ft == "vue" or ft == "svelte"
  if not is_js and not find_up("package.json") then return { text = "" } end
  local ver = memo("nodever", 60000, function()
    return trim(vim.fn.system("node -v 2>/dev/null"))
  end)
  if ver == "" then return { text = "" } end
  return { text = ("  %s "):format(ver), fg = M.c.base, bg = M.c.green, gui = "bold" }
end

-- GO
function M.modules.go()
  if vim.bo.filetype ~= "go" and not find_up("go.mod") then return { text = "" } end
  local ver = memo("gover", 60000, function()
    return trim(vim.fn.system("go version 2>/dev/null")):match("go(%S+)") or ""
  end)
  if ver == "" then return { text = "" } end
  return { text = (" 󰟓 %s "):format(ver), fg = M.c.base, bg = M.c.sapphire, gui = "bold" }
end

-- RUST
function M.modules.rust()
  if vim.bo.filetype ~= "rust" and not find_up("Cargo.toml") then return { text = "" } end
  local ver = memo("rustver", 60000, function()
    return trim(vim.fn.system("rustc --version 2>/dev/null")):match("rustc (%S+)") or ""
  end)
  if ver == "" then return { text = "" } end
  return { text = ("  %s "):format(ver), fg = M.c.base, bg = M.c.peach, gui = "bold" }
end

-- DOCKER (when Dockerfile in repo)
function M.modules.docker()
  if not find_up("Dockerfile") and not find_up("docker-compose.yml") and not find_up("compose.yaml") then
    return { text = "" }
  end
  return { text = "  docker ", fg = M.c.base, bg = M.c.blue, gui = "bold" }
end

-- KUBERNETES (when k8s yaml in project, shows current kubectl context)
function M.modules.k8s()
  local cwd = vim.fn.getcwd()
  local is_k8s = memo("k8s_proj:" .. cwd, 60000, function()
    if not find_up("Chart.yaml") and not find_up("kustomization.yaml") then
      -- Cheap check: any yaml file at repo root with kind:
      local out = vim.fn.systemlist("grep -l --max-count=1 'kind:' " .. cwd .. "/*.yaml " .. cwd .. "/*.yml 2>/dev/null")
      if #out == 0 then return "" end
    end
    return trim(vim.fn.system("kubectl config current-context 2>/dev/null"))
  end)
  if is_k8s == "" then return { text = "" } end
  return { text = ("  %s "):format(is_k8s), fg = M.c.base, bg = M.c.teal, gui = "bold" }
end

-- TERRAFORM
function M.modules.terraform()
  if vim.bo.filetype ~= "terraform" and not find_up("main.tf") then return { text = "" } end
  local ws = memo("tfws", 30000, function()
    return trim(vim.fn.system("terraform workspace show 2>/dev/null"))
  end)
  return { text = ("  %s "):format(ws ~= "" and ws or "tf"), fg = M.c.base, bg = M.c.pink, gui = "bold" }
end

-- AWS profile
function M.modules.aws()
  local p = vim.env.AWS_PROFILE
  if not p or p == "" then return { text = "" } end
  return { text = ("  %s "):format(p), fg = M.c.base, bg = M.c.peach }
end

-- BATTERY (macOS) — only shows when below 100% or charging
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
  local icon
  if mode == "ac" then icon = " "
  elseif pct >= 80 then icon = " "
  elseif pct >= 60 then icon = " "
  elseif pct >= 40 then icon = " "
  elseif pct >= 20 then icon = " "
  else icon = " " end
  local bg = (pct < 20 and mode == "bat") and M.c.red or M.c.surface
  return { text = (" %s %d%% "):format(icon, pct), fg = M.c.text, bg = bg }
end

-- TIME
function M.modules.time()
  return { text = ("  %s "):format(os.date("%H:%M")), fg = M.c.base, bg = M.c.lavender, gui = "bold" }
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
  return { text = (icons[kind] or "  ") .. kind .. " ", fg = M.c.base, bg = M.c.flamingo, gui = "bold" }
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
  return { text = (" 󰏗 v%s "):format(v), fg = M.c.base, bg = M.c.pink }
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

-- CPU LOAD — sparkline of recent load averages
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
function M.modules.cpu()
  local s = memo("cpu", 4000, function()
    -- macOS + linux both have `uptime` with load averages
    local out = trim(vim.fn.system("uptime 2>/dev/null"))
    local one = tonumber(out:match("load averages?:%s*([%d%.]+)") or out:match("load average:%s*([%d%.]+)"))
    if not one then return "" end
    local cores = tonumber(vim.fn.system("getconf _NPROCESSORS_ONLN 2>/dev/null") or "1") or 1
    local norm = math.min(1, one / cores)
    local idx = math.max(1, math.ceil(norm * #SPARK))
    return SPARK[idx] .. SPARK[idx] .. SPARK[idx] .. (" %.2f"):format(one)
  end)
  if s == "" then return { text = "" } end
  return { text = (" cpu %s "):format(s), fg = M.c.text, bg = M.c.surface }
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
  local fg = M.c.text
  if pct > 90 then fg = M.c.red elseif pct > 75 then fg = M.c.peach end
  return { text = (" ram %d%% "):format(pct), fg = fg, bg = M.c.surface }
end

-- CLOUD ACCOUNT — gcloud / aws (whichever is set)
function M.modules.cloud()
  -- gcloud first (more common to be set per-shell)
  if vim.env.CLOUDSDK_ACTIVE_CONFIG_NAME or vim.fn.executable("gcloud") == 1 then
    local acct = memo("gcloud", 60000, function()
      return trim(vim.fn.system("gcloud config get-value account 2>/dev/null"))
    end)
    if acct ~= "" and not acct:find("ERROR") then
      local short = acct:match("([^@]+)") or acct
      return { text = (" 󱇶 %s "):format(short), fg = M.c.base, bg = M.c.sapphire }
    end
  end
  -- aws fallback
  if vim.env.AWS_PROFILE then
    return { text = (" 󰸏 %s "):format(vim.env.AWS_PROFILE), fg = M.c.base, bg = M.c.peach }
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
    -- Trim common suffixes so "lua_ls" → "lua", "rust_analyzer" → "rust_analyzer"
    local n = (c.name or "?"):gsub("_ls$", "")
    table.insert(names, n)
  end
  return { text = (" 󰒋 %s "):format(table.concat(names, "·")),
           fg = M.c.base, bg = M.c.teal, gui = "bold" }
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
  local icon = lit and "●" or "○"
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
  -- Two-phase visual: full bright green for first 60% of window, then dim
  -- for the last 40% as a subtle fade-out — eye reads the transition.
  local total = PULSE_MS
  local phase_bright = remaining > (total * 0.4)
  local bg = p.ok and (phase_bright and M.c.green or M.c.teal) or M.c.red
  local icon = p.ok and "✓" or "✗"
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

function M.modules.engage()
  if not M._engage.session_start_ms then return { text = "" } end
  local mins = math.floor((vim.uv.now() - M._engage.session_start_ms) / 60000)
  return { text = (" ⌨ %s · %dm "):format(_fmt_count(M._engage.keys_today), mins),
           fg = M.c.text, bg = M.c.surface }
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
  return { text = (" 🔥 %dd "):format(s),
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
local hl_cache = {}
local function hl(fg, bg, gui)
  local key = (fg or "") .. ":" .. (bg or "") .. ":" .. (gui or "")
  if hl_cache[key] then return hl_cache[key] end
  local name = "Starship_" .. tostring(vim.tbl_count(hl_cache))
  vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg, bold = gui == "bold", italic = gui == "italic" })
  hl_cache[key] = name
  return name
end

local function sep_hl(prev_bg, next_bg)
  -- A separator's foreground = the previous segment's background, blended
  -- on top of the next segment's background. So fg=prev_bg, bg=next_bg.
  return hl(prev_bg, next_bg, nil)
end

-- chain {...segments} -> "%#hlA# text %#sepAB# %#hlB# text %*"
function M.chain(segments, opts)
  opts = opts or {}
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
function M.left()
  return M.chain({
    M.modules.mode(),          -- per-mode capsule (replaces lualine_a "mode")
    M.modules.macro(),         -- pulsing "REC @q" while recording
    M.modules.search(),        -- "[n/total]" during /-search
    M.modules.os(),
    M.modules.user_short(),
    M.modules.ssh(),           -- only if remote
    M.modules.dir(),
    M.modules.project_type(),  -- only if recognizable
    M.modules.package_version(),
    M.modules.git(),
    M.modules.gitdiff(),
    M.modules.diag(),          -- buffer diagnostics (severity-colored bg)
    M.modules.lsp(),           -- connected LSP clients
    M.modules.spinner(),       -- animated when user.jobs has running tasks
    M.modules.save_pulse(),    -- "✓ saved · file" chip for 1.6s after BufWritePost
    M.modules.jira(),          -- branch's Jira ticket + status (cache-only)
    M.modules.playbook_led(),  -- last fired playbook (fades after 10 min)
    M.modules.update(),        -- "↓N" if behind upstream
    M.modules.direnv(),        -- only if .envrc loaded
  }, { side = "left" })
end

function M.right()
  return M.chain({
    M.modules.heartbeat(),     -- once-a-minute 200ms ♥/♡ pulse
    M.modules.engage(),        -- "⌨ 2.4k · 47m" — keys today + session minutes
    M.modules.streak(),        -- "🔥 14d" — consecutive days (hidden ≤ 1)
    M.modules.cmd_duration(),  -- "took 2.4s" after slow cmds
    M.modules.ai(),
    M.modules.pomo(),
    -- per-language version (only one renders at a time)
    M.modules.python(),
    M.modules.node(),
    M.modules.go(),
    M.modules.rust(),
    M.modules.terraform(),
    M.modules.docker(),
    M.modules.k8s(),
    M.modules.cloud(),
    M.modules.cpu(),
    M.modules.ram(),
    M.modules.battery(),
    M.modules.time(),
  }, { side = "right" })
end

function M.setup()
  M._hook_cmd_timing()
  M._hook_mode_accent()
  M._hook_save_pulse()
  M._hook_engagement()
  M._hook_diag_chips()
end

return M
