-- Per-filetype adaptive layouts. Each "profile" runs a one-time setup when
-- you first land in that filetype during a session, and (optionally) a
-- teardown when you leave. Profiles are opt-in per ft to avoid surprises
-- — toggle with :ProfileToggle <ft>. Enabled set persists.
local M = {}

local brand = require("user.brand")

local STATE_FILE = vim.fn.stdpath("state") .. "/profiles.json"
local _enabled  = {}            -- { [ft] = true }
local _applied  = {}            -- { [ft] = true } (cleared on profile disable)

local function load_state()
  local f = io.open(STATE_FILE, "r"); if not f then return end
  local ok, p = pcall(vim.json.decode, f:read("*a"), { luanil = { object = true, array = true } })
  f:close()
  if ok and type(p) == "table" then _enabled = p.enabled or {} end
end

local function save_state()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  local f = io.open(STATE_FILE, "w")
  if f then f:write(vim.json.encode({ enabled = _enabled })); f:close() end
end

-- ─── profile registry ────────────────────────────────────────────────────
-- Each profile: { setup = function(ctx), teardown = function(ctx) }
-- The functions get a small ctx table with the triggering bufnr.
M._profiles = {

  markdown = {
    label = "auto-preview + outline",
    setup = function()
      -- Open MarkdownPreview if the plugin is installed
      if vim.fn.exists(":MarkdownPreviewToggle") > 0 then
        pcall(vim.cmd, "MarkdownPreviewToggle")
      end
    end,
  },

  http = {
    label = "open kulala output dock",
    setup = function()
      pcall(function() require("user.dock").open("output") end)
    end,
  },
  rest = {
    label = "open kulala output dock",
    setup = function()
      pcall(function() require("user.dock").open("output") end)
    end,
  },

  python = {
    label = "open neotest panel for *_test.py / test_*.py",
    setup = function()
      local name = vim.api.nvim_buf_get_name(0)
      local base = vim.fn.fnamemodify(name, ":t")
      if base:match("_test%.py$") or base:match("^test_") then
        pcall(vim.cmd, "Neotest summary open")
      end
    end,
  },

  go = {
    label = "open neotest panel for *_test.go",
    setup = function()
      local name = vim.api.nvim_buf_get_name(0)
      if vim.fn.fnamemodify(name, ":t"):match("_test%.go$") then
        pcall(vim.cmd, "Neotest summary open")
      end
    end,
  },

  sql = {
    label = "open dbui",
    setup = function() pcall(vim.cmd, "DBUIToggle") end,
  },

  gitcommit = {
    label = "open diff in a split for context",
    setup = function() pcall(vim.cmd, "vert Git diff --cached") end,
  },
}

-- ─── apply / unapply ─────────────────────────────────────────────────────
local function _apply(ft)
  local prof = M._profiles[ft]; if not prof then return end
  if _applied[ft] then return end
  _applied[ft] = true
  pcall(prof.setup, { buf = vim.api.nvim_get_current_buf() })
end

local function _maybe_apply()
  local ft = vim.bo.filetype
  if ft == "" then return end
  if not _enabled[ft] then return end
  _apply(ft)
end

-- ─── commands ────────────────────────────────────────────────────────────
function M.toggle(ft)
  ft = ft and ft ~= "" and ft or vim.bo.filetype
  if not M._profiles[ft] then
    brand.notify("no profile defined for · " .. ft, vim.log.levels.WARN, { title = "profiles" })
    return
  end
  _enabled[ft] = not _enabled[ft] and true or nil
  _applied[ft] = nil   -- next BufEnter will (re)apply
  save_state()
  brand.notify(("profile %s · %s"):format(_enabled[ft] and "ON" or "OFF", ft),
    nil, { title = "profiles" })
  if _enabled[ft] and vim.bo.filetype == ft then _apply(ft) end
end

function M.list()
  local lines = { "profiles:" }
  for ft, prof in pairs(M._profiles) do
    table.insert(lines, ("  [%s] %-12s  %s")
      :format(_enabled[ft] and "x" or " ", ft, prof.label))
  end
  table.sort(lines, function(a, b) return a < b end)
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "profiles" })
end

-- ─── setup ───────────────────────────────────────────────────────────────
function M.setup()
  load_state()
  local grp = vim.api.nvim_create_augroup("user_profiles", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufEnter" },
    { group = grp, callback = _maybe_apply })

  vim.api.nvim_create_user_command("ProfileToggle",
    function(a) M.toggle(a.args ~= "" and a.args or nil) end,
    { nargs = "?",
      complete = function() return vim.tbl_keys(M._profiles) end,
      desc = "Toggle the auto-layout profile for a filetype" })

  vim.api.nvim_create_user_command("ProfileList", M.list,
    { desc = "Show all profiles and their enabled state" })
end

return M
