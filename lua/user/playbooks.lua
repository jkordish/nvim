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
-- Builds a one-line progress string with dots showing chain state:
--   ✦  morning routine        [● ◐ ○ ○]  save
-- ● done · ◐ current · ○ pending · ✗ failed
local function progress_line(chain, step, status, name)
  local glyph = status == "done" and "✓"
             or status == "error" and "✗"
             or "✦"
  local dots = {}
  for i = 1, #chain do
    if i < step or status == "done" then table.insert(dots, "●")
    elseif i == step and status == "error" then table.insert(dots, "✗")
    elseif i == step then table.insert(dots, "◐")
    else table.insert(dots, "○") end
  end
  local trailing = chain[step] or "—"
  if status == "done"  then trailing = ("%d step%s"):format(#chain, #chain == 1 and "" or "s") end
  return string.format("%s  %-22s [%s]  %s",
    glyph, name:sub(1, 22), table.concat(dots, " "), trailing)
end

-- Module-level: most recently fired playbook. The statusline LED reads this
-- via M.last_fired() and renders a chip that fades after LED_TTL_SECONDS.
M._last_fired = nil
local LED_TTL_SECONDS = 600  -- 10 minutes

function M.last_fired()
  if not M._last_fired then return nil end
  if (os.time() - M._last_fired.ts) > LED_TTL_SECONDS then
    M._last_fired = nil
    return nil
  end
  return M._last_fired
end

function M.run_chain(chain, opts)
  opts = opts or {}
  local quiet = opts.quiet == true
  local key  = chain_key(chain)
  local name = meta.names[key] or "playbook"

  -- Record the fire for the statusline LED. Status flips done/error as the
  -- chain progresses so the LED can show outcome too.
  M._last_fired = { name = name, key = key, chain = chain, ts = os.time(), status = "running" }

  -- Persistent notification handle that we mutate as the chain progresses
  local handle = nil
  local function toast(text, level, replace, timeout)
    if quiet then return end
    local ok, ret = pcall(vim.notify, text, level or vim.log.levels.INFO, {
      title   = "playbook",
      replace = replace,
      timeout = timeout,         -- false = pinned, number = ms before fade
    })
    if ok then return ret end
  end

  -- Open the persistent toast right away
  handle = toast(progress_line(chain, 1, "running", name), vim.log.levels.INFO, nil, false)

  local suggest = require("user.suggest")
  local i = 0
  local function step()
    i = i + 1
    if i > #chain then
      handle = toast(progress_line(chain, #chain, "done", name), vim.log.levels.INFO, handle, 2200)
      if M._last_fired then M._last_fired.status = "done"; M._last_fired.ts = os.time() end
      return
    end
    handle = toast(progress_line(chain, i, "running", name), vim.log.levels.INFO, handle, false)

    local action = suggest.find_action(chain[i])
    if not action then
      handle = toast(progress_line(chain, i, "error", name) .. "  · action not found",
        vim.log.levels.ERROR, handle, 5000)
      if M._last_fired then M._last_fired.status = "error"; M._last_fired.ts = os.time() end
      return
    end
    local c = suggest.context()
    local ok, err = pcall(action.run, c)
    if not ok then
      handle = toast(progress_line(chain, i, "error", name) .. "  · " .. tostring(err):sub(1, 60),
        vim.log.levels.ERROR, handle, 5000)
      if M._last_fired then M._last_fired.status = "error"; M._last_fired.ts = os.time() end
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

  -- Chip-styled layout, matching the suggest panel's design vocabulary:
  --   "  [ N ] [F2 ] name                ×7"   ← row 1 (chips + label)
  --   "         save → test_nearest → commit"  ← row 2 (chain, dimmed)
  -- Each item takes 2 buffer rows. Digit chip mirrors suggest (accent for top,
  -- surface for others). Pin chip mirrors learned-marker styling (ok-green
  -- when pinned, blank otherwise). Chain on its own line keeps the top row
  -- short + readable; the chain row goes dim via BrandSubtext.
  local lines = { "" }
  state.chip_rows = {}  -- map item index → 0-indexed row for highlight targeting
  if #items == 0 then
    table.insert(lines, "        no playbooks discovered yet.")
    table.insert(lines, "")
    table.insert(lines, "        pick a few sequences in :Suggest within 2 minutes")
    table.insert(lines, "        of each other. after 3 repeats they'll surface here.")
  else
    for i, it in ipairs(items) do
      local key = chain_key(it.chain)
      local pin = pinned_label_for(key)
      local pin_chip = pin and (" " .. pin:gsub("[<>]", "") .. " ") or "     "  -- " F2 " or 5 spaces
      local name = meta.names[key] or "—"
      if #name > 26 then name = name:sub(1, 24) .. "…" end
      -- Row 1: chip block + name + strength
      table.insert(lines, string.format("  %s %s  %-26s  ×%d",
        (" %d "):format(i),   -- 3-col digit chip
        pin_chip,              -- 4-col pin chip
        name,
        it.strength))
      state.chip_rows[i] = #lines - 1
      -- Row 2: chain steps, dimmed
      local chain_visual = table.concat(it.chain, "  →  ")
      table.insert(lines, "         " .. chain_visual)
    end
  end
  table.insert(lines, "")
  table.insert(lines, "    " .. string.rep("─", 70))
  table.insert(lines, "    [n] name   [p] pin to F-key   [u] unpin   [d] delete    [q] close")
  table.insert(lines, "")

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Chip-styled highlights. Iterate items directly (not by line pattern) so
  -- column math stays exact and the design language matches the suggest panel.
  for i, it in ipairs(items) do
    local row = state.chip_rows[i]
    if row then
      local is_top = (i == 1)
      local key = chain_key(it.chain)
      local pinned = pinned_label_for(key) ~= nil
      -- Digit chip "  N  ": cols 2..5 (3 bytes — " N ")
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 2, {
        end_col = 5, hl_group = is_top and "BrandChipAccent" or "BrandChipSurface",
      })
      -- Pin chip " F2 ": cols 6..10 (4 bytes — " F2 "). Only colored when pinned.
      if pinned then
        pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 6, {
          end_col = 10, hl_group = "BrandChipOk",
        })
      end
      -- Name in bold accent for top item; default text for others. Name starts
      -- at col 12 (2 spaces after the pin chip block).
      if is_top then
        pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 12, {
          end_line = row + 1, hl_group = "BrandAccent",
        })
      end
      -- Chain row directly below — dim via BrandSubtext, arrows stay readable
      local chain_row = row + 1
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, chain_row, 0, {
        end_line = chain_row + 1, hl_group = "BrandSubtext",
      })
    end
  end
  -- Empty-state lines + divider + footer dimmed
  for r, line in ipairs(lines) do
    local row = r - 1
    if line:find("^%s+─") or line:find("^%s+%[n%]") then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandMuted" })
    end
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
  if not state.chip_rows then return nil end
  local cursor_row = vim.api.nvim_win_get_cursor(state.win)[1] - 1  -- 0-indexed
  -- Each item now spans two rows (chip + chain). Find the item whose chip row
  -- or chain row contains the cursor.
  local focused_idx
  for i, chip_row in ipairs(state.chip_rows) do
    if chip_row <= cursor_row and cursor_row <= chip_row + 1 then
      focused_idx = i
      break
    elseif chip_row > cursor_row then
      break
    else
      focused_idx = i  -- still closest above
    end
  end
  if not focused_idx then return nil end
  return state.items[focused_idx]
end

function M.show()
  load_meta()
  if state.win and vim.api.nvim_win_is_valid(state.win) then close(); return end
  local items = M.discover()

  local W = 78
  -- Each item is now 2 rows (chip + chain); +6 for header/divider/footer/blank
  local H = math.max(8, #items * 2 + 6)

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
