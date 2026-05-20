-- Persistent named macro library. Record a macro into a register, give it a
-- name, save to disk. Recall any macro by name later via picker.
--   :MacroSave <name> <register>  — e.g. :MacroSave format-row q
--   :Macro                         — picker over saved macros
--   :MacroRun <name>               — fire directly
local M = {}

local STORE = vim.fn.stdpath("state") .. "/macros.json"
local macros = {}

local function load()
  local f = io.open(STORE, "r")
  if not f then return end
  local data = f:read("*a"); f:close()
  local ok, parsed = pcall(vim.json.decode, data)
  if ok and type(parsed) == "table" then macros = parsed end
end

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(STORE, ":h"), "p")
  local f = io.open(STORE, "w")
  if f then f:write(vim.json.encode(macros)); f:close() end
end

function M.save_macro(name, reg)
  reg = (reg or "q"):sub(1, 1)
  local content = vim.fn.getreg(reg)
  if content == nil or content == "" then
    vim.notify("Macro register '" .. reg .. "' is empty", vim.log.levels.WARN); return
  end
  macros[name] = { content = content, saved_at = os.time(), reg = reg }
  save()
  vim.notify(("Macro '%s' saved (%d keystrokes)"):format(name, #content))
end

function M.run(name)
  local m = macros[name]
  if not m then vim.notify("No macro named '" .. name .. "'", vim.log.levels.WARN); return end
  -- Use feedkeys with 'x' mode so it runs synchronously like @q
  vim.fn.setreg("z", m.content)
  vim.cmd("normal! @z")
end

function M.delete(name)
  if macros[name] then macros[name] = nil; save(); vim.notify("Deleted macro '" .. name .. "'") end
end

function M.pick()
  local names = vim.tbl_keys(macros)
  if #names == 0 then vim.notify("No saved macros"); return end
  table.sort(names)
  vim.ui.select(names, {
    prompt = "Macros",
    format_item = function(n)
      local m = macros[n]
      local preview = m.content:gsub("[%c]", "·"):sub(1, 50)
      local age_d = math.floor((os.time() - m.saved_at) / 86400)
      return string.format("%-25s  %3dd ago  %s", n, age_d, preview)
    end,
  }, function(choice)
    if choice then M.run(choice) end
  end)
end

function M.setup()
  load()
  vim.api.nvim_create_user_command("MacroSave", function(args)
    local name, reg = args.args:match("^(%S+)%s*(%S?)")
    if not name then vim.notify("Usage: :MacroSave <name> [register=q]"); return end
    M.save_macro(name, reg ~= "" and reg or "q")
  end, { nargs = "+", desc = "Save current macro to named library" })

  vim.api.nvim_create_user_command("Macro", M.pick, { desc = "Pick + run a saved macro" })
  vim.api.nvim_create_user_command("MacroRun", function(args) M.run(args.args) end, {
    nargs = 1, desc = "Run a saved macro by name",
    complete = function() return vim.tbl_keys(macros) end,
  })
  vim.api.nvim_create_user_command("MacroDelete", function(args) M.delete(args.args) end, {
    nargs = 1, desc = "Delete a saved macro",
    complete = function() return vim.tbl_keys(macros) end,
  })
end

return M
