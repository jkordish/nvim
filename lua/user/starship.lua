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

-- USER PROMPT (root indicator)
function M.modules.user_short()
  local user = vim.env.USER or "user"
  local is_root = vim.uv.os_getenv("USER") == "root" or (vim.uv.os_getuid and vim.uv.os_getuid() == 0)
  local bg = is_root and M.c.red or M.c.lavender
  local prefix = is_root and "# " or " "
  return { text = (prefix .. "%s "):format(user), fg = M.c.base, bg = bg, gui = "bold" }
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
      if side == "left" then
        if prev_bg then
          table.insert(out, "%#" .. sep_hl(prev_bg, seg.bg) .. "#" .. sep_l)
        end
        table.insert(out, "%#" .. seg_hl .. "#" .. seg.text)
      else
        if prev_bg then
          table.insert(out, "%#" .. sep_hl(seg.bg, prev_bg) .. "#" .. sep_r)
        end
        table.insert(out, "%#" .. seg_hl .. "#" .. seg.text)
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
function M.left()
  return M.chain({
    M.modules.os(),
    M.modules.user_short(),
    M.modules.ssh(),           -- only if remote
    M.modules.dir(),
    M.modules.project_type(),  -- only if recognizable
    M.modules.package_version(),
    M.modules.git(),
    M.modules.gitdiff(),
    M.modules.update(),        -- "↓N" if behind upstream
    M.modules.direnv(),        -- only if .envrc loaded
  }, { side = "left" })
end

function M.right()
  return M.chain({
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
end

return M
