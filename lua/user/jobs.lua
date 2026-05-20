-- Async job queue. `:Job make build` runs `make build` in the background,
-- shows a spinner in lualine while it runs, notifies on completion with
-- exit code + duration. `:JobList` shows running + history.
local M = {}

M._running = {}      -- key=id, val={name, cmd, started, handle, output}
M._history = {}      -- last 20 finished
M._next_id = 1

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function format_dur(ms)
  if ms < 1000 then return ms .. "ms" end
  if ms < 60000 then return string.format("%.1fs", ms / 1000) end
  return string.format("%dm%ds", math.floor(ms / 60000), math.floor((ms % 60000) / 1000))
end

function M.run(name, cmd)
  if type(cmd) == "string" then cmd = vim.split(cmd, "%s+") end
  local id = M._next_id; M._next_id = id + 1
  local job = { id = id, name = name, cmd = table.concat(cmd, " "), started = vim.uv.now(), output = {} }

  job.handle = vim.system(cmd, {
    text = true,
    stdout = function(_, data) if data then table.insert(job.output, data) end end,
    stderr = function(_, data) if data then table.insert(job.output, data) end end,
  }, function(res)
    vim.schedule(function()
      M._running[id] = nil
      job.code = res.code
      job.duration = vim.uv.now() - job.started
      table.insert(M._history, 1, job)
      if #M._history > 20 then table.remove(M._history) end
      local level = res.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
      local icon = res.code == 0 and "✓" or "✗"
      vim.notify(string.format("%s job %s (%s) %s exit=%d",
        icon, name, format_dur(job.duration),
        res.code == 0 and "done" or "failed",
        res.code), level)
    end)
  end)
  M._running[id] = job
  vim.notify("▸ job " .. name .. " started")
  return id
end

function M.cancel(id)
  local job = M._running[id]
  if not job then vim.notify("No running job " .. id, vim.log.levels.WARN); return end
  if job.handle and job.handle.kill then job.handle:kill("sigterm") end
end

function M.list()
  local items = {}
  for _, j in pairs(M._running) do
    table.insert(items, string.format("[run]  #%d  %-20s  %s  %s",
      j.id, j.name, format_dur(vim.uv.now() - j.started), j.cmd))
  end
  for _, j in ipairs(M._history) do
    local icon = j.code == 0 and "✓" or "✗"
    table.insert(items, string.format("[%s ]  #%d  %-20s  %s  %s",
      icon, j.id, j.name, format_dur(j.duration or 0), j.cmd))
  end
  if #items == 0 then vim.notify("No jobs"); return end
  vim.ui.select(items, { prompt = "Jobs" }, function(choice)
    if not choice then return end
    local id = tonumber(choice:match("#(%d+)"))
    local job = M._running[id]
    if not job then
      for _, j in ipairs(M._history) do if j.id == id then job = j; break end end
    end
    if job then
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(table.concat(job.output), "\n"))
      vim.api.nvim_open_win(buf, true, {
        relative = "editor", border = "rounded",
        width = math.floor(vim.o.columns * 0.8),
        height = math.floor(vim.o.lines * 0.75),
        row = math.floor(vim.o.lines * 0.1),
        col = math.floor(vim.o.columns * 0.1),
        title = (" job #" .. job.id .. " — " .. job.name .. " "),
        title_pos = "center", style = "minimal",
      })
      vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
    end
  end)
end

-- Returns a string for lualine: "⠋ 2 jobs"  or ""
function M.statusline()
  local n = vim.tbl_count(M._running)
  if n == 0 then return "" end
  local frame = SPINNER[(math.floor(vim.uv.now() / 100) % #SPINNER) + 1]
  return string.format("  %s %d job%s", frame, n, n == 1 and "" or "s")
end

function M.setup()
  vim.api.nvim_create_user_command("Job", function(args)
    local rest = args.args
    local name, cmd = rest:match("^(%S+)%s+(.*)")
    if not name then vim.notify("Usage: :Job <name> <cmd...>"); return end
    M.run(name, cmd)
  end, { nargs = "+", complete = "shellcmd", desc = "Run a shell job in the background" })

  vim.api.nvim_create_user_command("JobList", M.list, { desc = "List running + recent jobs" })
  vim.api.nvim_create_user_command("JobCancel", function(args)
    M.cancel(tonumber(args.args))
  end, { nargs = 1, desc = "Cancel a running job by id" })
end

return M
