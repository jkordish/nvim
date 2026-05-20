-- Throttle: a centered tiled action launcher. Press <leader>! or :Throttle,
-- get a 2x4 grid of actions. Each tile has a number (1-8). Press the number
-- to fire instantly. Customize via vim.g.throttle_actions.
local M = {}

local DEFAULT_ACTIONS = {
  { key = "1", label = "Run tests",      icon = "  ", run = function() vim.cmd("Neotest run") end },
  { key = "2", label = "Build (Make)",   icon = " ⚙  ", run = function() vim.cmd("Job build  make") end },
  { key = "3", label = "Lazygit",        icon = "  ", run = function() vim.cmd("LazyGit") end },
  { key = "4", label = "Neogit",         icon = "  ", run = function() vim.cmd("Neogit") end },
  { key = "5", label = "AI chat",        icon = " ✦  ", run = function() vim.cmd("CopilotChatToggle") end },
  { key = "6", label = "REPL",           icon = "  ", run = function() require("user.repl").toggle() end },
  { key = "7", label = "Today report",   icon = " 󰃭  ", run = function() require("user.today").show() end },
  { key = "8", label = "Spotlight",      icon = " ✦  ", run = function() require("user.spotlight").open() end },
}

local state = { win = nil, buf = nil }

local function actions() return vim.g.throttle_actions or DEFAULT_ACTIONS end

local function render()
  local items = actions()
  local cols = 2
  local rows = math.ceil(#items / cols)
  local cell_w = 28
  local cell_h = 3

  local lines = {}
  for r = 1, rows do
    -- top border for each cell row
    local top = ""
    for c = 1, cols do top = top .. "╭" .. string.rep("─", cell_w - 2) .. "╮ " end
    table.insert(lines, top)
    -- middle (content)
    local mid = ""
    for c = 1, cols do
      local idx = (r - 1) * cols + c
      local it = items[idx]
      if it then
        local text = string.format(" [%s]%s%s", it.key, it.icon, it.label)
        text = text .. string.rep(" ", cell_w - 2 - vim.fn.strdisplaywidth(text))
        mid = mid .. "│" .. text .. "│ "
      else
        mid = mid .. " " .. string.rep(" ", cell_w - 2) .. "  "
      end
    end
    table.insert(lines, mid)
    -- bottom
    local bot = ""
    for c = 1, cols do bot = bot .. "╰" .. string.rep("─", cell_w - 2) .. "╯ " end
    table.insert(lines, bot)
  end
  table.insert(lines, "")
  table.insert(lines, "    press a number to fire   ·   q to close")

  local w = #lines[1]
  local h = #lines
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"; vim.bo[state.buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = " ✈ THROTTLE ", title_pos = "center",
    width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
  })

  for _, it in ipairs(items) do
    vim.keymap.set("n", it.key, function()
      M.close(); vim.schedule(it.run)
    end, { buffer = state.buf, silent = true, nowait = true })
  end
  vim.keymap.set("n", "q", function() M.close() end, { buffer = state.buf, silent = true })
  vim.keymap.set("n", "<Esc>", function() M.close() end, { buffer = state.buf, silent = true })
end

function M.open() if state.win and vim.api.nvim_win_is_valid(state.win) then return end; render() end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.setup()
  vim.api.nvim_create_user_command("Throttle", M.open, { desc = "Open the throttle action launcher" })
end

return M
