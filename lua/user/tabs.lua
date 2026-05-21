-- Named tabs + brand-styled tabline. Tabs become a first-class concept:
-- each one has an editable label (defaults to cwd:t), shows a modified
-- indicator, and is click-jumpable. Composes bufferline's output after
-- the tab chips so buffer-switching affordance is preserved.
local M = {}

local brand = require("user.brand")
local icons = require("user.icons")

-- ─── persistent label store ──────────────────────────────────────────────
local STATE_FILE = vim.fn.stdpath("state") .. "/tab_names.json"
local _names = {}   -- ["1"] = "frontend", ["2"] = "api", ... keyed by tabnr

local function load_state()
  local f = io.open(STATE_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a"), { luanil = { object = true, array = true } })
  f:close()
  if ok and type(parsed) == "table" then _names = parsed end
end

local function save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  local f = io.open(STATE_FILE, "w")
  if f then f:write(vim.json.encode(_names)); f:close() end
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
  local custom = _names[tostring(tabnr)]
  if custom and custom ~= "" then return custom end
  return auto_name(tabnr)
end

function M.set_name(tabnr, name)
  tabnr = tabnr or vim.fn.tabpagenr()
  if not name or name == "" then
    _names[tostring(tabnr)] = nil
  else
    _names[tostring(tabnr)] = name
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
    -- will jump before you press it.
    local lead = is_toggle and "↶" or "▎"
    local chip = (" %s%d %s %s "):format(lead, i, icon, label)
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

function M.new_named()
  vim.ui.input({ prompt = "name new tab: " }, function(name)
    vim.cmd("tabnew")
    if name and name ~= "" then M.set_name(vim.fn.tabpagenr(), name) end
  end)
end

function M.close_others()
  local total = vim.fn.tabpagenr("$")
  if total <= 1 then return end
  vim.cmd("tabonly")
  brand.notify(("closed " .. (total - 1) .. " other tab" .. (total - 1 == 1 and "" or "s")),
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

-- Snapshot + picker. Telescope when available, vim.ui.select as fallback.
-- Sorted by MRU (most recent first) — when you have 5+ tabs, the next one
-- you want is almost always the one you were just on, not tab 1.
local function snapshot()
  local items = {}
  local cur = vim.api.nvim_get_current_tabpage()
  for i = 1, vim.fn.tabpagenr("$") do
    local tabid = vim.api.nvim_list_tabpages()[i]
    local wins  = vim.api.nvim_tabpage_list_wins(tabid)
    local modified = false
    for _, w in ipairs(wins) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].modified then modified = true; break end
    end
    items[#items + 1] = {
      nr        = i,
      tabid     = tabid,
      name      = M.name_for(i),
      win_count = #wins,
      modified  = modified,
      current   = (tabid == cur),
      mru_rank  = mru_rank(tabid),
    }
  end
  table.sort(items, function(a, b) return a.mru_rank < b.mru_rank end)
  return items
end

local function fmt_item(t)
  local mark = t.current and "▎" or (t.mru_rank == 2 and "↶" or " ")
  local mod  = t.modified and "●" or " "
  return ("%s %d %s %s  (%d win%s)"):format(
    mark, t.nr, mod, t.name, t.win_count, t.win_count == 1 and "" or "s")
end

-- Open the picker. `mode` is "jump" (default) or "close" — only changes the
-- prompt title and the default action. Inline `<C-r>` rename and `<C-x>`
-- close work in either mode so you can do everything from one panel.
local function open_picker(mode)
  local items = snapshot()
  if #items <= 1 then
    brand.notify("only one tab open", vim.log.levels.INFO, { title = "tabs" })
    return
  end

  local ok_tel, telescope_pickers = pcall(require, "telescope.pickers")
  if not ok_tel then
    vim.ui.select(items, { prompt = mode == "close" and "close a tab" or "pick a tab",
                           format_item = fmt_item },
      function(t)
        if not t then return end
        if mode == "close" then pcall(vim.cmd, t.nr .. "tabclose")
        else M.jump(t.nr) end
      end)
    return
  end

  local finders   = require("telescope.finders")
  local conf      = require("telescope.config").values
  local actions   = require("telescope.actions")
  local action_st = require("telescope.actions.state")

  local function refresh(prompt_bufnr)
    local picker = action_st.get_current_picker(prompt_bufnr)
    picker:refresh(finders.new_table({
      results = snapshot(),
      entry_maker = function(t)
        return { value = t, display = fmt_item(t), ordinal = t.nr .. " " .. t.name }
      end,
    }), { reset_prompt = false })
  end

  telescope_pickers.new({}, {
    prompt_title = mode == "close" and "tabs · close" or "tabs · jump",
    finder = finders.new_table({
      results = items,
      entry_maker = function(t)
        return { value = t, display = fmt_item(t), ordinal = t.nr .. " " .. t.name }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local sel = action_st.get_selected_entry()
        actions.close(prompt_bufnr)
        if not (sel and sel.value) then return end
        if mode == "close" then pcall(vim.cmd, sel.value.nr .. "tabclose")
        else M.jump(sel.value.nr) end
      end)
      -- <C-r>: rename the highlighted tab without leaving the picker
      local function rename_action()
        local sel = action_st.get_selected_entry()
        if not (sel and sel.value) then return end
        local nr = sel.value.nr
        vim.ui.input({ prompt = ("rename tab %d: "):format(nr), default = M.name_for(nr) },
          function(v)
            if v then M.set_name(nr, v); refresh(prompt_bufnr) end
          end)
      end
      map("i", "<C-r>", rename_action)
      map("n", "<C-r>", rename_action)
      -- <C-x>: close the highlighted tab and stay in the picker
      local function close_action()
        local sel = action_st.get_selected_entry()
        if not (sel and sel.value) then return end
        pcall(vim.cmd, sel.value.nr .. "tabclose")
        if vim.fn.tabpagenr("$") <= 1 then actions.close(prompt_bufnr)
        else refresh(prompt_bufnr) end
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
  vim.opt.showtabline = 2
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
  vim.api.nvim_create_autocmd("TabClosed", {
    group = grp,
    callback = function(args)
      -- Renumber: when tab N closes, tabs > N shift down. Our keying is by
      -- number, so we rebuild the map. args.file is the tabnr that closed.
      local closed = tonumber(args.file)
      if not closed then return end
      local out = {}
      for k, v in pairs(_names) do
        local nr = tonumber(k)
        if nr and nr < closed then out[k] = v
        elseif nr and nr > closed then out[tostring(nr - 1)] = v
        end
      end
      _names = out; save_state()
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
  vim.api.nvim_create_user_command("TabCloseOthers", M.close_others,
    { desc = "Close every tab except the current one" })
  vim.api.nvim_create_user_command("TabLast", M.jump_last,
    { desc = "Jump to the most recently used tab (toggle)" })
  vim.api.nvim_create_user_command("TabMoveLeft", function() M.move("left") end,
    { desc = "Move current tab one position left" })
  vim.api.nvim_create_user_command("TabMoveRight", function() M.move("right") end,
    { desc = "Move current tab one position right" })
end

return M
