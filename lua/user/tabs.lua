-- Named tabs + brand-styled tabline. Tabs become a first-class concept:
-- each one has an editable label (defaults to cwd:t), shows a modified
-- indicator, and is click-jumpable. Composes bufferline's output after
-- the tab chips so buffer-switching affordance is preserved.
local M = {}

local brand = require("user.brand")
local icons = require("user.icons")

-- ─── persistent label store ──────────────────────────────────────────────
-- Names are keyed at runtime by *tabpage id* (stable across :tabmove and
-- middle :tabclose renumbers), but serialized to disk by tabnr (the only
-- thing that survives an nvim restart — tabids are fresh every session and
-- the tab order is the only thing the next session can match against). The
-- runtime/persistence layers are translated at the load/save boundary.
--
-- This matters for HCI: a name the user assigns ("api") must stay on the
-- tab they assigned it to until they rename it. Keyed-by-tabnr fails this
-- on :tabmove — Nielsen #4 (consistency) violation, and breaks the stable
-- letter-label scheme that hangs off names.
local STATE_FILE = vim.fn.stdpath("state") .. "/tab_names.json"
local _id_to_name = {}   -- runtime: [tabpage_id] = "frontend"

local function tabid_for_nr(nr)
  local pages = vim.api.nvim_list_tabpages()
  return pages[nr]
end

local function nr_for_tabid(tabid)
  for i, id in ipairs(vim.api.nvim_list_tabpages()) do
    if id == tabid then return i end
  end
  return nil
end

