-- Glyph: turns the word under the cursor into a deterministic ASCII sigil,
-- rendered as virt_lines below the line. Same word always yields the same
-- sigil — a sort of secret signature for every identifier.
local M = {}

local NS = vim.api.nvim_create_namespace("user_glyph")
local active = {}  -- bufnr -> autocmd id

local NODES = { "✶", "◉", "✦", "✧", "✸", "✺", "◯", "▲", "⬢", "◆" }
local CONNECTORS = { "─", "═", "┄", "┈" }

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

-- Render a 5-row × 17-col sigil for the given word.
local function render_sigil(word)
  local h = hash(word)
  local function rng()
    h = (h * 1103515245 + 12345) % 2147483647
    return h
  end

  local W, H = 17, 5
  local grid = {}
  for r = 1, H do grid[r] = {}; for c = 1, W do grid[r][c] = " " end end

  -- Place 3-5 nodes
  local n_nodes = 3 + (rng() % 3)
  local nodes = {}
  for _ = 1, n_nodes do
    local r = 1 + (rng() % H)
    local c = 2 + (rng() % (W - 4))
    table.insert(nodes, { r = r, c = c, glyph = NODES[1 + (rng() % #NODES)] })
  end

  -- Draw connections between consecutive nodes (Bresenham-lite)
  for i = 1, #nodes - 1 do
    local a, b = nodes[i], nodes[i + 1]
    local steps = math.max(math.abs(b.r - a.r), math.abs(b.c - a.c))
    if steps == 0 then steps = 1 end
    local conn = CONNECTORS[1 + (rng() % #CONNECTORS)]
    for s = 1, steps - 1 do
      local r = math.floor(a.r + (b.r - a.r) * s / steps + 0.5)
      local c = math.floor(a.c + (b.c - a.c) * s / steps + 0.5)
      if r >= 1 and r <= H and c >= 1 and c <= W and grid[r][c] == " " then
        -- pick connector character based on direction
        local dr, dc = b.r - a.r, b.c - a.c
        if math.abs(dc) > math.abs(dr) * 2 then grid[r][c] = conn
        elseif math.abs(dr) > math.abs(dc) * 2 then grid[r][c] = "│"
        else grid[r][c] = (dr * dc > 0) and "╲" or "╱" end
      end
    end
  end

  -- Place nodes last (on top of any connector line that crossed them)
  for _, n in ipairs(nodes) do
    if n.r >= 1 and n.r <= H and n.c >= 1 and n.c <= W then grid[n.r][n.c] = n.glyph end
  end

  -- Convert grid → lines, prefix with `   ⟁ ` framing
  local lines = {}
  for r = 1, H do
    table.insert(lines, "    " .. table.concat(grid[r]))
  end
  return lines
end

local function color_for_word(word)
  -- Spread the hash across a soft palette
  local palette = { "#cba6f7", "#f5c2e7", "#f38ba8", "#fab387", "#f9e2af", "#a6e3a1", "#94e2d5", "#89dceb", "#89b4fa", "#b4befe" }
  return palette[(hash(word) % #palette) + 1]
end

local function draw_for_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  local word = vim.fn.expand("<cword>")
  if not word or #word < 2 then return end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local color = color_for_word(word)

  local hl_name = "Glyph_" .. color:sub(2)
  vim.api.nvim_set_hl(0, hl_name, { fg = color, bold = true })

  local virt = {}
  for _, l in ipairs(render_sigil(word)) do
    table.insert(virt, { { l, hl_name } })
  end
  -- Insert a header line that names the word
  table.insert(virt, 1, { { "    ⟁ sigil of «" .. word .. "»", "Comment" } })

  pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, line, 0, { virt_lines = virt, virt_lines_above = false })
end

function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then return end
  active[bufnr] = vim.api.nvim_create_autocmd("CursorHold", {
    buffer = bufnr,
    callback = function() draw_for_buffer(bufnr) end,
  })
  draw_for_buffer(bufnr)
  vim.notify("glyph: sigils on (move cursor, wait for CursorHold)")
end

function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  if active[bufnr] then vim.api.nvim_del_autocmd(active[bufnr]); active[bufnr] = nil end
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then M.disable(bufnr) else M.enable(bufnr) end
end

function M.draw_once() draw_for_buffer() end

function M.setup()
  vim.api.nvim_create_user_command("Glyph",     M.toggle,    { desc = "Toggle live sigil for cursor word" })
  vim.api.nvim_create_user_command("GlyphDraw", M.draw_once, { desc = "Draw sigil for word under cursor (one-shot)" })
end

return M
