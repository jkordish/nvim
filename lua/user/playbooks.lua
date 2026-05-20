-- Playbooks: turns Suggest's pairwise sequence learning into named,
-- pinnable, multi-step chains. Walks the sequences graph from each action
-- and surfaces the strongest "if X → Y → Z" paths. You can name them and
-- pin to F2-F5 so a single key fires the whole sequence.
local M = {}

local META_FILE = vim.fn.stdpath("state") .. "/playbooks.json"
local MIN_STEP_COUNT = 3   -- transition needs ≥3 occurrences to extend a chain
local MAX_CHAIN_LEN  = 5
local STEP_DELAY_MS  = 250  -- between sequential action executions

-- ─── persistent metadata (names + pins) ────────────────────────────────────
local meta = {
  names = {},     -- chain_key -> "display name"
  pins  = {},     -- "F2" -> chain_key
  hidden = {},    -- chain_key -> true (suppress from panel)
}

local function load_meta()
  local f = io.open(META_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if ok and type(parsed) == "table" then
    meta = vim.tbl_deep_extend("force", meta, parsed)
  end
end

local function save_meta()
  vim.fn.mkdir(vim.fn.fnamemodify(META_FILE, ":h"), "p")
  local f = io.open(META_FILE, "w")
  if f then f:write(vim.json.encode(meta)); f:close() end
end

local function chain_key(chain) return table.concat(chain, "→") end

-- ─── chain discovery ───────────────────────────────────────────────────────
local function chain_from(seqs, start_id)
  local chain = { start_id }
  local seen = { [start_id] = true }
  local total_strength = math.huge
  for _ = 2, MAX_CHAIN_LEN do
    local trans = seqs[chain[#chain]]
    if not trans then break end
    local best, best_count = nil, 0
    for next_id, count in pairs(trans) do
      if not seen[next_id] and count > best_count and count >= MIN_STEP_COUNT then
        best, best_count = next_id, count
      end
    end
    if not best then break end
    table.insert(chain, best)
    seen[best] = true
    total_strength = math.min(total_strength, best_count)
  end
  if total_strength == math.huge then return nil end
  return { chain = chain, strength = total_strength }
end

function M.discover()
  local s = require("user.suggest").sequences()
  local seen_starts = {}
  local out = {}
  for start_id in pairs(s) do
    if not seen_starts[start_id] then
      local c = chain_from(s, start_id)
      if c and #c.chain >= 2 then
        table.insert(out, c)
        for _, id in ipairs(c.chain) do seen_starts[id] = true end  -- avoid sub-chains
      end
    end
  end
  table.sort(out, function(a, b) return a.strength > b.strength end)
  -- Apply hidden filter
  local filtered = {}
  for _, c in ipairs(out) do
    if not meta.hidden[chain_key(c.chain)] then table.insert(filtered, c) end
  end
  return filtered
end

-- ─── execution ─────────────────────────────────────────────────────────────
function M.run_chain(chain, opts)
  opts = opts or {}
  local suggest = require("user.suggest")
  local i = 0
  local function step()
    i = i + 1
    if i > #chain then
      pcall(function()
        require("user.brand").notify(("playbook complete · %d steps"):format(#chain),
          nil, { title = "playbook" })
      end)
      return
    end
    local action = suggest.find_action(chain[i])
    if not action then
      pcall(function()
        require("user.brand").notify(("step %d (%s) not found · stopped"):format(i, chain[i]),
          vim.log.levels.WARN, { title = "playbook" })
      end)
      return
    end
    local c = suggest.context()
    local ok, err = pcall(action.run, c)
    if not ok then
      pcall(function()
        require("user.brand").notify(("step %d (%s) failed · %s"):format(i, chain[i], err),
          vim.log.levels.ERROR, { title = "playbook" })
      end)
      return
    end
    vim.defer_fn(step, STEP_DELAY_MS)
  end
  step()
end

function M.run_by_name(name)
  for key, n in pairs(meta.names) do
    if n == name then
      local chain = vim.split(key, "→", { plain = true })
      M.run_chain(chain)
      return
    end
  end
  -- Or treat name as a literal chain_key
  if meta.names[name] or name:find("→") then
    M.run_chain(vim.split(name, "→", { plain = true }))
    return
  end
  pcall(function()
    require("user.brand").notify("no playbook named " .. name, vim.log.levels.WARN, { title = "playbook" })
  end)
end

-- ─── pin management ────────────────────────────────────────────────────────
local PIN_KEYS = { "<F2>", "<F3>", "<F4>", "<F5>" }

local function rebind_pins()
  -- Unbind first (best-effort)
  for _, k in ipairs(PIN_KEYS) do pcall(vim.keymap.del, "n", k) end
  for k, key in pairs(meta.pins) do
    local chain = vim.split(key, "→", { plain = true })
    vim.keymap.set("n", k, function() M.run_chain(chain) end,
      { silent = true, desc = "Playbook: " .. (meta.names[key] or key) })
  end
end

function M.pin(chain, pin_key)
  meta.pins[pin_key] = chain_key(chain)
  save_meta()
  rebind_pins()
  pcall(function()
    require("user.brand").notify(pin_key .. " → " .. (meta.names[chain_key(chain)] or chain_key(chain)),
      nil, { title = "playbook · pinned" })
  end)
end

function M.unpin(pin_key)
  meta.pins[pin_key] = nil
  save_meta()
  rebind_pins()
end

-- ─── name / hide ───────────────────────────────────────────────────────────
function M.name(chain, name) meta.names[chain_key(chain)] = name; save_meta() end
function M.hide(chain)       meta.hidden[chain_key(chain)] = true; save_meta() end
function M.unhide_all()      meta.hidden = {}; save_meta() end

-- ─── panel ─────────────────────────────────────────────────────────────────
local state = { win = nil, buf = nil, items = {} }
local NS = vim.api.nvim_create_namespace("user_playbooks")

local function pinned_label_for(key)
  for pkey, cval in pairs(meta.pins) do
    if cval == key then return pkey end
  end
end

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win, state.buf, state.items = nil, nil, {}
end

local function render(items)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  state.items = items
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)

  local lines = { "" }
  if #items == 0 then
    table.insert(lines, "        no playbooks discovered yet.")
    table.insert(lines, "")
    table.insert(lines, "        pick a few sequences in :Suggest within 2 minutes")
    table.insert(lines, "        of each other. after 3 repeats they'll surface here.")
  else
    for i, it in ipairs(items) do
      local key = chain_key(it.chain)
      local pin = pinned_label_for(key)
      local name = meta.names[key] or "—"
      -- format: "  N  <pin>  <name>  · step → step → step  · ×N"
      local chain_visual = table.concat(it.chain, "  →  ")
      table.insert(lines, string.format("    %d  %-5s  %-18s  %s    ×%d",
        i,
        pin and "[" .. pin:gsub("[<>]", "") .. "]" or "     ",
        name:sub(1, 18),
        chain_visual,
        it.strength
      ))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "    " .. string.rep("─", 70))
  table.insert(lines, "    [n] name   [p] pin to F-key   [u] unpin   [d] delete    [q] close")
  table.insert(lines, "")

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Highlights
  for r, line in ipairs(lines) do
    local row = r - 1
    -- digit prefix in accent
    local digit = line:match("^%s+(%d)%s")
    if digit then
      local col = #line:match("^(%s+)")
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, col,
        { end_col = col + 1, hl_group = "BrandAccent" })
    end
    -- pin brackets in ok-green
    local pin_s, pin_e = line:find("%[F%d%]")
    if pin_s then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, pin_s - 1,
        { end_col = pin_e, hl_group = "BrandOk" })
    end
    -- → arrows in subtext
    local a_s = 1
    while true do
      local s2, e2 = line:find("→", a_s, true)
      if not s2 then break end
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, s2 - 1,
        { end_col = e2, hl_group = "BrandSubtext" })
      a_s = e2 + 1
    end
    -- divider + footer
    if line:find("^%s+─") or line:find("^%s+%[n%]") then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandMuted" })
    end
    -- empty-state lines
    if #items == 0 and (line:find("^%s+no playbooks") or line:find("^%s+pick a few")) then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandMuted" })
    end
  end

  -- Number key bindings: 1-9 fires that chain
  for i = 1, 9 do pcall(vim.keymap.del, "n", tostring(i), { buffer = state.buf }) end
  for i = 1, math.min(9, #items) do
    vim.keymap.set("n", tostring(i), function()
      close()
      vim.schedule(function() M.run_chain(items[i].chain) end)
    end, { buffer = state.buf, silent = true, nowait = true })
  end
end

local function selected_item()
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  -- Items start at row 2 (after blank), so row-1 is the index
  local idx = row - 1
  return state.items[idx]
end

function M.show()
  load_meta()
  if state.win and vim.api.nvim_win_is_valid(state.win) then close(); return end
  local items = M.discover()

  local W = 78
  local H = math.max(8, #items + 6)

  local r = require("user.brand").win({
    title = "playbooks",
    width = W, height = H,
    anchor = "center",
    close_keys = { "q", "<Esc>" },
    animate = true,
  })
  state.win, state.buf = r.win, r.buf

  render(items)

  -- Action keymaps (n/p/u/d) inside panel
  vim.keymap.set("n", "n", function()
    local it = selected_item(); if not it then return end
    vim.ui.input({ prompt = "playbook name: ", default = meta.names[chain_key(it.chain)] or "" }, function(input)
      if input and input ~= "" then
        M.name(it.chain, input)
        render(M.discover())
      end
    end)
  end, { buffer = state.buf, silent = true, desc = "name this playbook" })

  vim.keymap.set("n", "p", function()
    local it = selected_item(); if not it then return end
    vim.ui.select(PIN_KEYS, { prompt = "pin to which key?" }, function(choice)
      if choice then M.pin(it.chain, choice); render(M.discover()) end
    end)
  end, { buffer = state.buf, silent = true, desc = "pin to F-key" })

  vim.keymap.set("n", "u", function()
    local active_pins = vim.tbl_keys(meta.pins); if #active_pins == 0 then
      pcall(function() require("user.brand").notify("no pins to remove") end); return
    end
    vim.ui.select(active_pins, { prompt = "unpin which key?" }, function(choice)
      if choice then M.unpin(choice); render(M.discover()) end
    end)
  end, { buffer = state.buf, silent = true, desc = "unpin" })

  vim.keymap.set("n", "d", function()
    local it = selected_item(); if not it then return end
    if vim.fn.confirm("hide this playbook?", "&Yes\n&No", 2) == 1 then
      M.hide(it.chain); render(M.discover())
    end
  end, { buffer = state.buf, silent = true, desc = "hide" })
end

function M.list_named()
  local out = {}
  for key, name in pairs(meta.names) do
    table.insert(out, { name = name, key = key })
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function M.setup()
  load_meta()
  rebind_pins()   -- re-register any pinned F-keys at every nvim start
  vim.api.nvim_create_user_command("Playbooks",       M.show,        { desc = "Browse discovered playbooks" })
  vim.api.nvim_create_user_command("PlaybookRun",
    function(args) M.run_by_name(args.args) end,
    { nargs = 1, complete = function()
      local names = {}
      for _, p in ipairs(M.list_named()) do table.insert(names, p.name) end
      return names
    end, desc = "Run a named playbook" })
  vim.api.nvim_create_user_command("PlaybookForget", M.unhide_all,   { desc = "Show all hidden playbooks again" })
end

return M
