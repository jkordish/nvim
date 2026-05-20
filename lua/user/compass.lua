-- Compass: always-on floating HUD, bottom-right corner.
-- Renders 5 rows of colored "chips" using the same Catppuccin palette + mode
-- vocabulary as user.starship — so the compass tunes with mode just like the
-- statusline. Chips are colored via extmarks (statusline %#hl# syntax doesn't
-- apply to buffer content).
local M = {}

local state = { win = nil, buf = nil, timer = nil, ns = nil, width = 0, height = 0 }
local GIT = { branch = "—", dirty = "·", t = 0 }

-- ─── color palette (mirrors user.starship.c) ─────────────────────────────
local C = {
  base = "#1e1e2e", surface = "#313244", overlay = "#6c7086", text = "#cdd6f4",
  red = "#f38ba8", peach = "#fab387", yellow = "#f9e2af", green = "#a6e3a1",
  teal = "#94e2d5", sky = "#89dceb", sapphire = "#74c7ec", blue = "#89b4fa",
  lavender = "#b4befe", mauve = "#cba6f7", pink = "#f5c2e7", flamingo = "#f2cdcd",
}

-- ─── highlight cache ─────────────────────────────────────────────────────
local hl_cache = {}
local function hl(fg, bg, bold)
  local key = (fg or "-") .. ":" .. (bg or "-") .. ":" .. tostring(bold or false)
  if hl_cache[key] then return hl_cache[key] end
  local name = "Compass_" .. tostring(vim.tbl_count(hl_cache))
  vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg, bold = bold or false })
  hl_cache[key] = name
  return name
end

