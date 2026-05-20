-- Tiny World: an ASCII garden that grows over time from your activity.
-- Each commit adds a sprout. Each file you save waters it. Idle days
-- bring weather changes. State persists to ~/.local/state/nvim/tiny_world.json.
local M = {}

local STORE = vim.fn.stdpath("state") .. "/tiny_world.json"
local state = {
  saves = 0, commits = 0, day_started = nil, last_save = 0,
  trees = {},   -- { { age = days, size = 1..5, x = col, kind = "oak"|"pine"|"flower" }, ... }
}

local KINDS = {
  oak    = { "  ╭╮  ", "  ╰╯  ", "  ╱╲  ", " ╱  ╲ ", "╱    ╲" },  -- triangle leaves
  pine   = { "  ▲   ", " ▲▲▲  ", "▲▲▲▲▲ ", " ╭╮   ", " ╰╯   " },  -- pine
  flower = { " ✿    ", " │    ", " │    ", " │    ", " │    " },  -- flower
}

local function load()
  local f = io.open(STORE, "r")
  if not f then return end
  local data = f:read("*a"); f:close()
  local ok, parsed = pcall(vim.json.decode, data)
  if ok and type(parsed) == "table" then state = vim.tbl_deep_extend("force", state, parsed) end
end

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(STORE, ":h"), "p")
  local f = io.open(STORE, "w"); if not f then return end
  f:write(vim.json.encode(state)); f:close()
end

local function add_tree()
  local kinds = vim.tbl_keys(KINDS)
  table.insert(state.trees, {
    age = 0,
    size = 1,
    x = math.random(2, 70),
    kind = kinds[math.random(#kinds)],
  })
  while #state.trees > 12 do table.remove(state.trees, 1) end  -- cap
  save()
end

local function water_all()
  for _, t in ipairs(state.trees) do
    t.age = t.age + 1
    if t.age % 3 == 0 then t.size = math.min(5, t.size + 1) end
  end
  save()
end

local function compose_world()
  local W, H = 76, 12
  local lines = {}
  for _ = 1, H do table.insert(lines, string.rep(" ", W)) end

  -- Time of day → sky
  local hour = tonumber(os.date("%H"))
  local sky_line
  if hour >= 6 and hour < 18 then
    sky_line = "         ☀                    " .. string.rep(" ", W - 30)   -- day
  elseif hour >= 18 and hour < 21 then
    sky_line = "             ☄                  " .. string.rep(" ", W - 30) -- dusk
  else
    sky_line = "    ✦   ☾                   ✦  " .. string.rep(" ", W - 30) -- night
  end
  lines[1] = sky_line:sub(1, W)

  -- Ground line near bottom
  lines[H - 1] = string.rep("─", W)
  lines[H] = string.rep(" ", W)

  -- Plot trees: each tree's base sits on the ground line. Sprite drawn upward.
  for _, t in ipairs(state.trees) do
    local sprite = KINDS[t.kind]
    local size = math.max(1, math.min(t.size, #sprite))
    for i = 1, size do
      local sprite_row = sprite[#sprite - (size - i)]
      if sprite_row then
        local row = H - 1 - (size - i) - 1
        if row >= 2 then
          local existing = lines[row]
          local prefix = existing:sub(1, t.x - 1)
          local suffix = existing:sub(t.x + vim.api.nvim_strwidth(sprite_row))
          lines[row] = (prefix .. sprite_row .. suffix):sub(1, W)
        end
      end
    end
  end

  -- Status under the world
  table.insert(lines, "")
  table.insert(lines, string.format("    %d trees · %d saves · %d commits in your garden",
    #state.trees, state.saves, state.commits))
  table.insert(lines, "    [ s ] sow seed   [ w ] water   [ r ] reset   [ q ] close")
  return lines
end

local current_buf
local function refresh()
  if not current_buf or not vim.api.nvim_buf_is_valid(current_buf) then return end
  local lines = compose_world()
  vim.bo[current_buf].modifiable = true
  vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, lines)
  vim.bo[current_buf].modifiable = false
end

function M.show()
  load()
  current_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[current_buf].buftype = "nofile"; vim.bo[current_buf].bufhidden = "wipe"
  local W = 78
  local H = 16
  vim.api.nvim_open_win(current_buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = " 🌱 tiny world ", title_pos = "center",
    width = W, height = H,
    row = math.floor((vim.o.lines - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
  refresh()
  vim.keymap.set("n", "s", function() add_tree(); refresh() end, { buffer = current_buf, desc = "sow seed" })
  vim.keymap.set("n", "w", function() water_all(); refresh() end, { buffer = current_buf, desc = "water" })
  vim.keymap.set("n", "r", function()
    if vim.fn.confirm("Reset tiny world?", "&Yes\n&No", 2) == 1 then
      state = { saves = 0, commits = 0, trees = {} }; save(); refresh()
    end
  end, { buffer = current_buf, desc = "reset" })
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = current_buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = current_buf })
end

local function on_write()
  load()
  state.saves = (state.saves or 0) + 1
  -- Every 10 saves: sprout a new tree
  if state.saves % 10 == 0 then add_tree() end
  -- Every save: 1-in-3 chance to water
  if math.random(3) == 1 then water_all() else save() end
end

local function on_commit()
  -- Approximated: any save to a .git/COMMIT_EDITMSG (gitcommit ft) treated as commit
  load()
  state.commits = (state.commits or 0) + 1
  add_tree()
end

function M.setup()
  load()
  local grp = vim.api.nvim_create_augroup("user_tiny_world", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", { group = grp, callback = on_write })
  vim.api.nvim_create_autocmd("BufWritePost", { group = grp, pattern = "COMMIT_EDITMSG", callback = on_commit })
  vim.api.nvim_create_user_command("TinyWorld", M.show, { desc = "Show your ASCII garden" })
end

return M
