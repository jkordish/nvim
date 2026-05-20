-- Radar: a small circular sweep showing nearby diagnostics + marks in the
-- current buffer. Position on the radar maps to distance from cursor (line
-- delta). Color = severity. Toggle with :Radar.
local M = {}

local state = { win = nil, buf = nil, timer = nil }
local W, H = 27, 13

-- Pick a glyph for severity / type
local function dot(severity)
  if severity == 1 then return { "●", "DiagnosticError" } end
  if severity == 2 then return { "●", "DiagnosticWarn"  } end
  if severity == 3 then return { "●", "DiagnosticInfo"  } end
  if severity == 4 then return { "●", "DiagnosticHint"  } end
  return { "○", "Comment" }
end

local function scan()
  -- Returns list of { line_delta, glyph, hl }
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local total = vim.api.nvim_buf_line_count(0)
  local items = {}
  for _, d in ipairs(vim.diagnostic.get(0)) do
    local delta = d.lnum + 1 - cur
    local g = dot(d.severity)
    table.insert(items, { delta = delta, glyph = g[1], hl = g[2], lnum = d.lnum + 1 })
  end
  -- Marks too
  for _, m in ipairs(vim.fn.getmarklist("%")) do
    if m.mark:match("'[a-zA-Z]") then
      table.insert(items, { delta = m.pos[2] - cur, glyph = "M", hl = "Identifier", lnum = m.pos[2] })
    end
  end
  return items, total
end

local function plot(items, total)
  -- Build empty grid
  local cx, cy = math.floor(W / 2), math.floor(H / 2)
  local grid = {}
  for y = 1, H do grid[y] = {}; for x = 1, W do grid[y][x] = " " end end

  -- Draw circle outline (ASCII approximation)
  local r = math.min(cx, cy) - 1
  for theta = 0, math.pi * 2, math.pi / 24 do
    local x = math.floor(cx + math.cos(theta) * r + 0.5)
    local y = math.floor(cy + math.sin(theta) * (r * 0.55) + 0.5)
    if x >= 1 and x <= W and y >= 1 and y <= H then grid[y][x] = "·" end
  end
  -- Crosshairs
  grid[cy][cx] = "+"
  for x = cx - r + 1, cx + r - 1 do if grid[cy][x] == " " then grid[cy][x] = "─" end end
  for y = cy - math.floor(r * 0.55) + 1, cy + math.floor(r * 0.55) - 1 do
    if grid[y][cx] == " " then grid[y][cx] = "│" end
  end

  -- Place items: angle = sign of delta (above/below), radius = |delta|/total * r
  local highlights = {}  -- {row, col_start, col_end, hl}
  local max_delta = math.max(50, total)
  for _, it in ipairs(items) do
    local norm = math.min(1, math.abs(it.delta) / max_delta)
    local angle = it.delta < 0 and (-math.pi / 2) or (math.pi / 2)  -- above (up) / below (down)
    -- spread by hash so multiple items don't overlap
    local jitter = ((it.lnum * 37) % 31 - 15) / 60
    angle = angle + jitter
    local x = math.floor(cx + math.cos(angle) * (r * norm * 0.9) + 0.5)
    local y = math.floor(cy + math.sin(angle) * (r * 0.55 * norm * 0.9) + 0.5)
    if x >= 1 and x <= W and y >= 1 and y <= H then
      grid[y][x] = it.glyph
      table.insert(highlights, { y - 1, x - 1, x, it.hl })
    end
  end

  local lines = {}
  for y = 1, H do table.insert(lines, table.concat(grid[y])) end
  return lines, highlights
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local items, total = scan()
  local lines, hls = plot(items, total)
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  local NS = vim.api.nvim_create_namespace("user_radar")
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_config, state.win, {
      title = (" RADAR  · %d items "):format(#items), title_pos = "center",
    })
  end
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", focusable = false, noautocmd = true,
    border = "rounded", title = " RADAR ", title_pos = "center",
    width = W, height = H, row = 1, col = vim.o.columns - W - 2,
  })
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 600, vim.schedule_wrap(render))
end

function M.close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open() end
end

function M.is_open() return state.win ~= nil end

function M.setup()
  vim.api.nvim_create_user_command("Radar", M.toggle, { desc = "Toggle diagnostic/mark radar" })
end

return M
