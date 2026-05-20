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
  local out = { " " }

  for i = 1, total do
    local tabid = vim.api.nvim_list_tabpages()[i]
    local is_active = (tabid == cur_tab)
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

    -- The clickable region wraps the whole chip incl. modified glyph
    local chip = (" ▎%d %s %s "):format(i, icon, label)
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

-- ─── commands + setup ────────────────────────────────────────────────────
function M.setup()
  load_state()
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
end

return M
