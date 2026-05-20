-- Constellation: your codebase as a star map. Each file is a star, size
-- maps to LOC, color to recency, position is a deterministic hash of the
-- directory path. Hovering over a star (cursor on it) shows the file name;
-- pressing <CR> opens it.
local M = {}

local NS = vim.api.nvim_create_namespace("user_constellation")
local state = { stars = {}, buf = nil, win = nil, W = 100, H = 32 }

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

local function gather_files()
  local cwd = vim.fn.getcwd()
  local files = vim.fn.systemlist({ "rg", "--files", "--hidden", "--glob=!.git/", "--glob=!node_modules/" })
  local stars = {}
  for _, rel in ipairs(files) do
    if #stars >= 200 then break end  -- cap density
    local full = cwd .. "/" .. rel
    local stat = vim.uv.fs_stat(full)
    if stat then
      local age_days = (os.time() - stat.mtime.sec) / 86400
      local dir = vim.fn.fnamemodify(rel, ":h")
      local angle = (hash(dir) % 10000) / 10000 * math.pi * 2
      local radius = 0.3 + ((hash(rel) % 7000) / 10000)  -- 0.3..1.0
      local x = math.floor(state.W / 2 + math.cos(angle) * (radius * state.W * 0.45)) + 1
      local y = math.floor(state.H / 2 + math.sin(angle) * (radius * state.H * 0.40)) + 1
      table.insert(stars, {
        rel = rel,
        loc = math.min(2000, math.floor(stat.size / 30)),  -- rough LOC estimate
        age = age_days,
        x = x, y = y,
      })
    end
  end
  return stars
end

local function star_glyph(loc)
  if loc < 30   then return "·" end
  if loc < 100  then return "•" end
  if loc < 300  then return "★" end
  if loc < 800  then return "✦" end
  return "✸"
end

local function star_color(age_days)
  if age_days < 1   then return "#f38ba8" end  -- red:    edited today
  if age_days < 7   then return "#fab387" end  -- orange: this week
  if age_days < 30  then return "#f9e2af" end  -- yellow: this month
  if age_days < 180 then return "#a6e3a1" end  -- green:  this half-year
  if age_days < 365 then return "#74c7ec" end  -- blue:   year
  return "#7287fd"                              -- ancient
end

local hl_cache = {}
local function color_hl(hex, bold)
  local key = hex .. (bold and "B" or "")
  if hl_cache[key] then return hl_cache[key] end
  local name = "Constell_" .. hex:sub(2) .. (bold and "B" or "")
  vim.api.nvim_set_hl(0, name, { fg = hex, bold = bold })
  hl_cache[key] = name
  return name
end

local function render()
  -- Empty canvas
  local lines = {}
  for _ = 1, state.H do table.insert(lines, string.rep(" ", state.W)) end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)

  -- Faint background dots for ambient starfield
  math.randomseed(42)
  for _ = 1, 60 do
    local x = math.random(state.W)
    local y = math.random(state.H)
    pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, y - 1, 0, {
      virt_text = { { ".", color_hl("#313244", false) } },
      virt_text_pos = "overlay",
      virt_text_win_col = x - 1,
    })
  end

  -- Plot stars
  for i, s in ipairs(state.stars) do
    if s.x >= 1 and s.x <= state.W and s.y >= 1 and s.y <= state.H then
      local glyph = star_glyph(s.loc)
      local big = s.loc > 300
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, s.y - 1, 0, {
        virt_text = { { glyph, color_hl(star_color(s.age), big) } },
        virt_text_pos = "overlay",
        virt_text_win_col = s.x - 1,
      })
      s.id = i  -- store for lookup
    end
  end
end

local function star_under_cursor()
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1], pos[2] + 1
  local best, best_d = nil, math.huge
  for _, s in ipairs(state.stars) do
    local d = math.abs(s.x - col) + math.abs(s.y - row)  -- manhattan
    if d < best_d then best, best_d = s, d end
  end
  if best and best_d <= 3 then return best end
end

local function on_cursor_moved()
  local s = star_under_cursor()
  if not s then return end
  local label = ("%s · %d bytes · %dd old"):format(s.rel, s.loc * 30, math.floor(s.age))
  vim.api.nvim_buf_clear_namespace(state.buf, NS, state.H, -1)
  pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, state.H - 1, 0, {
    virt_text = { { "  " .. label, "Comment" } },
    virt_text_pos = "overlay",
  })
end

function M.open()
  state.stars = gather_files()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = " ✦ constellation  ·  " .. #state.stars .. " stars ", title_pos = "center",
    width = state.W, height = state.H + 1,
    row = math.floor((vim.o.lines - state.H) / 2),
    col = math.floor((vim.o.columns - state.W) / 2),
  })
  vim.wo[state.win].cursorline = false
  render()

  vim.api.nvim_create_autocmd("CursorMoved", { buffer = state.buf, callback = on_cursor_moved })
  vim.keymap.set("n", "<CR>", function()
    local s = star_under_cursor()
    if s then vim.cmd("close | edit " .. vim.fn.fnameescape(vim.fn.getcwd() .. "/" .. s.rel)) end
  end, { buffer = state.buf })
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = state.buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = state.buf })
end

function M.setup() vim.api.nvim_create_user_command("Constellation", M.open, { desc = "Open codebase as star map" }) end
return M
