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
local UNDO_FILE  = vim.fn.stdpath("state") .. "/tab_undo_stack.json"
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

-- Previous-name history, keyed by tabpage id. One-deep — enough to revert
-- a typo or a misjudged rename without persisting unbounded history.
-- Forgiveness principle (Tognazzini's First Principles; Norman 2013 revision):
-- destructive actions must be reversible without the user remembering the
-- old value. Rename was the asymmetric blind spot — close-undo existed,
-- rename-undo didn't. Kept in-memory only; persistent rename history would
-- bloat the state file for a vanishingly small recovery window.
local _prev_name = {}

function M.set_name(tabnr, name, opts)
  tabnr = tabnr or vim.fn.tabpagenr()
  opts = opts or {}
  local id = tabid_for_nr(tabnr)
  if not id then return end
  -- Save the outgoing custom name (if any) so revert_rename can swap back.
  -- Skipped when the caller is a revert (otherwise revert→revert would lose
  -- the original target).
  if not opts.from_revert then
    local outgoing = _id_to_name[id]
    if outgoing and outgoing ~= "" and outgoing ~= name then
      _prev_name[id] = outgoing
    end
  end
  if not name or name == "" then
    _id_to_name[id] = nil
  else
    _id_to_name[id] = name
  end
  save_state()
  pcall(vim.cmd, "redrawtabline")
end

-- Returns the previously-set custom name for a tab, or nil.
function M.previous_name(tabnr)
  local id = tabid_for_nr(tabnr or vim.fn.tabpagenr())
  return id and _prev_name[id] or nil
end

function M.revert_rename(tabnr)
  tabnr = tabnr or vim.fn.tabpagenr()
  local id = tabid_for_nr(tabnr)
  if not id then return end
  local prev = _prev_name[id]
  if not prev or prev == "" then
    brand.notify("no rename to revert on this tab", vim.log.levels.INFO, { title = "tabs" })
    return
  end
  -- Swap current ⇄ previous so the revert is itself revertible. The opts
  -- flag prevents set_name from clobbering _prev_name with the swap value.
  local now_current = _id_to_name[id]
  _prev_name[id] = now_current
  M.set_name(tabnr, prev, { from_revert = true })
  brand.notify(("reverted to '%s' (now '%s' is the previous)"):format(prev, now_current or "(auto)"),
               vim.log.levels.INFO, { title = "tabs" })
end

-- Reap _prev_name entries for tabpage ids that no longer exist. Called from
-- the TabClosed cleanup loop so the table doesn't grow unbounded.
local function reap_prev_names()
  for id in pairs(_prev_name) do
    if not vim.api.nvim_tabpage_is_valid(id) then _prev_name[id] = nil end
  end
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
  -- Transient highlight for just-restored tabs (1.5s after undo_close /
  -- batch undo / ghost-row restore). Green-tinted to read as "this chip
  -- came back" without competing with the active-tab accent.
  set(0, "UserTabRestored",    { fg = c.bg,     bg = c.green or c.accent, bold = true })
  -- Pre-attentive error indicator (Treisman 1980 feature-integration theory;
  -- Healey & Enns 2012; Ware 2019). Red fg pops against the surface in any
  -- row of normal-toned chips — color contrast is processed pre-attentively
  -- so the user's eye is drawn to the urgent tab without conscious scanning.
  -- Two variants: one for the active chip (sits on accent bg) and one for
  -- inactive (sits on surface bg) so contrast stays high either way.
  set(0, "UserTabError",       { fg = c.red or "#f38ba8", bg = c.surface, bold = true })
  set(0, "UserTabErrorActive", { fg = c.red or "#f38ba8", bg = c.accent,  bold = true })
end

-- Set true while M.jump_by_label() is waiting on a keystroke. render() reads
-- this flag and uses UserTabLabelPrompt for every [x] chunk. Mode entry/exit
-- triggers a redrawtabline so the visual change is synchronous with the
-- mode change (Vermeulen 2013: self-revealing gestures appear *at* the
-- moment of need, not before).
local _label_mode = false

-- Transient "just restored" marker. Set by mark_restored(tabid); render()
-- highlights the chip and prepends ↺ for the remaining duration. Calm Tech
-- (Case 2014) + eye-mind hypothesis (Just & Carpenter 1976/1980): feedback
-- in the region of action, where the user's eye is already going, not in a
-- central pop-up notification that pulls attention to a different screen
-- area. Bartram 2002 "Whisper, Don't Scream" — a 1.5s in-place flash is
-- sub-threshold for distraction but pre-attentively detectable.
local _restored_until = {}   -- [tabid] = vim.uv.now() + ms

-- Per-tab ERROR-severity diagnostic count, cached. Recomputing on every
-- render() (which fires many times per second under cursor movement etc.)
-- would burn CPU; we invalidate the cache on DiagnosticChanged via the
-- autocmd registered in setup(). Bounded by the number of tabs, so size
-- is irrelevant. Warnings/info/hints are excluded — they're too common to
-- be load-bearing as a pre-attentive cue, and using all severities would
-- light up most tabs most of the time (noise > signal).
local _err_count_cache = {}

local function tab_error_count(tabid)
  local hit = _err_count_cache[tabid]
  if hit ~= nil then return hit end
  local total = 0
  local ok_wins, wins = pcall(vim.api.nvim_tabpage_list_wins, tabid)
  if ok_wins then
    local seen_bufs = {}
    for _, w in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(w)
      if not seen_bufs[buf] then
        seen_bufs[buf] = true
        local diags = vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
        total = total + #diags
      end
    end
  end
  _err_count_cache[tabid] = total
  return total
end

local function mark_restored(tabid, ms)
  if not tabid then return end
  ms = ms or 1500
  _restored_until[tabid] = vim.uv.now() + ms
  pcall(vim.cmd, "redrawtabline")
  -- Schedule a second redraw so the highlight clears even when nothing
  -- else triggers a redraw between now and the expiry.
  vim.defer_fn(function() pcall(vim.cmd, "redrawtabline") end, ms + 30)
end

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

-- ─── input with live label preview ───────────────────────────────────────
-- A floating one-line prompt that shows two pieces of feedforward as the
-- user types a tab name:
--   • title bar: the labels currently in use (info at point of decision)
--   • trailing virtual text: the label THIS name will yield once submitted
-- Updates on every keystroke (TextChangedI). Per Yang, Steinfeld & Rosé
-- (CHI 2020), the system surfaces the consequence of input *as it's being
-- entered*, not after — closing Norman's gulf of evaluation pre-emptively
-- so the user doesn't have to commit to a name to learn what label it gets.
--
-- Falls through to vim.ui.input (with a static "[in use: ...]" hint in the
-- prompt label) when the floating window can't be created — e.g., headless
-- runs or when this code is reached before a UI exists.
local function preview_label_for(name, taken_set)
  if not name or name == "" then return "?" end
  local used = vim.deepcopy(taken_set)
  for j = 1, #name do
    local c = name:sub(j, j):lower()
    if c:match("[a-z0-9]") and not used[c] then return c end
  end
  for j = 1, #name do
    local c = name:sub(j, j):upper()
    if c:match("[A-Z]") and not used[c] then return c end
  end
  for d = 1, 9 do
    local c = tostring(d)
    if not used[c] then return c end
  end
  return "?"
end

local function input_with_label_preview(opts, callback)
  opts = opts or {}
  local prompt  = opts.prompt or "name: "
  local default = opts.default or ""
  local except  = opts.except_tabnr  -- exclude this tab from the "taken" set

  -- Build the taken-label set for the title and the preview calculator.
  local labels = compute_labels()
  local taken  = {}
  for nr, lab in pairs(labels) do
    if nr ~= except then taken[lab] = true end
  end
  local taken_list = {}
  for lab in pairs(taken) do taken_list[#taken_list + 1] = lab end
  table.sort(taken_list)
  local taken_hint = #taken_list > 0
    and ("in use: " .. table.concat(taken_list, " "))
    or "no labels yet"

  -- Forgiveness disclosure: when the tab being renamed has a previous-name
  -- on file, surface "(was: oldname)" in the title bar so the user knows
  -- the escape hatch (`<leader><tab>R`) exists at the moment they might
  -- want it — same principle as round 6 (info at point of decision),
  -- reapplied to revert visibility.
  local prev_hint = ""
  if except then
    local prev = M.previous_name(except)
    if prev and prev ~= "" then
      prev_hint = ("  ·  was '%s' (<leader><tab>R reverts)"):format(prev)
    end
  end

  local has_ui = #vim.api.nvim_list_uis() > 0
  if not has_ui then
    -- Headless: keep the hint, drop the live preview. If a suggestion is
    -- available, surface it in the prompt text and treat empty submit as
    -- accept-suggestion (same mixed-initiative contract as the floating UI).
    local sug_hint = (opts.suggestion and opts.suggestion ~= "")
                       and (" [suggest: " .. opts.suggestion .. "]") or ""
    vim.ui.input({ prompt = prompt .. "[" .. taken_hint .. prev_hint .. "]" .. sug_hint .. " ", default = default },
      function(v)
        if (v == nil or v == "") and opts.suggestion and opts.suggestion ~= "" then
          v = opts.suggestion
        end
        callback(v)
      end)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  if default ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })
  end

  local width = math.min(60, vim.o.columns - 8)
  local ok_win, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative  = "editor",
    row       = math.floor(vim.o.lines / 2) - 1,
    col       = math.floor((vim.o.columns - width) / 2),
    width     = width,
    height    = 1,
    style     = "minimal",
    border    = "rounded",
    title     = " " .. prompt:gsub(":%s*$", "") .. "  ·  " .. taken_hint .. prev_hint .. " ",
    title_pos = "center",
  })
  if not ok_win then
    vim.ui.input({ prompt = prompt .. "[" .. taken_hint .. "] ", default = default },
      function(v) callback(v) end)
    return
  end

  local ns = vim.api.nvim_create_namespace("user_tabs_input_preview")
  -- Mixed-initiative ghost text (Horvitz 1999 "Principles of Mixed-Initiative
  -- User Interfaces"; modern lineage: Copilot inline 2021, Cursor 2023). When
  -- the buffer is empty AND a suggestion exists, render it as faded virt_text
  -- so the user sees the system's proposal *without* the input being pre-filled.
  -- Type → ghost disappears, replaced by the label preview for what you typed.
  -- <CR> on empty input → accepts the suggestion. System proposes, user disposes.
  local suggestion = opts.suggestion or ""
  local function refresh()
    local line = (vim.api.nvim_buf_get_lines(buf, 0, 1, false) or {})[1] or ""
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local virt
    if line == "" and suggestion ~= "" then
      -- Show the suggestion as ghost text + the label IT would yield.
      local lab = preview_label_for(suggestion, taken)
      virt = {
        { suggestion,                "Comment" },
        { ("   → [%s]"):format(lab), "BrandAccent" },
      }
    else
      local lab = preview_label_for(line, taken)
      virt = { { ("  → [%s]"):format(lab), "BrandAccent" } }
    end
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_text = virt,
      virt_text_pos = "eol",
    })
  end

  local finished = false
  local function finish(value)
    if finished then return end
    finished = true
    pcall(vim.api.nvim_win_close, win, true)
    callback(value)
  end

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = buf, callback = refresh,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf, once = true, callback = function() finish(nil) end,
  })
  -- <CR> in insert mode accepts; <Esc> cancels. Keep mappings buffer-local
  -- so they don't leak to other buffers if the prompt is interrupted oddly.
  -- Empty + suggestion = accept the suggestion (mixed-initiative dispose).
  local function accept()
    local line = (vim.api.nvim_buf_get_lines(buf, 0, 1, false) or {})[1] or ""
    if line == "" and suggestion ~= "" then line = suggestion end
    finish(line)
  end
  vim.keymap.set("i", "<CR>",  accept,                  { buffer = buf })
  vim.keymap.set("i", "<Esc>", function() finish(nil) end, { buffer = buf })
  vim.keymap.set("n", "<CR>",  accept,                  { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() finish(nil) end, { buffer = buf })

  vim.cmd("startinsert!")
  refresh()
end

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

  -- Semantic zoom / focus+context (Furnas 1986 "Generalized Fisheye Views";
  -- Sarkar & Brown 1992; Carpendale 2005 "A Framework of Distortion Viewing";
  -- modern: constraint-aware density). Estimate full-chip widths up front;
  -- if the sum exceeds the screen, switch non-priority chips to a compact
  -- form (just lead + `[label]`) so every tab keeps SOME presence rather
  -- than vim auto-scrolling and pushing chips off-screen. Active + MRU
  -- toggle target always render full — they're the user's two primary
  -- contexts and lose the most from compaction.
  local function full_width_estimate(i, name_str)
    -- Rough chip-only width: lead(2) + "N "(2) + "[x] "(4) + icon(2) + name + " "*2 + modified maybe + gap(2)
    return 2 + 2 + 4 + 2 + vim.fn.strdisplaywidth(name_str) + 4 + 2
  end
  local total_estimate = 0
  for i = 1, total do
    total_estimate = total_estimate + full_width_estimate(i, M.name_for(i))
  end
  -- Leave a small budget for bufferline / right padding.
  local compact_mode = total_estimate > (vim.o.columns - 8)

  local now = vim.uv.now()
  for i = 1, total do
    local tabid = vim.api.nvim_list_tabpages()[i]
    local is_active = (tabid == cur_tab)
    local is_toggle = (i == toggle_nr) and not is_active
    -- "Priority" chips always render full — focus+context principle: the
    -- chip you're on and the one you'd flip to keep maximum information
    -- density even when the rest compact.
    local is_priority = is_active or is_toggle
    -- Clean expired restored markers as we encounter them; lazy cleanup is
    -- fine because render() runs frequently and the table is tiny.
    if _restored_until[tabid] and now >= _restored_until[tabid] then
      _restored_until[tabid] = nil
    end
    local is_restored = _restored_until[tabid] ~= nil
    if is_restored then is_priority = true end  -- the flash deserves full chip
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

    -- "Just-restored" highlight wins over the active accent for the 1.5s
    -- it lives. The user just brought this tab back; the green tint
    -- confirms "yes, that one" in the region they're already looking at.
    local hl    = is_restored and "UserTabRestored"
                  or (is_active and "UserTabActive" or "UserTabInactive")
    local modhl = is_active and "UserTabModActive"   or "UserTabModInactive"

    -- left = jump · right = rename · middle = close
    local click_id = register_click(function(button)
      if button == "l" then
        pcall(vim.cmd, i .. "tabnext")
      elseif button == "r" then
        input_with_label_preview({
          prompt = "rename tab " .. i .. ": ",
          default = M.name_for(i),
          except_tabnr = i,
        }, function(v) if v then M.set_name(i, v) end end)
      elseif button == "m" then
        pcall(vim.cmd, i .. "tabclose")
      end
    end)

    -- The clickable region wraps the whole chip incl. modified glyph.
    -- Toggle target gets a ↶ glyph so you can SEE where <leader><tab><tab>
    -- will jump before you press it. The [letter] is the stable jump label
    -- — visible affordance for <M-j>{letter}, no recall required.
    --
    -- Lead glyph priority: restored (transient) > toggle target > active >
    -- inactive. Active uses `▌` (half-block, heavier) and inactive uses
    -- `▎` (thin bar) — same family of glyphs, weight difference redundantly
    -- encodes active state in addition to the accent background color.
    -- WCAG 1.4.1 "Use of Color" (W3C ongoing through WCAG 2.2, 2023):
    -- never let color alone carry state. ~8% of men have red-green color
    -- blindness; monochrome terminals and high-glare displays compress
    -- color distance further. Shape weight survives all of those.
    local lead
    if is_restored then lead = "↺"
    elseif is_toggle then lead = "↶"
    elseif is_active then lead = "▌"
    else                  lead = "▎" end
    -- During jump-by-label mode, every [x] chunk uses the prompt highlight
    -- (feedforward: the affordance reveals itself in-place). Out of mode,
    -- the active tab keeps its inverted label and others stay subtle.
    local label_hl
    if _label_mode then label_hl = "UserTabLabelPrompt"
    else label_hl = is_active and "UserTabLabelActive" or "UserTabLabel" end
    local chip_lead = (" %s%d "):format(lead, i)
    local chip_label = ("%%#%s#[%s]%%#%s# "):format(label_hl, labels[i] or "?", hl)
    local chip
    if compact_mode and not is_priority then
      -- Compact form: drop the icon, drop the name, keep lead + N + label.
      -- The `[label]` is the load-bearing affordance for <M-j>; everything
      -- else can recover via the picker if the user needs the full name.
      chip = chip_lead .. chip_label
      if modified then chip = chip .. "%#" .. modhl .. "#●" end
    else
      local chip_body = ("%s %s "):format(icon, label)
      chip = chip_lead .. chip_label .. chip_body
      if modified then
        chip = chip .. "%#" .. modhl .. "#●  "
      else
        chip = chip .. " "
      end
    end
    -- Pre-attentive error indicator: red ⚠N appended when the tab carries
    -- ≥1 ERROR-severity diagnostic. Color + shape double-encoded so the
    -- urgent chip pops from a row of normal-toned chips without conscious
    -- search (Treisman pre-attentive processing, ~200ms detection latency).
    -- Always rendered even in compact mode — urgency overrides density.
    local err = tab_error_count(tabid)
    if err > 0 then
      local err_hl = is_active and "UserTabErrorActive" or "UserTabError"
      chip = chip .. ("%%#%s#⚠%d  "):format(err_hl, err)
    end
    table.insert(out, ("%%%d@v:lua._user_tabs_on_click@%%#%s#%s%%X")
      :format(click_id, hl, chip))

    -- Inter-chip spacing. Proximity-as-relatedness (Tversky 2019 "Mind in
    -- Motion" reapplying Gestalt principles to modern spatial UIs): tabs
    -- sharing a cwd belong to the same workspace, so they cluster with the
    -- tight gap. A cwd transition gets a thin separator ` ╱ ` (or a wider
    -- gap in compact mode where ink density is constrained) so the eye
    -- groups projects automatically without having to parse names. When all
    -- tabs share one cwd the separator never appears — no ink for nothing.
    if i < total then
      local function tab_cwd(nr)
        local ok, c = pcall(vim.fn.getcwd, -1, nr)
        return ok and c or ""
      end
      local sep
      if tab_cwd(i) == tab_cwd(i + 1) then
        sep = "%#UserTabFill#  "                                -- same project
      else
        sep = compact_mode and "%#UserTabFill#    "             -- compact: wider gap
                            or "%#UserTabFill# ╱ "              -- full: thin divider
      end
      table.insert(out, sep)
    end
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

-- Wall-clock timestamp per tab id for temporal awareness in the picker
-- (Tversky 2019 "Mind in Motion": spatial layouts naturally encode time
-- when the temporal dimension is presented inline). Updated on every
-- mru_push so it stays in lockstep with "this tab just became current."
-- Using os.time() (epoch seconds) rather than uv.now() (process-monotonic
-- ms) means the value survives a recompute or restart's frame of reference.
local _last_visited_epoch = {}

local function mru_push(tabid)
  for i, id in ipairs(_mru) do
    if id == tabid then table.remove(_mru, i); break end
  end
  table.insert(_mru, 1, tabid)
  _last_visited_epoch[tabid] = os.time()
  while #_mru > MRU_MAX do table.remove(_mru) end
end

-- Human-readable idle label from a number of seconds. Calibrated for
-- glance-readable density in the picker: under 10s reads as live, under
-- a minute is precise, longer spans round to the next coarser unit.
local function idle_label(seconds)
  if not seconds or seconds < 10 then return "now" end
  if seconds < 60   then return ("%ds"):format(seconds) end
  if seconds < 3600 then return ("%dm"):format(math.floor(seconds / 60)) end
  if seconds < 86400 then return ("%dh"):format(math.floor(seconds / 3600)) end
  return ("%dd"):format(math.floor(seconds / 86400))
end

local function mru_prune_invalid()
  local valid = {}
  for _, id in ipairs(_mru) do
    if vim.api.nvim_tabpage_is_valid(id) then valid[#valid + 1] = id end
  end
  _mru = valid
end

-- Tracks the tabid we *left* most recently. TabClosed reads this to detect
-- "the user closed the current tab" (the leaving tabid is now invalid)
-- vs "the user closed a non-current tab" (leaving tabid is still valid).
-- The distinction matters because we only want to override vim's
-- auto-pick when the close was *of* the current tab.
local _leaving_tabid = nil

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

-- Shared one-shot prompt: enables _label_mode, reads one keystroke, restores.
-- Returns ("ok", char) for any normal keystroke, ("exit", nil) for esc/cr/empty.
-- Caller is responsible for redrawing the tabline AFTER mode flips off.
local function read_label_keystroke()
  pcall(vim.cmd, "redraw")
  local ok, ch = pcall(vim.fn.getcharstr)
  if not ok or ch == "" or ch == "\27" or ch == "\r" then
    return "exit"
  end
  return "ok", ch
end

local function dispatch_label(ch, labels)
  for nr, lab in pairs(labels) do
    if lab == ch or lab == ch:lower() then M.jump(nr); return true end
  end
  return false
end

function M.jump_by_label()
  if vim.fn.tabpagenr("$") <= 1 then
    brand.notify("only one tab open", vim.log.levels.INFO, { title = "tabs" })
    return
  end
  local labels = compute_labels()
  _label_mode = true
  pcall(vim.cmd, "redrawtabline")
  local status, ch = read_label_keystroke()
  _label_mode = false
  pcall(vim.cmd, "redrawtabline")
  if status == "exit" then return end
  if not dispatch_label(ch, labels) then
    brand.notify(("no tab labeled '%s'"):format(ch), vim.log.levels.WARN, { title = "tabs" })
  end
end

-- Sustained label-jump (`<M-J>` capital): mode stays active across multiple
-- jumps; each keystroke jumps, <Esc>/<CR> exits. Flow-preserving sustained
-- interaction (Hutchins/Hollan/Norman 1986 direct-manipulation; Csíkszent-
-- mihályi 1990 flow; modern: "sticky modes" in Cursor / Linear / VSCode
-- multi-cursor). GOMS (Card-Moran-Newell 1983) framing: amortize mode-entry
-- cost across the whole browse, so three jumps cost five keystrokes instead
-- of six, and one cognitive setup ("I'm scanning my tabs") covers them all.
--
-- _label_mode stays true continuously between jumps so the peach feedforward
-- highlight never flickers — the user sees a single sustained visual state
-- for the entire browse, exiting cleanly on Esc/CR.
function M.jump_by_label_sustained()
  if vim.fn.tabpagenr("$") <= 1 then
    brand.notify("only one tab open", vim.log.levels.INFO, { title = "tabs" })
    return
  end
  _label_mode = true
  pcall(vim.cmd, "redrawtabline")
  while true do
    -- Recompute labels each iteration in case a jump triggered some side
    -- effect that changed names (unlikely in practice, but cheap and safe).
    local labels = compute_labels()
    local status, ch = read_label_keystroke()
    if status == "exit" then break end
    if not dispatch_label(ch, labels) then
      brand.notify(("no tab labeled '%s' — exiting sustained mode"):format(ch),
                   vim.log.levels.WARN, { title = "tabs" })
      break  -- a miss likely means the user got lost; exit to recover
    end
    if vim.fn.tabpagenr("$") <= 1 then break end  -- defensive: lost all tabs
  end
  _label_mode = false
  pcall(vim.cmd, "redrawtabline")
end

-- Cheap shellout to read the short branch name for the given cwd. Returns
-- nil when git fails, when the cwd isn't a repo, or when the branch is the
-- default (main/master) — defaults are too generic to add signal to a tab
-- name, so we suppress them.
local function smart_branch(cwd)
  local out = vim.fn.systemlist({ "git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD" })
  if vim.v.shell_error ~= 0 then return nil end
  local branch = (out[1] or ""):gsub("%s+$", "")
  if branch == "" or branch == "HEAD" or branch == "main" or branch == "master" then
    return nil
  end
  -- feature/long-name → long-name (the leading namespace is rarely the
  -- signal the user wants on the chip).
  return branch:match("([^/]+)$") or branch
end

-- Mixed-initiative system proposal for `<leader><tab>N`'s prompt. Empty
-- string means "no useful suggestion, let the user type from scratch."
local function smart_default_name()
  local cwd = vim.fn.getcwd()
  local short = vim.fn.fnamemodify(cwd, ":t")
  if short == "" or cwd == vim.env.HOME then return "" end
  local branch = smart_branch(cwd)
  if branch then return ("%s · %s"):format(short, branch) end
  return short
end

function M.new_named()
  -- No except_tabnr — the new tab doesn't exist yet, so every current
  -- label is "in use" from its perspective. Preview reflects the *next*
  -- label this name will receive.
  --
  -- suggestion is the system's mixed-initiative proposal (cwd + branch
  -- when on a feature branch; else cwd:t). User sees it as ghost text;
  -- <CR> on empty accepts it, typing overrides.
  input_with_label_preview({
    prompt     = "name new tab: ",
    suggestion = smart_default_name(),
  }, function(name)
    vim.cmd("tabnew")
    if name and name ~= "" then M.set_name(vim.fn.tabpagenr(), name) end
  end)
end

function M.close_others()
  local total = vim.fn.tabpagenr("$")
  if total <= 1 then return end
  -- Reversibility-over-confirmation (Gmail Undo Send 2009, Material snackbar
  -- 2014, Tognazzini's First Principles ongoing): when recovery is one
  -- keystroke and *visible at the moment of action*, pre-confirming
  -- destructive ops is wasted friction. The previous version of this
  -- function gated on a vim.fn.confirm modal — that interrupts the common
  -- case where the user meant it. Now we just do it and surface
  -- `<leader><tab>U` (batch undo) in the same notify that confirms
  -- completion. The action and its escape hatch live in one beat.
  vim.cmd("tabonly")
  brand.notify(
    ("closed %d other tab%s · `<leader><tab>U` to restore all"):format(
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
  -- just closed. Push onto the stack with a wall-clock timestamp so
  -- undo_close_batch() can group restores by "this was one user operation."
  -- (Could be more than one in a single tick if `:tabonly` etc. kills many.)
  local now = vim.uv.now()
  for tabid, snap in pairs(_tab_snapshots) do
    if not vim.api.nvim_tabpage_is_valid(tabid) then
      snap.closed_at_ms = now
      snap.closed_at_epoch = os.time()  -- wall-clock for cross-session display
      table.insert(_closed_stack, 1, snap)
      _tab_snapshots[tabid] = nil
      while #_closed_stack > CLOSED_MAX do table.remove(_closed_stack) end
    end
  end
end

-- ─── persistent undo stack (cognitive offloading) ────────────────────────
-- Cognitive offloading (Risko & Gilbert 2016, Trends in Cognitive Sciences;
-- foundational: Clark & Chalmers 1998 "The Extended Mind") only works when
-- the externalization is *trustworthy*. An undo stack that evaporates on
-- nvim restart forces the user to keep tabs in their own head defensively
-- — they can't actually offload "what tabs did I close earlier today" to
-- the tool. Persisting the stack to disk closes that trust gap.
--
-- Save is debounced (100ms) on TabClosed and flushed synchronously on
-- VimLeavePre. Load filters out entries whose files no longer exist —
-- restoring "I closed tab X yesterday" only works if X's files still do.
local _save_timer

local function save_closed_stack()
  vim.fn.mkdir(vim.fn.fnamemodify(UNDO_FILE, ":h"), "p")
  local f = io.open(UNDO_FILE, "w")
  if f then f:write(vim.json.encode(_closed_stack)); f:close() end
end

local function save_closed_stack_debounced()
  if _save_timer then pcall(function() _save_timer:stop(); _save_timer:close() end) end
  _save_timer = vim.uv.new_timer()
  _save_timer:start(100, 0, vim.schedule_wrap(function()
    pcall(save_closed_stack)
    if _save_timer then pcall(function() _save_timer:close() end); _save_timer = nil end
  end))
end

local function load_closed_stack()
  -- Idempotent — setup() can be called more than once (lazy.nvim eagerly
  -- loads the user-modules spec, then a manual :luafile or test harness
  -- might re-require). Clearing first prevents double-loading the same
  -- entries from disk into memory.
  _closed_stack = {}
  local f = io.open(UNDO_FILE, "r"); if not f then return end
  local raw = f:read("*a"); f:close()
  local ok, parsed = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  if not (ok and type(parsed) == "table") then return end
  for _, snap in ipairs(parsed) do
    -- Drop file entries whose paths vanished between sessions. If everything
    -- in a snapshot is gone, skip the snapshot entirely — restoring an empty
    -- tab would be confusing.
    local live_files = {}
    for _, fe in ipairs(snap.files or {}) do
      if fe.path and vim.uv.fs_stat(fe.path) then
        live_files[#live_files + 1] = fe
      end
    end
    if #live_files > 0 then
      snap.files = live_files
      _closed_stack[#_closed_stack + 1] = snap
    end
  end
  while #_closed_stack > CLOSED_MAX do table.remove(_closed_stack) end
end

-- Replay one snapshot into a fresh tab. Shared by undo_close, batch undo,
-- and the picker's ghost-row restore. Keeping the replay logic in one
-- place means every recovery path produces visually-identical results
-- (Nielsen #4 consistency across paths). Also marks the new tab as
-- "just-restored" so the tabline flashes ↺ for 1.5s — in-place feedback
-- replaces the floating notify the caller used to fire.
local function restore_snapshot(snap)
  if not (snap and snap.files and snap.files[1]) then return end
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
  mark_restored(vim.api.nvim_get_current_tabpage())
end

function M.undo_close()
  local snap = table.remove(_closed_stack, 1)
  if not snap then
    -- No visual change occurs on the failure path, so we DO need the notify
    -- here (Nielsen #1 visibility of status). Success path skips notify
    -- because the in-place ↺ flash in the tabline IS the feedback.
    brand.notify("no closed tabs to restore", vim.log.levels.INFO, { title = "tabs" })
    return
  end
  restore_snapshot(snap)
  pcall(save_closed_stack_debounced)
  pcall(vim.cmd, "redrawstatus")
end

-- Batch undo: restore everything that landed on the stack as part of the
-- *same user operation*. Defined as "any snapshot harvested within the
-- last 500ms of the most-recent one" — close_others, :tabonly, and rapid
-- `tabclose; tabclose` all land inside that window; a tab closed an hour
-- ago wouldn't be sucked in by a fresh batch undo.
--
-- This is the core of the reversibility-over-confirmation pattern (Gmail
-- Undo Send 2009, Material snackbar 2014): the destructive action commits
-- immediately, with a one-keystroke recovery path published right next to
-- the confirmation notify. No modal prompt, no decision fatigue at commit.
function M.undo_close_batch()
  if #_closed_stack == 0 then
    brand.notify("nothing to restore", vim.log.levels.INFO, { title = "tabs" })
    return
  end
  local newest = _closed_stack[1].closed_at_ms or 0
  local cutoff = newest - 500
  local batch = {}
  while _closed_stack[1] and (_closed_stack[1].closed_at_ms or 0) >= cutoff do
    table.insert(batch, table.remove(_closed_stack, 1))
  end
  -- Restore in reverse so the visually-leftmost batch entry ends up leftmost
  -- in the tabline (matches the order they were closed in, roughly). Each
  -- restored chip flashes ↺ for 1.5s in the tabline — three chips flashing
  -- at once is the in-place equivalent of "restored 3 tabs", visible in the
  -- region the user is already scanning. No floating notify needed.
  for i = #batch, 1, -1 do restore_snapshot(batch[i]) end
  pcall(save_closed_stack_debounced)
  pcall(vim.cmd, "redrawstatus")
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
    local lv = _last_visited_epoch[tabid]
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
      idle_s    = lv and (os.time() - lv) or nil,
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
    -- `↺` glyph + "(closed Xm ago)" signals "this isn't a live tab, but
    -- selecting it brings it back" — and the timestamp lets the user pick
    -- between several closed candidates by recency.
    local when_part = ""
    if t.closed_at_epoch then
      local lbl = idle_label(os.time() - t.closed_at_epoch)
      -- "closed now ago" reads as nonsense; switch to "just now" at the
      -- low-resolution end of the scale.
      when_part = (lbl == "now") and " just now" or (" " .. lbl .. " ago")
    end
    return ("  ↺   %s  (closed%s · %d file%s)"):format(
      t.name, when_part, #t.files, #t.files == 1 and "" or "s")
  end
  local mark = t.current and "▎" or (t.mru_rank == 2 and "↶" or " ")
  local mod  = t.modified and "●" or " "
  -- Temporal awareness (Tversky 2019 "Mind in Motion"; modern temporal
  -- info-vis): show idle time inline so picker rows carry both the spatial
  -- (MRU ordering) and temporal (how stale) dimensions in one glance.
  -- Current tab reads "now"; rest read "5m" / "2h" / "1d".
  local when = t.current and "now" or idle_label(t.idle_s)
  return ("%s %d [%s] %s %-4s %s  (%d win%s)"):format(
    mark, t.nr, t.label or "?", mod, when, t.name, t.win_count, t.win_count == 1 and "" or "s")
end

-- Expose closed-tab snapshots as picker entries. Tagged with `ghost = true`
-- so fmt_item / actions can branch on liveness.
local function ghost_entries()
  local out = {}
  for i, snap in ipairs(_closed_stack) do
    out[#out + 1] = {
      ghost            = true,
      stack_idx        = i,
      name             = snap.name or vim.fn.fnamemodify(snap.cwd or "", ":t"),
      files            = snap.files or {},
      cwd              = snap.cwd or "",
      closed_at_epoch  = snap.closed_at_epoch,
    }
  end
  return out
end

local function restore_ghost(g)
  -- Pop the specific stack entry (not necessarily the top), then delegate
  -- to the shared replay helper. The ↺ flash in the tabline replaces the
  -- floating notify — consistent with undo_close / batch undo paths.
  if not (g and g.stack_idx) then return end
  local snap = table.remove(_closed_stack, g.stack_idx)
  if not snap then return end
  restore_snapshot(snap)
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
        input_with_label_preview({
          prompt = ("rename tab %d: "):format(nr),
          default = M.name_for(nr),
          except_tabnr = nr,
        }, function(v)
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
  load_closed_stack()
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
  -- Track the tab being left so TabClosed can tell "user closed current"
  -- (the leaving tabid becomes invalid) from "user closed a non-current
  -- tab" (the leaving tabid stays valid). Only the former case justifies
  -- overriding vim's auto-pick with MRU-restore.
  vim.api.nvim_create_autocmd("TabLeave", {
    group = grp,
    callback = function() _leaving_tabid = vim.api.nvim_get_current_tabpage() end,
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
      pcall(save_closed_stack_debounced)
      -- Nudge the statusline so the ambient ↺N chip appears the instant
      -- this close adds an entry to the recovery stack — no waiting for
      -- lualine's polling cycle to catch up.
      pcall(vim.cmd, "redrawstatus")

      -- Spatial Context Preservation (Czerwinski et al. 2004 "A Diary Study
      -- of Task Switching and Interruption", CHI; Norman 1983 mental models;
      -- de facto since Chrome 2008): closing a tab is one deliberate context
      -- shift. Vim's default behavior — auto-pick the spatially adjacent
      -- tab — adds a second, *unintended* shift. Instead, return the user
      -- to their MRU-previous tab. That's the workspace they were in before
      -- they made the side trip into the now-closed tab.
      if _leaving_tabid and not vim.api.nvim_tabpage_is_valid(_leaving_tabid) then
        mru_prune_invalid()
        -- TabEnter for vim's auto-pick fires *after* TabClosed, so the
        -- new-current tabid hasn't been pushed onto _mru yet at this point.
        -- After pruning out the just-closed tabid, _mru[1] is the user's
        -- actual previous tab — exactly the context they want returned to.
        local current = vim.api.nvim_get_current_tabpage()
        local target = _mru[1]
        if target and vim.api.nvim_tabpage_is_valid(target) and target ~= current then
          pcall(vim.api.nvim_set_current_tabpage, target)
        end
      end
      _leaving_tabid = nil

      -- Reap names of any tabpage id that no longer exists. Tabid-keyed
      -- naming makes :tabmove "just work", and this loop cleans up after
      -- :tabclose so the persistent state file doesn't grow unbounded.
      for id in pairs(_id_to_name) do
        if not vim.api.nvim_tabpage_is_valid(id) then
          _id_to_name[id] = nil
        end
      end
      pcall(reap_prev_names)
      pcall(save_state)
    end,
  })
  -- Flush the debounced save synchronously on exit — without this, an
  -- nvim quit within 100ms of a tab close drops the latest entry.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = grp, callback = function() pcall(save_closed_stack) end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = grp, callback = apply_hl })
  -- Invalidate the per-tab ERROR-count cache when diagnostics shift, and
  -- nudge the tabline so the pre-attentive ⚠N glyph appears/disappears
  -- without waiting for the next render trigger.
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = grp,
    callback = function() _err_count_cache = {}; pcall(vim.cmd, "redrawtabline") end,
  })

  vim.api.nvim_create_user_command("TabName", function(a)
    M.set_name(nil, a.args ~= "" and a.args or nil)
  end, { nargs = "?", desc = "Set current tab name (no args clears the custom name)" })

  vim.api.nvim_create_user_command("TabRename", function()
    local nr = vim.fn.tabpagenr()
    input_with_label_preview({
      prompt = "tab name: ",
      default = M.name_for(nr),
      except_tabnr = nr,
    }, function(v) if v then M.set_name(nr, v) end end)
  end, { desc = "Rename current tab interactively" })

  vim.api.nvim_create_user_command("TabRenameAuto", function()
    M.set_name(nil, nil)
  end, { desc = "Clear the custom name (revert to auto-derived)" })

  vim.api.nvim_create_user_command("TabRenameRevert", function() M.revert_rename() end,
    { desc = "Swap current and previous custom name (one-deep rename undo)" })

  vim.api.nvim_create_user_command("TabNewNamed", M.new_named,
    { desc = "Create a new tab and prompt for its name" })
  vim.api.nvim_create_user_command("TabPick", M.pick,
    { desc = "Pick a tab by name (telescope/select)" })
  vim.api.nvim_create_user_command("TabPickClose", M.pick_close,
    { desc = "Pick a tab to close (telescope/select)" })
  vim.api.nvim_create_user_command("TabUndoClose", M.undo_close,
    { desc = "Reopen the most recently closed tab (up to 10 deep)" })
  vim.api.nvim_create_user_command("TabUndoCloseBatch", M.undo_close_batch,
    { desc = "Reopen every tab closed in the last user operation (e.g. :tabonly)" })
  vim.api.nvim_create_user_command("TabCloseOthers", M.close_others,
    { desc = "Close every tab except the current one" })
  vim.api.nvim_create_user_command("TabLast", M.jump_last,
    { desc = "Jump to the most recently used tab (toggle)" })
  vim.api.nvim_create_user_command("TabJumpLabel", M.jump_by_label,
    { desc = "Prompt for a tab letter label and jump (stable across reorder)" })
  vim.api.nvim_create_user_command("TabJumpLabelSustained", M.jump_by_label_sustained,
    { desc = "Sustained label-jump mode: each keystroke jumps until <Esc>/<CR>" })
  vim.api.nvim_create_user_command("TabMoveLeft", function() M.move("left") end,
    { desc = "Move current tab one position left" })
  vim.api.nvim_create_user_command("TabMoveRight", function() M.move("right") end,
    { desc = "Move current tab one position right" })
end

return M
