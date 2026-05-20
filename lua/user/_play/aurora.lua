-- Aurora: animated shifting-hue backdrop drawn with extmarks. Open with
-- :Aurora. A floating window in the bottom-right whose contents are a slow,
-- horizontal sine-wave of color shifting through the spectrum.
local M = {}

local state = { win = nil, buf = nil, timer = nil, phase = 0 }
local NS = vim.api.nvim_create_namespace("user_aurora")
local W, H = 50, 8
local CHARS = { " ", "░", "▒", "▓", "█" }

local function hsv_to_hex(h, s, v)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  local r, g, b = 0, 0, 0
  if     i % 6 == 0 then r, g, b = v, t, p
  elseif i % 6 == 1 then r, g, b = q, v, p
  elseif i % 6 == 2 then r, g, b = p, v, t
  elseif i % 6 == 3 then r, g, b = p, q, v
  elseif i % 6 == 4 then r, g, b = t, p, v
  else                   r, g, b = v, p, q end
  return string.format("#%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local hl_cache = {}
local function color_hl(hex)
  if hl_cache[hex] then return hl_cache[hex] end
  local name = "Aurora_" .. hex:sub(2)
  vim.api.nvim_set_hl(0, name, { fg = hex })
  hl_cache[hex] = name
  return name
end

local function paint()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  state.phase = state.phase + 0.04

  -- Build lines of blank space, then overlay colored block characters per cell.
  local lines = {}
  for _ = 1, H do table.insert(lines, string.rep(" ", W)) end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- For each cell, compute a sine wave value, map to a glyph density and color.
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local wave = math.sin((x / W) * math.pi * 2 + state.phase)
                 + math.sin((y / H) * math.pi * 3 + state.phase * 1.3)
      local density = (wave + 2) / 4   -- 0..1
      local ch = CHARS[math.max(1, math.min(#CHARS, math.floor(density * #CHARS) + 1))]
      local hue = ((x / W) * 0.4 + (y / H) * 0.2 + state.phase * 0.08) % 1
      local hex = hsv_to_hex(hue, 0.7, 0.6 + density * 0.4)
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, y, 0, {
        virt_text = { { ch, color_hl(hex) } },
        virt_text_pos = "overlay",
        virt_text_win_col = x,
      })
    end
  end
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", focusable = false, noautocmd = true,
    border = "rounded", title = " ✦ aurora ", title_pos = "center",
    width = W, height = H,
    row = vim.o.lines - H - 4, col = vim.o.columns - W - 4,
  })
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 80, vim.schedule_wrap(paint))
end

function M.close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else M.open() end
end

function M.setup() vim.api.nvim_create_user_command("Aurora", M.toggle, { desc = "Toggle aurora animation" }) end
return M