local function load_state()
  local f = io.open(STATE_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a"), { luanil = { object = true, array = true } })
  f:close()
  if not (ok and type(parsed) == "table") then return end
  -- parsed is {[tabnr] = name}; translate to {[current tabid for tabnr] = name}
  for k, v in pairs(parsed) do
    local nr = tonumber(k)
    local id = nr and tabid_for_nr(nr)
    if id then _id_to_name[id] = v end
  end
end

local function save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  -- Serialize as {[tabnr] = name} so a future session can match by position.
  local out = {}
  for id, name in pairs(_id_to_name) do
    local nr = nr_for_tabid(id)
    if nr then out[tostring(nr)] = name end
  end
  local f = io.open(STATE_FILE, "w")
  if f then f:write(vim.json.encode(out)); f:close() end
end

-- ─── naming ──────────────────────────────────────────────────────────────
-- Auto-derived name when nothing custom is set. cwd:t is the natural choice;
-- if cwd is $HOME or empty, fall back to the active buffer's project root or
-- finally to "tab N".
local function auto_name(tabnr)
  local ok, cwd = pcall(vim.fn.getcwd, -1, tabnr)
  if not ok or cwd == "" then cwd = vim.fn.getcwd() end
  local short = vim.fn.fnamemodify(cwd, ":t")
  if short == "" or cwd == vim.env.HOME then return "tab " .. tabnr end
  return short
end

function M.name_for(tabnr)
  local id = tabid_for_nr(tabnr)
  local custom = id and _id_to_name[id]
  if custom and custom ~= "" then return custom end
  return auto_name(tabnr)
end

function M.set_name(tabnr, name)
  tabnr = tabnr or vim.fn.tabpagenr()
  local id = tabid_for_nr(tabnr)
  if not id then return end
  if not name or name == "" then
    _id_to_name[id] = nil
  else
    _id_to_name[id] = name
  end
  save_state()
  pcall(vim.cmd, "redrawtabline")
end

-- ─── click dispatcher ────────────────────────────────────────────────────
M._click_handlers = {}
local _next_click_id = 0

function M._on_click(id, clicks, button, mods)
  local fn = M._click_handlers[id]
  if fn then pcall(fn, button or "l", mods or "", clicks or 1) end
end
_G._user_tabs_on_click = M._on_click

local function register_click(fn)
  _next_click_id = _next_click_id + 1
  local id = _next_click_id
  M._click_handlers[id] = fn
  return id
end

-- ─── highlights ──────────────────────────────────────────────────────────
local function apply_hl()
  local c = brand.c
  local set = vim.api.nvim_set_hl
  set(0, "UserTabActive",      { fg = c.bg,    bg = c.accent,  bold = true })
  set(0, "UserTabInactive",    { fg = c.text,  bg = c.surface })
  set(0, "UserTabModActive",   { fg = c.bg,    bg = c.accent,  bold = true })
  set(0, "UserTabModInactive", { fg = c.peach, bg = c.surface, bold = true })
  set(0, "UserTabFill",        { fg = c.muted, bg = "NONE" })
  set(0, "UserTabSep",         { fg = c.surface, bg = "NONE" })
  set(0, "UserTabAccentSep",   { fg = c.accent,  bg = "NONE" })
  set(0, "UserTabLabel",       { fg = c.accent, bg = c.surface, bold = true })
  set(0, "UserTabLabelActive", { fg = c.bg,     bg = c.accent,  bold = true, underline = true })
  -- Used during jump-by-label mode (feedforward): the [x] chunk inverts to
  -- accent bg / dark fg so it pops against the rest of the chip — the
  -- affordance reveals itself at the exact moment it matters, in the same
  -- region the user is already looking at (no head-bob to cmdline).
  set(0, "UserTabLabelPrompt", { fg = c.bg,     bg = c.peach,   bold = true })
end

-- Set true while M.jump_by_label() is waiting on a keystroke. render() reads
-- this flag and uses UserTabLabelPrompt for every [x] chunk. Mode entry/exit
-- triggers a redrawtabline so the visual change is synchronous with the
-- mode change (Vermeulen 2013: self-revealing gestures appear *at* the
-- moment of need, not before).
local _label_mode = false

-- ─── stable letter labels (HCI-grounded jump targets) ────────────────────
-- The tabnr addressing scheme (1..N) is *unstable*: any :tabmove or middle
-- :tabclose renumbers everything to the right, so the muscle memory the
-- user just built (tab 3 = "docs") silently breaks. Numbers feel primary
-- because they're prominent, but the addressing target underneath shifts.
--
-- Per Nielsen heuristic #6 (recognition rather than recall) + Fitts's Law
-- (one-keystroke target), we derive a stable single-char *label* from each
-- tab's name. The label persists across reorders because the name does.
-- The user sees `[s] src` in the chip and presses <M-j> s — no counting,
-- no renumbering surprise. Numeric <M-1..9> stays available as a positional
-- fallback for users whose muscle memory is already there (Nielsen #4:
-- consistency — don't yank existing affordances).
local function compute_labels()
  -- Assign labels in *tabid* order (creation order proxy, stable per session)
  -- rather than tabnr order. If we walked tabnrs, :tabmove would silently
  -- reshuffle labels even though names didn't change — Nielsen #4 violation.
  -- By walking tabids, the first-created tab named "src" keeps [s] forever
  -- (until renamed), regardless of where the user drags it.
  local entries = {}
  for nr, id in ipairs(vim.api.nvim_list_tabpages()) do
    entries[#entries + 1] = { nr = nr, id = id }
  end
  table.sort(entries, function(a, b) return a.id < b.id end)

  local used, labels = {}, {}
  for _, e in ipairs(entries) do
    local name = M.name_for(e.nr)
    local picked
    -- Pass 1: first lowercase a-z/0-9 char of the name not already taken.
    for j = 1, #name do
      local c = name:sub(j, j):lower()
      if c:match("[a-z0-9]") and not used[c] then
        picked = c; used[c] = true; break
      end
    end
    -- Pass 2: try uppercase letters of the name (collision relief).
    if not picked then
      for j = 1, #name do
        local c = name:sub(j, j):upper()
        if c:match("[A-Z]") and not used[c] then
          picked = c; used[c] = true; break
        end
      end
    end
    -- Pass 3: any unused digit 1-9 (Miller's law: cap at 9 distinct slots
    -- before we admit "you have too many tabs for letter-jump to be useful").
    if not picked then
      for d = 1, 9 do
        local c = tostring(d)
        if not used[c] then picked = c; used[c] = true; break end
      end
    end
    labels[e.nr] = picked or "?"
  end
  return labels
end

-- Expose to other surfaces (picker rows show the label so the panel
-- becomes a self-documenting cheat sheet — incidental learning).
function M.labels() return compute_labels() end

-- ─── render ──────────────────────────────────────────────────────────────
-- Composes:  [tab 1: name*] [tab 2: name] [tab 3: name] | <bufferline output>
-- Tab chip layout:  ▎ N · name <•>     where • is "●" when modified.
-- Bufferline (if present) is appended after a small gap so buffer chips
-- stay accessible.
function M.render()
  apply_hl()
  M._click_handlers = {}; _next_click_id = 0
  local cur_tab = vim.api.nvim_get_current_tabpage()
  local total = vim.fn.tabpagenr("$")
  local toggle_nr = M.toggle_target_nr()
  local labels = compute_labels()
  local out = { " " }

  for i = 1, total do
    local tabid = vim.api.nvim_list_tabpages()[i]
    local is_active = (tabid == cur_tab)
    local is_toggle = (i == toggle_nr) and not is_active
    local label = M.name_for(i):gsub("%%", "%%%%")  -- escape `%` for statusline

    -- modified detection + active-buffer ft (for the icon)
    local modified, active_buf = false, nil
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabid)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].modified then modified = true end
      -- pick the first non-special buffer in the tab for the icon
      if not active_buf and vim.bo[buf].buftype == "" then active_buf = buf end
    end
    -- icon for the active buffer's ft (falls back to "" if no real buffer yet)
    local icon = ""
    if active_buf then
      local fname = vim.api.nvim_buf_get_name(active_buf)
      local ft    = vim.bo[active_buf].filetype
      local info  = icons.ft(fname ~= "" and fname or nil, ft)
      icon = info.icon
    end

    local hl    = is_active and "UserTabActive"      or "UserTabInactive"
    local modhl = is_active and "UserTabModActive"   or "UserTabModInactive"

    -- left = jump · right = rename · middle = close
    local click_id = register_click(function(button)
      if button == "l" then
        pcall(vim.cmd, i .. "tabnext")
      elseif button == "r" then
        vim.ui.input({ prompt = "rename tab " .. i .. ": ", default = M.name_for(i) },
          function(v) if v then M.set_name(i, v) end end)
      elseif button == "m" then
        pcall(vim.cmd, i .. "tabclose")
      end
    end)

    -- The clickable region wraps the whole chip incl. modified glyph.
    -- Toggle target gets a ↶ glyph so you can SEE where <leader><tab><tab>
    -- will jump before you press it. The [letter] is the stable jump label
    -- — visible affordance for <M-j>{letter}, no recall required.
    local lead = is_toggle and "↶" or "▎"
    -- During jump-by-label mode, every [x] chunk uses the prompt highlight
    -- (feedforward: the affordance reveals itself in-place). Out of mode,
    -- the active tab keeps its inverted label and others stay subtle.
    local label_hl
    if _label_mode then label_hl = "UserTabLabelPrompt"
    else label_hl = is_active and "UserTabLabelActive" or "UserTabLabel" end
    local chip_lead = (" %s%d "):format(lead, i)
    local chip_label = ("%%#%s#[%s]%%#%s# "):format(label_hl, labels[i] or "?", hl)
    local chip_body = ("%s %s "):format(icon, label)
    local chip = chip_lead .. chip_label .. chip_body
    if modified then
      chip = chip .. "%#" .. modhl .. "#●  "
    else
      chip = chip .. " "
    end
    table.insert(out, ("%%%d@v:lua._user_tabs_on_click@%%#%s#%s%%X")
      :format(click_id, hl, chip))

    -- small gap between chips
    if i < total then table.insert(out, "%#UserTabFill#  ") end
  end
  table.insert(out, "%#UserTabFill#%T")

  -- Append bufferline's output (if the plugin is active) after a separator.
  -- bufferline.nvim exposes its tabline as `v:lua.nvim_bufferline()`.
  local ok, bl = pcall(function() return vim.fn["nvim_bufferline"]() end)
  if ok and type(bl) == "string" and bl ~= "" then
    table.insert(out, "%#UserTabFill#     ")
    table.insert(out, bl)
  end

  return table.concat(out)
end

-- ─── MRU history ─────────────────────────────────────────────────────────
-- Newest first. Tracked by tabpage id (not number) so the stack survives a
-- middle tab closing and renumbering the ones to its right. _mru[1] is the
-- current tab; _mru[2] is the toggle target for <leader><tab><tab>; deeper
-- entries drive picker ordering ("recent first" beats "tabnr order" once you
-- have 5+ tabs and remember which one you were just on, not its position).
local _mru = {}
local MRU_MAX = 16

local function mru_push(tabid)
  for i, id in ipairs(_mru) do
    if id == tabid then table.remove(_mru, i); break end
  end
  table.insert(_mru, 1, tabid)
  while #_mru > MRU_MAX do table.remove(_mru) end
end

local function mru_rank(tabid)
  for i, id in ipairs(_mru) do
    if id == tabid then return i end
  end
  return math.huge
end

-- Expose the toggle target so the tabline can mark it. Returns the tabnr
-- of the MRU[2] tab (the one <leader><tab><tab> will jump to), or nil.
function M.toggle_target_nr()
  local id = _mru[2]
  if not id or not vim.api.nvim_tabpage_is_valid(id) then return nil end
  for i = 1, vim.fn.tabpagenr("$") do
    if vim.api.nvim_list_tabpages()[i] == id then return i end
  end
  return nil
end

-- ─── operations ──────────────────────────────────────────────────────────
function M.jump(n)
  local total = vim.fn.tabpagenr("$")
  if n < 1 or n > total then
    brand.notify(("no tab %d (have %d)"):format(n, total), vim.log.levels.WARN, { title = "tabs" })
    return
  end
  pcall(vim.cmd, n .. "tabnext")
end

function M.jump_last()
  local prev = _mru[2]
  if not prev or not vim.api.nvim_tabpage_is_valid(prev) then
    brand.notify("no previous tab", vim.log.levels.INFO, { title = "tabs" })
    return
  end
  -- nvim_set_current_tabpage takes the id directly; no number lookup needed.
  vim.api.nvim_set_current_tabpage(prev)
end

-- Label-based jump. Drives feedforward through the tabline itself: while
-- waiting on the user's keystroke, every [x] chunk inverts to the prompt
-- highlight, so the affordance reveals itself in the region the user is
-- already looking at. No cmdline echo — that would split attention across
-- two screen regions (top tabline vs bottom cmdline). Single locus of
-- attention is the cognitive-load win (Sweller; Treisman attention research).
--
-- Vermeulen et al. 2013 ("Crossing the bridge over Norman's gulf of
-- execution") frames this as a *self-revealing gesture*: the system makes
-- the next valid input visible at the moment the user is about to give it.
function M.jump_by_label()
  local labels = compute_labels()
  local total = vim.fn.tabpagenr("$")
  if total <= 1 then
    brand.notify("only one tab open", vim.log.levels.INFO, { title = "tabs" })
    return
  end

  _label_mode = true
  pcall(vim.cmd, "redrawtabline")
  pcall(vim.cmd, "redraw")
  local ok, ch = pcall(vim.fn.getcharstr)
  _label_mode = false
  pcall(vim.cmd, "redrawtabline")

  if not ok or ch == "" or ch == "\27" then return end  -- esc cancels

  for nr, lab in pairs(labels) do
    if lab == ch or lab == ch:lower() then M.jump(nr); return end
  end
  brand.notify(("no tab labeled '%s'"):format(ch), vim.log.levels.WARN, { title = "tabs" })
end

function M.new_named()
  vim.ui.input({ prompt = "name new tab: " }, function(name)
    vim.cmd("tabnew")
    if name and name ~= "" then M.set_name(vim.fn.tabpagenr(), name) end
  end)
end

function M.close_others()
  local total = vim.fn.tabpagenr("$")
  if total <= 1 then return end
  -- Error prevention (Nielsen #5): a *named* tab signals user investment.
  -- An unnamed scratch tab doesn't. If we'd kill 2+ named tabs, confirm.
  -- Tabs the user just left lying around get closed without ceremony — the
  -- friction scales with the cost of the mistake. (Undo-close is the fallback
  -- if confirmation is misjudged: <leader><tab>u brings everything back.)
  local cur_nr = vim.fn.tabpagenr()
  local named_to_close, named_names = 0, {}
  for i = 1, total do
    if i ~= cur_nr then
      local id = tabid_for_nr(i)
      local nm = id and _id_to_name[id]
      if nm and nm ~= "" then
        named_to_close = named_to_close + 1
        named_names[#named_names + 1] = nm
      end
    end
  end
  if named_to_close >= 2 then
    local prompt = ("close %d named tab%s? (%s)"):format(
      named_to_close, named_to_close == 1 and "" or "s",
      table.concat(named_names, ", "))
    local choice = vim.fn.confirm(prompt, "&Yes\n&No", 2)
    if choice ~= 1 then return end
  end
  vim.cmd("tabonly")
  brand.notify(
    ("closed %d other tab%s · `:TabUndoClose` to restore"):format(
      total - 1, total - 1 == 1 and "" or "s"),
    vim.log.levels.INFO, { title = "tabs" })
end

function M.move(direction)
  local cur = vim.fn.tabpagenr()
  local total = vim.fn.tabpagenr("$")
  if direction == "left" then
    if cur == 1 then return end
    vim.cmd("tabmove -1")
  elseif direction == "right" then
    if cur == total then return end
    vim.cmd("tabmove +1")
  end
end

-- ─── undo-close: the safety net ──────────────────────────────────────────
-- We keep a rolling per-tab snapshot in _tab_snapshots, keyed by tabpage id.
-- Each TabEnter / BufWinEnter refreshes the entry for the current tab. When
-- a tab closes, the autocmd fires AFTER the tabpage is gone (so we can't
-- inspect it), but the snapshot from the last leave is still in our map —
-- we find the now-invalid id, pop the snapshot onto a closed-tab stack, and
-- :TabUndoClose pulls the top off.
local _tab_snapshots = {}    -- [tabpage_id] = { name, cwd, files, cursor }
local _closed_stack  = {}    -- newest first, capped
local CLOSED_MAX     = 10

local function record_tab(tabid)
  if not (tabid and vim.api.nvim_tabpage_is_valid(tabid)) then return end
  local files = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabid)) do
    local buf  = vim.api.nvim_win_get_buf(w)
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" and vim.bo[buf].buftype == "" then
      local cur  = vim.api.nvim_win_get_cursor(w)
      files[#files + 1] = { path = name, line = cur[1], col = cur[2] }
    end
  end
  -- Don't snapshot empty/special-only tabs — undoing them would just create
  -- an empty tab, which is noise not rescue.
  if #files == 0 then _tab_snapshots[tabid] = nil; return end
  -- Resolve tab number from id so getcwd(-1, tabnr) and _names lookup work.
  local tabnr
  for i, id in ipairs(vim.api.nvim_list_tabpages()) do
    if id == tabid then tabnr = i; break end
  end
  if not tabnr then return end
  local ok_cwd, tab_cwd = pcall(vim.fn.getcwd, -1, tabnr)
  _tab_snapshots[tabid] = {
    name  = _id_to_name[tabid],
    cwd   = ok_cwd and tab_cwd or vim.fn.getcwd(),
    files = files,
  }
end

local function harvest_closed()
  -- Any snapshot whose tabid is no longer a valid tabpage = the one that
  -- just closed. Push onto the stack (could be more than one if multiple
  -- tabs close in a single tick).
  for tabid, snap in pairs(_tab_snapshots) do
    if not vim.api.nvim_tabpage_is_valid(tabid) then
      table.insert(_closed_stack, 1, snap)
      _tab_snapshots[tabid] = nil
      while #_closed_stack > CLOSED_MAX do table.remove(_closed_stack) end
    end
  end
end

function M.undo_close()
  local snap = table.remove(_closed_stack, 1)
  if not snap then
    brand.notify("no closed tabs to restore", vim.log.levels.INFO, { title = "tabs" })
    return
  end
  -- Build the tab: first file as `tabnew <file>`, rest as vsplits. We don't
  -- attempt to recreate split orientation (would need to record window tree);
  -- one window per file is the high-value 80% and avoids replay surprises.
  local first = snap.files[1]
  vim.cmd("tabnew " .. vim.fn.fnameescape(first.path))
  pcall(vim.api.nvim_win_set_cursor, 0, { first.line, first.col })
  for i = 2, #snap.files do
    local f = snap.files[i]
    vim.cmd("vsplit " .. vim.fn.fnameescape(f.path))
    pcall(vim.api.nvim_win_set_cursor, 0, { f.line, f.col })
  end
  if snap.cwd and snap.cwd ~= "" then
    pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(snap.cwd))
  end
  if snap.name and snap.name ~= "" then
    M.set_name(vim.fn.tabpagenr(), snap.name)
  end
  brand.notify(
    ("restored tab '%s' (%d file%s)"):format(
      snap.name or vim.fn.fnamemodify(snap.cwd or "", ":t"),
      #snap.files, #snap.files == 1 and "" or "s"),
    vim.log.levels.INFO, { title = "tabs" })
end

-- Read-only counter for callers (suggest, statusline, etc.) that want to
-- gate UI on "is there anything to undo?"
function M.closed_count() return #_closed_stack end

-- Snapshot + picker. Telescope when available, vim.ui.select as fallback.
-- Sorted by MRU (most recent first) — when you have 5+ tabs, the next one
-- you want is almost always the one you were just on, not tab 1. We collect
-- the file list per tab here too so the previewer can render without ever
-- switching tabs (switching to read would dirty the MRU stack we just built).
local function snapshot()
  local items = {}
  local cur = vim.api.nvim_get_current_tabpage()
  local labels = compute_labels()
  for i = 1, vim.fn.tabpagenr("$") do
    local tabid = vim.api.nvim_list_tabpages()[i]
    local wins  = vim.api.nvim_tabpage_list_wins(tabid)
    local modified, files = false, {}
    for _, w in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(w)
      if vim.bo[buf].modified then modified = true end
      local name = vim.api.nvim_buf_get_name(buf)
      local bt   = vim.bo[buf].buftype
      if name ~= "" and bt == "" then
        files[#files + 1] = { path = name, modified = vim.bo[buf].modified, ft = vim.bo[buf].filetype }
      end
    end
    local ok_cwd, tab_cwd = pcall(vim.fn.getcwd, -1, i)
    items[#items + 1] = {
      nr        = i,
      tabid     = tabid,
      name      = M.name_for(i),
      label     = labels[i],
      win_count = #wins,
      modified  = modified,
      current   = (tabid == cur),
      mru_rank  = mru_rank(tabid),
      cwd       = ok_cwd and tab_cwd or vim.fn.getcwd(),
      files     = files,
    }
  end
  table.sort(items, function(a, b) return a.mru_rank < b.mru_rank end)
  return items
end

local function fmt_item(t)
  if t.ghost then
    -- Ghost rows surface the undo-close stack into the existing pick flow.
    -- Anticipatory design (UX 2020s): make recovery a first-class citizen
    -- instead of a separate keymap the user has to remember exists. The
    -- `↺` glyph + "(closed)" suffix signals "this isn't a live tab, but
    -- selecting it brings it back" — affordance + signifier in one row.
    return ("  ↺   %s  (closed · %d file%s)"):format(
      t.name, #t.files, #t.files == 1 and "" or "s")
  end
  local mark = t.current and "▎" or (t.mru_rank == 2 and "↶" or " ")
  local mod  = t.modified and "●" or " "
  -- [label] before the name builds incidental muscle memory: every time the
  -- user opens the picker to find a tab, they see the one-keystroke
  -- shortcut next to its name. Eventually the picker stops being needed.
  return ("%s %d [%s] %s %s  (%d win%s)"):format(
    mark, t.nr, t.label or "?", mod, t.name, t.win_count, t.win_count == 1 and "" or "s")
end

-- Expose closed-tab snapshots as picker entries. Tagged with `ghost = true`
-- so fmt_item / actions can branch on liveness.
local function ghost_entries()
  local out = {}
  for i, snap in ipairs(_closed_stack) do
    out[#out + 1] = {
      ghost     = true,
      stack_idx = i,
      name      = snap.name or vim.fn.fnamemodify(snap.cwd or "", ":t"),
      files     = snap.files or {},
      cwd       = snap.cwd or "",
    }
  end
  return out
end

local function restore_ghost(g)
  -- Pop the specific stack entry (not necessarily the top), then call the
  -- standard replay so the visual outcome matches <leader><tab>u.
  if not (g and g.stack_idx) then return end
  local snap = table.remove(_closed_stack, g.stack_idx)
  if not snap then return end
  -- Inline the replay logic from M.undo_close — same code path either way.
  local first = snap.files[1]
  if not first then return end
  vim.cmd("tabnew " .. vim.fn.fnameescape(first.path))
  pcall(vim.api.nvim_win_set_cursor, 0, { first.line, first.col })
  for i = 2, #snap.files do
    local f = snap.files[i]
    vim.cmd("vsplit " .. vim.fn.fnameescape(f.path))
    pcall(vim.api.nvim_win_set_cursor, 0, { f.line, f.col })
  end
  if snap.cwd and snap.cwd ~= "" then pcall(vim.cmd, "tcd " .. vim.fn.fnameescape(snap.cwd)) end
  if snap.name and snap.name ~= "" then M.set_name(vim.fn.tabpagenr(), snap.name) end
  brand.notify(("restored '%s'"):format(snap.name or "tab"),
               vim.log.levels.INFO, { title = "tabs" })
end

-- Open the picker. `mode` is "jump" (default) or "close" — only changes the
-- prompt title and the default action. Inline `<C-r>` rename and `<C-x>`
-- close work in either mode so you can do everything from one panel.
-- Closed tabs appear as ghost rows at the bottom — selecting one restores it.
local function open_picker(mode)
  local live   = snapshot()
  local ghosts = mode == "close" and {} or ghost_entries()  -- no point restoring on close-mode
  local items  = {}
  for _, t in ipairs(live)   do items[#items + 1] = t end
  for _, g in ipairs(ghosts) do items[#items + 1] = g end

  if #items == 0 or (#live <= 1 and #ghosts == 0) then
    brand.notify("only one tab open", vim.log.levels.INFO, { title = "tabs" })
    return
  end

  local ok_tel, telescope_pickers = pcall(require, "telescope.pickers")
  if not ok_tel then
    vim.ui.select(items, { prompt = mode == "close" and "close a tab" or "pick a tab",
                           format_item = fmt_item },
      function(t)
        if not t then return end
        if t.ghost then restore_ghost(t)
        elseif mode == "close" then pcall(vim.cmd, t.nr .. "tabclose")
        else M.jump(t.nr) end
      end)
    return
  end

  local finders    = require("telescope.finders")
  local conf       = require("telescope.config").values
  local actions    = require("telescope.actions")
  local action_st  = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local function refresh(prompt_bufnr)
    local picker = action_st.get_current_picker(prompt_bufnr)
    local fresh = {}
    for _, t in ipairs(snapshot()) do fresh[#fresh + 1] = t end
    if mode ~= "close" then
      for _, g in ipairs(ghost_entries()) do fresh[#fresh + 1] = g end
    end
    picker:refresh(finders.new_table({
      results = fresh,
      entry_maker = function(t)
        local ordinal = t.ghost and ("zz " .. t.name) or (t.nr .. " " .. t.name)
        return { value = t, display = fmt_item(t), ordinal = ordinal }
      end,
    }), { reset_prompt = false })
  end

  -- Preview pane: cwd line, then one row per file in the tab. Paths are
  -- rendered relative to the tab's cwd when possible (basename otherwise).
  local tab_previewer = previewers.new_buffer_previewer({
    title = "tab contents",
    define_preview = function(self, entry)
      local t = entry.value
      local lines = { ("cwd: %s"):format(vim.fn.fnamemodify(t.cwd, ":~")), "" }
      if #t.files == 0 then
        lines[#lines + 1] = "(no files in this tab — empty buffer or special windows only)"
      else
        for _, f in ipairs(t.files) do
          local rel = vim.fn.fnamemodify(f.path, ":~:.")
          -- prefer relative-to-cwd when the file lives under the tab's cwd
          if f.path:sub(1, #t.cwd) == t.cwd then
            rel = f.path:sub(#t.cwd + 2)  -- drop "cwd/" prefix
            if rel == "" then rel = vim.fn.fnamemodify(f.path, ":t") end
          end
          local mod = f.modified and "● " or "  "
          local icon = (icons.ft and icons.ft(f.path, f.ft) or {}).icon or ""
          lines[#lines + 1] = ("%s%s %s"):format(mod, icon, rel)
        end
      end
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = "tabpreview"
    end,
  })

  telescope_pickers.new({}, {
    prompt_title = mode == "close" and "tabs · close" or "tabs · jump",
    previewer = tab_previewer,
    finder = finders.new_table({
      results = items,
      entry_maker = function(t)
        -- Ghost rows sort to the bottom by ordinal-prefix "zz" so live tabs
        -- always come first in the unfiltered view, but typing the ghost's
        -- name still narrows to it via telescope's fuzzy match.
        local ordinal = t.ghost and ("zz " .. t.name) or (t.nr .. " " .. t.name)
        return { value = t, display = fmt_item(t), ordinal = ordinal }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local sel = action_st.get_selected_entry()
        actions.close(prompt_bufnr)
        if not (sel and sel.value) then return end
        local v = sel.value
        if v.ghost then restore_ghost(v); return end
        if mode == "close" then pcall(vim.cmd, v.nr .. "tabclose")
        else M.jump(v.nr) end
      end)
      -- <C-r>: rename the highlighted tab without leaving the picker.
      -- Ghost rows aren't live so renaming them is meaningless — no-op.
      local function rename_action()
        local sel = action_st.get_selected_entry()
        if not (sel and sel.value) or sel.value.ghost then return end
        local nr = sel.value.nr
        vim.ui.input({ prompt = ("rename tab %d: "):format(nr), default = M.name_for(nr) },
          function(v)
            if v then M.set_name(nr, v); refresh(prompt_bufnr) end
          end)
      end
      map("i", "<C-r>", rename_action)
      map("n", "<C-r>", rename_action)
      -- <C-x>: live tab → close it; ghost → drop it from the undo stack.
      -- Same gesture, both "remove this entry from view," which respects
      -- the user's expectation (Nielsen #4 consistency) regardless of liveness.
      local function close_action()
        local sel = action_st.get_selected_entry()
        if not (sel and sel.value) then return end
        local v = sel.value
        if v.ghost then
          table.remove(_closed_stack, v.stack_idx)
          refresh(prompt_bufnr)
        else
          pcall(vim.cmd, v.nr .. "tabclose")
          if vim.fn.tabpagenr("$") <= 1 and #_closed_stack == 0 then
            actions.close(prompt_bufnr)
          else refresh(prompt_bufnr) end
        end
      end
      map("i", "<C-x>", close_action)
      map("n", "<C-x>", close_action)
      return true
    end,
  }):find()
end

function M.pick()        open_picker("jump")  end
function M.pick_close()  open_picker("close") end

-- ─── commands + setup ────────────────────────────────────────────────────
function M.setup()
  load_state()
  mru_push(vim.api.nvim_get_current_tabpage())
  -- Take over the tabline. Schedule a re-assign on VeryLazy so plugins
  -- (bufferline) that also set tabline don't win the race.
  vim.opt.tabline = "%!v:lua.require'user.tabs'.render()"
  -- Calm Technology (Case, 2014): the tabline carries zero information when
  -- there's only one tab — hiding it then reclaims a row of vertical real
  -- estate for actual content. The tabline reappears the moment a second
  -- tab exists, so the affordance is never lost, just deferred until it
  -- matters. Set to 2 for always-on if you prefer the consistency.
  vim.opt.showtabline = 1
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy", once = true,
    callback = function() vim.opt.tabline = "%!v:lua.require'user.tabs'.render()" end,
  })

  local grp = vim.api.nvim_create_augroup("user_tabs", { clear = true })
  vim.api.nvim_create_autocmd({ "TabEnter", "TabNew", "BufWritePost",
                                "BufModifiedSet", "DirChanged", "BufEnter" }, {
    group = grp, callback = function() pcall(vim.cmd, "redrawtabline") end,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = grp,
    callback = function() mru_push(vim.api.nvim_get_current_tabpage()) end,
  })
  -- Keep the per-tab snapshot fresh so undo-close has something to restore.
  -- Capture the tabid synchronously (current tab at autocmd fire time) and
  -- defer the actual snapshot one tick so vsplit/split operations have
  -- time to register the new window in nvim_tabpage_list_wins(). Without
  -- the capture, the scheduled callback would read whichever tab happens
  -- to be current later — wrong for rapid TabEnter sequences (tabnew foo;
  -- tabnew bar would snapshot bar into foo's slot).
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinNew", "WinClosed",
                                "TabLeave", "TabEnter", "DirChanged" }, {
    group = grp,
    callback = function()
      local tabid = vim.api.nvim_get_current_tabpage()
      vim.schedule(function() pcall(record_tab, tabid) end)
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = grp,
    callback = function()
      pcall(harvest_closed)
      -- Reap names of any tabpage id that no longer exists. Tabid-keyed
      -- naming makes :tabmove "just work", and this loop cleans up after
      -- :tabclose so the persistent state file doesn't grow unbounded.
      for id in pairs(_id_to_name) do
        if not vim.api.nvim_tabpage_is_valid(id) then
          _id_to_name[id] = nil
        end
      end
      pcall(save_state)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = apply_hl })

  vim.api.nvim_create_user_command("TabName", function(a)
    M.set_name(nil, a.args ~= "" and a.args or nil)
  end, { nargs = "?", desc = "Set current tab name (no args clears the custom name)" })

  vim.api.nvim_create_user_command("TabRename", function()
    local nr = vim.fn.tabpagenr()
    vim.ui.input({ prompt = "tab name: ", default = M.name_for(nr) },
      function(v) if v then M.set_name(nr, v) end end)
  end, { desc = "Rename current tab interactively" })

  vim.api.nvim_create_user_command("TabRenameAuto", function()
    M.set_name(nil, nil)
  end, { desc = "Clear the custom name (revert to auto-derived)" })

  vim.api.nvim_create_user_command("TabNewNamed", M.new_named,
    { desc = "Create a new tab and prompt for its name" })
  vim.api.nvim_create_user_command("TabPick", M.pick,
    { desc = "Pick a tab by name (telescope/select)" })
  vim.api.nvim_create_user_command("TabPickClose", M.pick_close,
    { desc = "Pick a tab to close (telescope/select)" })
  vim.api.nvim_create_user_command("TabUndoClose", M.undo_close,
    { desc = "Reopen the most recently closed tab (up to 10 deep)" })
  vim.api.nvim_create_user_command("TabCloseOthers", M.close_others,
    { desc = "Close every tab except the current one" })
  vim.api.nvim_create_user_command("TabLast", M.jump_last,
    { desc = "Jump to the most recently used tab (toggle)" })
  vim.api.nvim_create_user_command("TabJumpLabel", M.jump_by_label,
    { desc = "Prompt for a tab letter label and jump (stable across reorder)" })
  vim.api.nvim_create_user_command("TabMoveLeft", function() M.move("left") end,
    { desc = "Move current tab one position left" })
  vim.api.nvim_create_user_command("TabMoveRight", function() M.move("right") end,
    { desc = "Move current tab one position right" })
end

return M
