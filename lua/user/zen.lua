-- Zen: animated breathing exercise. A floating circle that expands over 4s,
-- holds for 4s, contracts over 4s. Repeat. Press q to exit and exhale.
local M = {}

local state = { win = nil, buf = nil, timer = nil, t0 = 0, cycles = 0 }
local W, H = 30, 15

local CYCLE_MS = 12000   -- 4s inhale + 4s hold + 4s exhale
local function phase_at(t_ms)
  local p = (t_ms % CYCLE_MS) / CYCLE_MS  -- 0..1
  if p < 1/3 then return "inhale", p * 3
  elseif p < 2/3 then return "hold", 1
  else return "exhale", 1 - (p - 2/3) * 3 end
end

local function draw_circle(width, height, radius)
  local lines = {}
  for y = 0, height - 1 do
    local row = ""
    for x = 0, width - 1 do
      local dx, dy = (x - width / 2), (y - height / 2) * 2   -- compensate for cell aspect
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= radius then
        if d > radius - 1 then row = row .. "●"
        else row = row .. "·" end
      else
        row = row .. " "
      end
    end
    table.insert(lines, row)
  end
  return lines
end

local function paint()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local elapsed = vim.uv.now() - state.t0
  local label, amp = phase_at(elapsed)
  local max_r = math.min(W / 2, H) - 1
  local radius = 2 + amp * (max_r - 2)
  local lines = draw_circle(W, H, radius)

  -- Centered phase label on the last line
  local prompt = ({ inhale = "breathe  in", hold = "hold", exhale = "breathe out" })[label]
  local pad = math.max(0, math.floor((W - #prompt) / 2))
  table.insert(lines, "")
  table.insert(lines, string.rep(" ", pad) .. prompt)
  table.insert(lines, "")
  local sub = string.format("    cycle %d   ·   q to exit", state.cycles)
  table.insert(lines, sub)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  if math.floor(elapsed / CYCLE_MS) > state.cycles - 1 then state.cycles = math.floor(elapsed / CYCLE_MS) + 1 end
end

function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then return end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = " ⊙ zen ", title_pos = "center",
    width = W, height = H + 4,
    row = math.floor((vim.o.lines - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
  vim.wo[state.win].cursorline = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  state.t0 = vim.uv.now()
  state.cycles = 0
  state.timer = vim.uv.new_timer()
  state.timer:start(0, 80, vim.schedule_wrap(paint))

  vim.keymap.set("n", "q", function() M.close() end, { buffer = state.buf })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = state.buf })
end

function M.close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.setup() vim.api.nvim_create_user_command("Zen", M.open, { desc = "Animated breathing exercise" }) end
return M
