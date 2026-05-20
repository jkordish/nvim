-- Play: a single entry point for the novelty modules. Nothing in this
-- namespace is loaded eagerly — each toy boots only when you `:Play <name>`.
-- This keeps them out of the daily mental surface.
local M = {}

-- catalog: name -> { description, run = function(mod) ... end }
M.toys = {
  aurora     = { desc = "shifting-hue gradient float",         run = function(m) m.toggle() end },
  matrix     = { desc = "katakana rain side column",            run = function(m) m.toggle() end },
  tarot      = { desc = "developer's tarot — today's card",     run = function(m) m.today() end },
  tiny_world = { desc = "ASCII garden that grows from saves",   run = function(m) m.show() end },
  haiku      = { desc = "AI 5-7-5 about function under cursor", run = function(m) m.compose() end },
  synth      = { desc = "system chord on save (toggle)",        run = function(m) m.toggle() end },
  glyph      = { desc = "deterministic sigils for cursor word", run = function(m) m.toggle() end },
  oracle     = { desc = "ask AI a yes/no with coin animation",
    run = function(m, args)
      if args and args ~= "" then
        m.ask({ args = args })
      else
        vim.ui.input({ prompt = "ask the oracle (yes/no): " }, function(q)
          if q and q ~= "" then m.ask({ args = q }) end
        end)
      end
    end,
  },
}

local _loaded = {}

local function load_toy(name)
  if _loaded[name] then return _loaded[name] end
  local ok, mod = pcall(require, "user._play." .. name)
  if not ok then return nil, mod end
  -- Don't call setup() — we don't want their :Aurora/:Matrix/etc. commands
  -- registered in the top-level namespace. Play is the single entry point.
  _loaded[name] = mod
  return mod
end

function M.run(name, rest)
  local toy = M.toys[name]
  if not toy then
    require("user.brand").notify("no such toy: " .. tostring(name), vim.log.levels.WARN, { title = "play" })
    return
  end
  local mod, err = load_toy(name)
  if not mod then
    require("user.brand").notify("failed to load " .. name .. ": " .. tostring(err), vim.log.levels.ERROR, { title = "play" })
    return
  end
  pcall(toy.run, mod, rest)
end

function M.list()
  local names = vim.tbl_keys(M.toys); table.sort(names)
  vim.ui.select(names, {
    prompt = "play with…",
    format_item = function(n) return string.format("%-12s  %s", n, M.toys[n].desc) end,
  }, function(choice) if choice then M.run(choice) end end)
end

function M.setup()
  vim.api.nvim_create_user_command("Play", function(args)
    -- :Play  → picker.  :Play <name>  → run.  :Play <name> <args>  → run with args
    if args.args == "" then return M.list() end
    local name, rest = args.args:match("^(%S+)%s*(.*)$")
    M.run(name, rest)
  end, {
    nargs = "?",
    complete = function(arg_lead)
      local out = {}
      for n in pairs(M.toys) do
        if n:sub(1, #arg_lead) == arg_lead then table.insert(out, n) end
      end
      return out
    end,
    desc = "Play with a novelty module — picker if no arg",
  })
end

return M
