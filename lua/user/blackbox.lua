-- Black box flight recorder. Logs every command, buffer open, mode change,
-- LSP attach, error, etc. with timestamp. Browse the timeline with :Blackbox.
local M = {}

local MAX = 500
local log = {}

local function push(kind, msg)
  table.insert(log, 1, {
    t = os.time(),
    ms = vim.uv.now(),
    kind = kind,
    msg = msg,
    buf = vim.api.nvim_buf_get_name(0):match("([^/]+)$") or "",
  })
  while #log > MAX do table.remove(log) end
end

local KIND_ICON = {
  cmd = "  ", buf = "  ", mode = "  ", lsp = "  ",
  diag = " ⚠  ", search = "  ", jump = "  ",
  yank = "  ", win = "  ", git = "  ", error = " ✗  ",
}

local function format_entry(e)
  local age = os.time() - e.t
  local ago = age < 60 and (age .. "s")
    or age < 3600 and (math.floor(age / 60) .. "m")
    or age < 86400 and (math.floor(age / 3600) .. "h")
    or (math.floor(age / 86400) .. "d")
  return string.format("[%4s ago] %s %-7s  %-15s  %s",
    ago, (KIND_ICON[e.kind] or " ?  "), e.kind, e.buf:sub(1, 15),
    (e.msg or ""):gsub("\n", " ↵ "):sub(1, 80))
end

function M.show()
  if #log == 0 then
    local ok, brand = pcall(require, "user.brand")
    if ok then brand.notify("the black box is quiet · come back after you've done a few things", vim.log.levels.INFO, { title = "blackbox" })
    else vim.notify("Blackbox empty (just started recording)") end
    return
  end
  local lines = { "  BLACK BOX  ·  " .. #log .. " events  ·  newest first" }
  table.insert(lines, string.rep("─", 100))
  for _, e in ipairs(log) do table.insert(lines, format_entry(e)) end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = 102
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.85))
  vim.api.nvim_open_win(buf, true, {
    relative = "editor", border = "rounded", style = "minimal",
    title = " ⬛ BLACK BOX ", title_pos = "center",
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "c", function() log = {}; vim.notify("Blackbox cleared") end, { buffer = buf })
  vim.keymap.set("n", "s", function()
    local path = vim.fn.stdpath("state") .. "/blackbox-" .. os.date("%Y%m%d-%H%M%S") .. ".json"
    local f = io.open(path, "w")
    if f then f:write(vim.json.encode(log)); f:close(); vim.notify("Saved to " .. path) end
  end, { buffer = buf, desc = "Save log to disk" })
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("user_blackbox", { clear = true })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = grp,
    callback = function()
      local line = vim.fn.getcmdline()
      if line and #line > 0 then push("cmd", ":" .. line) end
    end,
  })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = grp,
    callback = function(args) push("buf", "opened " .. (vim.api.nvim_buf_get_name(args.buf) or "")) end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = grp,
    callback = function(args) push("buf", "wrote " .. (vim.api.nvim_buf_get_name(args.buf) or "")) end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = grp,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      push("lsp", "attached " .. (client and client.name or "?"))
    end,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = grp,
    callback = function(args)
      local errs = #vim.tbl_filter(function(d) return d.severity == 1 end, args.data.diagnostics or {})
      if errs > 0 then push("diag", errs .. " errors in " .. (vim.api.nvim_buf_get_name(args.buf) or "")) end
    end,
  })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = grp,
    callback = function()
      local txt = table.concat(vim.v.event.regcontents or {}, " ")
      push("yank", "yanked " .. (#txt) .. "b")
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = grp, once = true,
    callback = function() push("cmd", "session started") end,
  })

  vim.api.nvim_create_user_command("Blackbox", M.show, { desc = "Browse the action recorder timeline" })
end

return M