-- ─── git cache (3s TTL) ──────────────────────────────────────────────────
local function git_cached()
  local now = vim.uv.now()
  if now - GIT.t < 3000 then return GIT.branch, GIT.dirty end
  local cwd = vim.fn.shellescape(vim.fn.getcwd())
  local b = vim.fn.systemlist("git -C " .. cwd .. " rev-parse --abbrev-ref HEAD 2>/dev/null")[1] or ""
  local s = vim.fn.systemlist("git -C " .. cwd .. " status --porcelain 2>/dev/null")
  GIT.branch = (b == "" and "—" or b)
  GIT.dirty = (#s > 0) and ("✗ " .. #s) or "✓"
  GIT.t = now
  return GIT.branch, GIT.dirty
end

-- ─── chip helper: returns {text, fg, bg, bold} for a single segment ──────
local function chip(text, fg, bg, bold)
  return { text = text, fg = fg, bg = bg, bold = bold ~= false }
end

-- ─── compose a row of chips into {text, spans} ───────────────────────────
-- spans = { { col_start, col_end, hl_name }, ... }
local function compose(chips)
  local text, spans = "", {}
  for _, c in ipairs(chips) do
    local start_b = #text
    text = text .. c.text
    table.insert(spans, { start_b, #text, hl(c.fg, c.bg, c.bold) })
  end
  -- Return a single table so `local rows = { row_a(), row_b() }` preserves
  -- both fields (multi-return collapses to first value in list constructors).
  return { text, spans }
end

-- ─── ROWS ─────────────────────────────────────────────────────────────────
local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

local function row_mode()
  -- Pull the same mode defs as starship so labels/colors stay in sync.
  local sok, st = pcall(require, "user.starship")
  local def
  if sok and st._mode_defs then
    local m = vim.api.nvim_get_mode().mode
    def = st._mode_defs[m] or st._mode_defs[m:sub(1, 1)] or st._mode_defs.n
  else
    def = { label = "NORMAL", icon = "●", bg = "blue" }
  end
  return compose({ chip((" %s %s "):format(def.icon, def.label), C.base, C[def.bg]) })
end

local function row_dir_branch()
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  if #cwd > 14 then cwd = cwd:sub(1, 14) end
  local branch, dirty = git_cached()
  if #branch > 12 then branch = branch:sub(1, 12) end
  return compose({
    chip(("  %s "):format(cwd), C.base, C.sky),
    chip((" "):format(""), nil, nil, false),
    chip(("  %s "):format(branch), C.base, C.mauve),
    chip(" ", nil, nil, false),
    chip((" %s "):format(dirty), C.base, dirty:sub(1, 1) == "✗" and C.peach or C.green),
  })
end

local function row_lsp_diag()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local names = {}
  for _, c in ipairs(clients) do
    local n = (c.name or "?"):gsub("_ls$", "")
    table.insert(names, n)
  end
  local lsp_text = #names > 0 and (" 󰒋 " .. table.concat(names, "·") .. " ") or " 󰒋 idle "
  if #lsp_text > 22 then lsp_text = lsp_text:sub(1, 19) .. "… " end
  local lsp_bg = #names > 0 and C.teal or C.surface
  local lsp_fg = #names > 0 and C.base or C.overlay

  local d = vim.diagnostic.count(0)
  local e, w, i, h = d[1] or 0, d[2] or 0, d[3] or 0, d[4] or 0
  local diag_chips = {}
  if e + w + i + h == 0 then
    table.insert(diag_chips, chip("  clean ", C.base, C.green))
  else
    if e > 0 then table.insert(diag_chips, chip(("   %d "):format(e), C.base, C.red)) end
    if w > 0 then table.insert(diag_chips, chip(("   %d "):format(w), C.base, C.yellow)) end
    if i > 0 then table.insert(diag_chips, chip(("   %d "):format(i), C.base, C.sky)) end
    if h > 0 then table.insert(diag_chips, chip((" 󰌵 %d "):format(h), C.base, C.teal)) end
  end

  local chips = { chip(lsp_text, lsp_fg, lsp_bg), chip(" ", nil, nil, false) }
  for _, c in ipairs(diag_chips) do
    table.insert(chips, c)
    table.insert(chips, chip(" ", nil, nil, false))
  end
  return compose(chips)
end

local function row_system()
  -- Compact sparkline for load average (cached for cost; HUD refresh is 250ms)
  local load = tonumber((vim.fn.systemlist("uptime 2>/dev/null")[1] or ""):match("load averages?:%s*([%d%.]+)") or "0") or 0
  local cores = tonumber(vim.fn.system("getconf _NPROCESSORS_ONLN 2>/dev/null")) or 1
  local norm = math.min(1, load / cores)
  local idx = math.max(1, math.ceil(norm * #SPARK))
  local cpu_text = (" cpu %s%s %.2f "):format(SPARK[idx], SPARK[idx], load)
  local cpu_bg = norm > 0.85 and C.red or norm > 0.6 and C.peach or C.surface
  local cpu_fg = norm > 0.6 and C.base or C.text

  -- RAM
  local ram_pct = 0
  if vim.fn.has("mac") == 1 then
    local pages = vim.fn.system("vm_stat 2>/dev/null")
    local free = tonumber(pages:match("Pages free:%s*(%d+)") or "0")
    local active = tonumber(pages:match("Pages active:%s*(%d+)") or "0")
    local wired = tonumber(pages:match("Pages wired down:%s*(%d+)") or "0")
    local comp = tonumber(pages:match("Pages occupied by compressor:%s*(%d+)") or "0")
    local total = free + active + wired + comp
    if total > 0 then ram_pct = math.floor(((active + wired + comp) / total) * 100) end
  end
  local ram_bg = ram_pct > 90 and C.red or ram_pct > 75 and C.peach or C.surface
  local ram_fg = ram_pct > 75 and C.base or C.text

  return compose({
    chip(cpu_text, cpu_fg, cpu_bg),
    chip(" ", nil, nil, false),
    chip((" ram %d%% "):format(ram_pct), ram_fg, ram_bg),
  })
end

local function row_clock()
  local time = os.date("%H:%M")
  local date = os.date("%a %b %d")
  -- Pomo / jobs hint chip on the right if active
  local extras = {}
  local pok, pomo = pcall(require, "pomo")
  if pok then
    local t = pomo.get_first_to_finish()
    if t then table.insert(extras, chip(("  %s "):format(t:remaining_time_str()), C.base, C.peach)) end
  end
  local jok, jobs = pcall(require, "user.jobs")
  if jok and jobs.tasks then
    local STATUS = jobs.STATUS or {}
    local running = 0
    for _, t in pairs(jobs.tasks()) do
      if t.status == (STATUS.RUNNING or "running") then running = running + 1 end
    end
    if running > 0 then
      local SP = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
      local frame = SP[(math.floor(vim.uv.now() / 80) % #SP) + 1]
      table.insert(extras, chip((" %s %d "):format(frame, running), C.base, C.sapphire))
    end
  end
  local chips = {
    chip(("  %s "):format(date), C.text, C.surface),
    chip(("  %s "):format(time), C.base, C.lavender),
  }
  if #extras > 0 then table.insert(chips, chip(" ", nil, nil, false)) end
  for _, e in ipairs(extras) do table.insert(chips, e) end
  return compose(chips)
end

-- ─── render ──────────────────────────────────────────────────────────────
local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local rows = { row_mode(), row_dir_branch(), row_lsp_diag(), row_system(), row_clock() }
  local lines, all_spans = {}, {}
  local max_w = 0
  for i, r in ipairs(rows) do
    local text, spans = r[1], r[2]
    lines[i] = text
    max_w = math.max(max_w, vim.fn.strdisplaywidth(text))
    for _, sp in ipairs(spans) do
      table.insert(all_spans, { line = i - 1, col_start = sp[1], col_end = sp[2], hl = sp[3] })
    end
  end
  -- Pad to consistent width so chip backgrounds don't fray on short rows
  for i, ln in ipairs(lines) do
    local pad = max_w - vim.fn.strdisplaywidth(ln)
    if pad > 0 then lines[i] = ln .. string.rep(" ", pad) end
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
  for _, s in ipairs(all_spans) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, state.ns, s.line, s.col_start, {
      end_col = s.col_end, hl_group = s.hl,
    })
  end

  -- Resize window if width changed (e.g. branch name shrunk/grew)
  if state.win and vim.api.nvim_win_is_valid(state.win) and max_w ~= state.width then
    state.width = max_w
    vim.api.nvim_win_set_config(state.win, {
      relative = "editor", width = max_w, height = #lines,
      row = vim.o.lines - #lines - 3, col = vim.o.columns - max_w - 2,
    })
  end
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.ns = state.ns or vim.api.nvim_create_namespace("user_compass")
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"

  -- Open with placeholder size; render() will resize on first tick.
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", focusable = false, noautocmd = true,
    width = 30, height = 5,
    row = vim.o.lines - 8, col = vim.o.columns - 32,
    border = "rounded", zindex = 40,
    title = " COMPASS ", title_pos = "center",
  })
  -- Brand-accented border + transparent background for chip color clarity
  vim.wo[state.win].winhighlight = "Normal:NormalFloat,FloatBorder:Comment,FloatTitle:Special"
  vim.wo[state.win].wrap = false

  render()
  state.timer = vim.uv.new_timer()
  state.timer:start(250, 250, vim.schedule_wrap(render))
end

function M.close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf, state.width = nil, nil, 0
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open() end
end

function M.is_open() return state.win ~= nil end

function M.setup()
  vim.api.nvim_create_user_command("Compass", M.toggle, { desc = "Toggle floating compass HUD" })
end

return M
