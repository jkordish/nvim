-- Iconography shim. One module, one API — every surface that needs a glyph
-- pulls it from here so we can retheme everything at once.
--
-- Backends (in preference order):
--   1. mini.icons  (newer, richer category coverage)
--   2. nvim-web-devicons (filetype/extension lookups)
--   3. hard-coded fallbacks (so headless / icon-less terminals still work)
--
-- All getters return { icon = "x", color = "#hex" } so callers can either
-- ignore the color or apply it to their own highlight.
local M = {}

local _mini, _devi
local function backends()
  if _mini == nil then _mini = pcall(require, "mini.icons") and require("mini.icons") or false end
  if _devi == nil then _devi = pcall(require, "nvim-web-devicons") and require("nvim-web-devicons") or false end
  return _mini, _devi
end

-- ─── filetype / filename ─────────────────────────────────────────────────
-- Pass a filename or a filetype string. Tries filename first (extension is
-- a better signal than ft), falls back to ft.
function M.ft(name, ft)
  local mini, devi = backends()
  if mini then
    local kind = (name and name:match("%.[^%./]+$")) and "file" or "filetype"
    local ok, icon, hl = pcall(mini.get, kind, name or ft or "")
    if ok and icon and icon ~= "" then
      local color = nil
      if hl then
        local h = vim.api.nvim_get_hl(0, { name = hl, link = false })
        if h and h.fg then color = ("#%06x"):format(h.fg) end
      end
      return { icon = icon, color = color }
    end
  end
  if devi then
    local icon, color
    if name and name ~= "" then
      icon, color = devi.get_icon_color(name, name:match("%.([^%.]+)$"), { default = true })
    end
    if (not icon) and ft and ft ~= "" then
      icon, color = devi.get_icon_color_by_filetype(ft, { default = true })
    end
    if icon then return { icon = icon, color = color } end
  end
  return { icon = "" }   -- empty document glyph
end

-- ─── jira issue type ─────────────────────────────────────────────────────
-- Atlassian's stock types + their close cousins. Comparison is lower-case
-- substring so "Story · UI", "User Story", etc. all match.
local ISSUE_TYPE = {
  { match = "bug",       icon = "󰃤", color = "#f38ba8" },
  { match = "story",     icon = "󰋽", color = "#a6e3a1" },
  { match = "epic",      icon = "󱓞", color = "#cba6f7" },
  { match = "sub",       icon = "󰘬", color = "#bac2de" },   -- sub-task / subtask
  { match = "spike",     icon = "",  color = "#f9e2af" },
  { match = "task",      icon = "",  color = "#89b4fa" },
  { match = "incident",  icon = "",  color = "#f38ba8" },
  { match = "feature",   icon = "",  color = "#a6e3a1" },
  { match = "improve",   icon = "",  color = "#fab387" },
  { match = "support",   icon = "󰋖",  color = "#89dceb" },
}
function M.issuetype(name)
  local n = (name or ""):lower()
  for _, e in ipairs(ISSUE_TYPE) do
    if n:find(e.match, 1, true) then return { icon = e.icon, color = e.color } end
  end
  return { icon = "", color = "#bac2de" }
end

-- ─── jira priority ───────────────────────────────────────────────────────
local PRIORITY = {
  highest = { icon = "", color = "#f38ba8" },   -- double up arrow
  high    = { icon = "", color = "#fab387" },
  medium  = { icon = "", color = "#f9e2af" },
  low     = { icon = "", color = "#89dceb" },
  lowest  = { icon = "", color = "#74c7ec" },
}
function M.priority(name)
  local n = (name or ""):lower():gsub("%s+", "")
  return PRIORITY[n] or { icon = "·", color = "#7f849c" }
end

-- ─── confluence page kind ────────────────────────────────────────────────
local PAGE = {
  page       = { icon = "󰈙", color = "#89b4fa" },
  blogpost   = { icon = "󰂭", color = "#cba6f7" },
  attachment = { icon = "",  color = "#bac2de" },
  comment    = { icon = "󰍩", color = "#94e2d5" },
}
function M.page_type(kind)
  return PAGE[(kind or "page"):lower()] or PAGE.page
end

-- ─── suggest action categories ───────────────────────────────────────────
-- Each suggest action declares a `cat` (optional); we map to a glyph.
local CAT = {
  git      = { icon = "", color = "#fab387" },
  ai       = { icon = "✦", color = "#cba6f7" },
  file     = { icon = "", color = "#89b4fa" },
  search   = { icon = "", color = "#f9e2af" },
  lsp      = { icon = "",  color = "#a6e3a1" },
  repl     = { icon = "", color = "#74c7ec" },
  jira     = { icon = "",  color = "#74c7ec" },
  confluence = { icon = "󰈙", color = "#89b4fa" },
  test     = { icon = "󰙨", color = "#a6e3a1" },
  diag     = { icon = "", color = "#f38ba8" },
  shell    = { icon = "",  color = "#89dceb" },
  workspace= { icon = "󱂬", color = "#cba6f7" },
  journal  = { icon = "",  color = "#fab387" },
  macro    = { icon = "",  color = "#f5c2e7" },
  task     = { icon = "",  color = "#74c7ec" },
  default  = { icon = "◆", color = "#cba6f7" },
}
function M.cat(name)
  return CAT[(name or "default"):lower()] or CAT.default
end

return M
