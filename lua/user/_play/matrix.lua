-- Matrix: katakana rain that persistently falls in a slim side column.
-- Each column is independent. Heads are white, trails fade to green→dark.
local M = {}

local state = { win = nil, buf = nil, timer = nil, cols = nil }
local NS = vim.api.nvim_create_namespace("user_matrix")

local W = 14   -- columns of rain
local KATAKANA = {}
for c = 0x30A0, 0x30FF do table.insert(KATAKANA, vim.fn.nr2char(c)) end
for _, s in ipairs({ "0","1","2","3","4","5","6","7","8","9","Z","X","#","$","@","&","Λ","Σ","Ω" }) do
  table.insert(KATAKANA, s)
end

-- Palette: head (bright white) + 8 fading green trails
local PALETTE = { "#ffffff", "#a6e3a1", "#7fdb83", "#5fc966", "#46af4d", "#338a3a", "#23652a", "#16451c", "#0d2810" }

local hl_cache = {}
local function color_hl(idx)
  if hl_cache[idx] then return hl_cache[idx] end
  local name = "MatrixGrad_" .. idx
  vim.api.nvim_set_hl(0, name, { fg = PALETTE[idx], bold = (idx == 1) })
  hl_cache[idx] = name
  return name
end

local function rand_char() return KATAKANA[math.random(#KATAKANA)] end

local function H() return vim.o.lines - 4 end

local function init_columns()
  state.cols = {}
  for x = 0, W - 1 do
    state.cols[x] = {
      y = math.random(-H(), 0),
      speed = math.random(1, 3) / 2,
      length = math.random(6, 14),
      chars = {},
    }
    -- Pre-seed chars for the trail
    for i = 1, H() do state.cols[x].chars[i] = rand_char() end
  end
end

local function paint()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local h = H()
  local lines = {}
  for _ = 1, h do table.insert(lines, string.rep(" ", W)) end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for x = 0, W - 1 do
    local col = state.cols[x]
    col.y = col.y + col.speed
    if col.y - col.length > h then
      col.y = math.random(-10, 0)
      col.speed = math.random(1, 3) / 2
      col.length = math.random(6, 14)
    end
    -- Occasionally jitter a char somewhere in the trail
    local jitter_idx = math.random(h)
    col.chars[jitter_idx] = rand_char()

    for trail = 0, col.length do
      local row = math.floor(col.y) - trail
      if row >= 0 and row < h then
        local color_idx = math.min(#PALETTE, trail + 1)
        local ch = col.chars[row + 1] or rand_char()
        pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 0, {
          virt_text = { { ch, color_hl(color_idx) } },
          virt_text_pos = "overlay",
          virt_text_win_col = x,
        })
      end
    end
  end
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", focusable = false, noautocmd = true,
    width = W, height = H(),
    row = 0, col = vim.o.columns - W,
  })
  vim.wo[state.win].winhighlight = "Normal:Normal,NormalFloat:Normal"
  init_columns()
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 90, vim.schedule_wrap(paint))
end

function M.close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open() end
end

function M.setup() vim.api.nvim_create_user_command("Matrix", M.toggle, { desc = "Toggle matrix rain side column" }) end
return M
