-- Summon: track every window that opens and let you re-open one you closed.
-- "Give me back the trouble panel I closed 3 minutes ago"
local M = {}

local MAX = 20
local history = {}  -- newest first: { time, cmd, label }

local function record(label, reopen_cmd)
  -- Dedup against the most recent entry
  if history[1] and history[1].cmd == reopen_cmd then return end
  table.insert(history, 1, { time = os.time(), cmd = reopen_cmd, label = label })
  while #history > MAX do table.remove(history) end
end

local PATTERNS = {
  { ft = "Trouble",     label = "Trouble diagnostics",   cmd = "Trouble diagnostics open" },
  { ft = "neo-tree",    label = "Neo-tree explorer",     cmd = "Neotree" },
  { ft = "lazy",        label = "Lazy plugin manager",   cmd = "Lazy" },
  { ft = "mason",       label = "Mason package mgr",     cmd = "Mason" },
  { ft = "DiffviewFiles", label = "Diffview",            cmd = "DiffviewOpen" },
  { ft = "fugitive",    label = "Fugitive",              cmd = "Git" },
  { ft = "NeogitStatus", label = "Neogit",               cmd = "Neogit" },
  { ft = "dbui",        label = "Database UI",           cmd = "DBUIToggle" },
  { ft = "dbout",       label = "Database UI",           cmd = "DBUIToggle" },
  { ft = "qf",          label = "Quickfix",              cmd = "copen" },
  { ft = "help",        label = "Help",                  cmd_fn = function(buf)
      local f = vim.api.nvim_buf_get_name(buf):match("([^/]+)%.txt$")
      return f and ("help " .. f) or nil end },
  { ft = "aerial",      label = "Aerial outline",        cmd = "AerialOpen" },
  { ft = "OverseerList", label = "Overseer tasks",       cmd = "OverseerOpen" },
  { ft = "perfhud",     label = "Perf HUD",              cmd = "PerfHUD" },
  { ft = "symtree",     label = "Symbol tree",           cmd = "SymTree" },
  { ft = "tsplay",      label = "Treesitter playground", cmd = "TSPlay" },
}

local function ago(t)
  local d = os.time() - t
  if d < 60 then return d .. "s ago" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  return math.floor(d / 3600) .. "h ago"
end

function M.show()
  if #history == 0 then
    local ok, brand = pcall(require, "user.brand")
    if ok then brand.notify("no windows to recall yet · open and close a few panels first", vim.log.levels.INFO, { title = "summon" })
    else vim.notify("summon: nothing to recall yet") end
    return
  end
  local items = {}
  for _, h in ipairs(history) do
    table.insert(items, string.format("[%-8s]  %s", ago(h.time), h.label))
  end
  vim.ui.select(items, { prompt = "Summon back" }, function(_, idx)
    if not idx then return end
    pcall(vim.cmd, history[idx].cmd)
  end)
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("user_summon", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinNew" }, {
    group = grp,
    callback = function(args)
      local buf = args.buf
      local ft = vim.bo[buf].filetype
      for _, p in ipairs(PATTERNS) do
        if p.ft == ft then
          local cmd = p.cmd_fn and p.cmd_fn(buf) or p.cmd
          if cmd then record(p.label, cmd); return end
        end
      end
    end,
  })
  vim.api.nvim_create_user_command("Summon", M.show, { desc = "Recall a recently-closed plugin window" })
end

return M
