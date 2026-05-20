-- Per-filetype REPL: opens the right REPL for the current buffer in a
-- floating term. Send current line / selection / paragraph to it.
local M = {}

local REPLS = {
  python      = { cmd = function() return vim.fn.executable("ipython") == 1 and "ipython" or "python3" end },
  lua         = { cmd = "lua" },
  javascript  = { cmd = "node" },
  typescript  = { cmd = function() return vim.fn.executable("ts-node") == 1 and "ts-node" or "node" end },
  ruby        = { cmd = "irb" },
  go          = { cmd = "go run -" }, -- doesn't repl; placeholder
  rust        = { cmd = "evcxr" },
  sh          = { cmd = vim.o.shell },
  bash        = { cmd = "bash" },
  zsh         = { cmd = "zsh" },
  fish        = { cmd = "fish" },
  sql         = { cmd = "psql" },
  clojure     = { cmd = "clojure" },
  julia       = { cmd = "julia" },
  haskell     = { cmd = "ghci" },
  r           = { cmd = "R" },
  elixir      = { cmd = "iex" },
  ocaml       = { cmd = "utop" },
}

local state = { term = nil }

local function get_cmd(ft)
  local r = REPLS[ft]
  if not r then return nil end
  return type(r.cmd) == "function" and r.cmd() or r.cmd
end

local function ensure(ft)
  local cmd = get_cmd(ft)
  if not cmd then return nil end
  if state.term and state.term:is_open() then return state.term end
  local Terminal = require("toggleterm.terminal").Terminal
  state.term = Terminal:new({
    cmd = cmd,
    direction = "vertical",
    size = math.floor(vim.o.columns * 0.4),
    hidden = true,
    close_on_exit = false,
  })
  state.term:open()
  return state.term
end

local function send(text)
  if not state.term then return end
  -- Send line by line so the REPL processes each (more reliable than \n in many REPLs)
  for _, line in ipairs(vim.split(text, "\n")) do
    state.term:send(line, false)
  end
end

function M.toggle()
  local ft = vim.bo.filetype
  local cmd = get_cmd(ft)
  if not cmd then vim.notify("REPL: no REPL configured for " .. ft, vim.log.levels.WARN); return end
  if state.term and state.term:is_open() then
    state.term:close()
  else
    ensure(ft)
  end
end

function M.send_line()
  if not state.term then ensure(vim.bo.filetype) end
  local line = vim.api.nvim_get_current_line()
  send(line)
end

function M.send_selection()
  if not state.term then ensure(vim.bo.filetype) end
  -- Save+restore the unnamed register; yank visual selection into z
  local saved = vim.fn.getreg("z")
  vim.cmd('silent! normal! "zy')
  send(vim.fn.getreg("z"))
  vim.fn.setreg("z", saved)
end

function M.send_paragraph()
  if not state.term then ensure(vim.bo.filetype) end
  local saved = vim.fn.getreg("z")
  vim.cmd('silent! normal! "zyap')
  send(vim.fn.getreg("z"))
  vim.fn.setreg("z", saved)
end

function M.send_buffer()
  if not state.term then ensure(vim.bo.filetype) end
  send(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
end

function M.setup()
  vim.api.nvim_create_user_command("Repl",          M.toggle,          { desc = "Toggle REPL for current ft" })
  vim.api.nvim_create_user_command("ReplLine",      M.send_line,       { desc = "Send current line to REPL" })
  vim.api.nvim_create_user_command("ReplSelection", M.send_selection,  { desc = "Send visual selection to REPL", range = true })
  vim.api.nvim_create_user_command("ReplParagraph", M.send_paragraph,  { desc = "Send paragraph to REPL" })
  vim.api.nvim_create_user_command("ReplBuffer",    M.send_buffer,     { desc = "Send buffer to REPL" })
end

return M
