-- Today dashboard: shows what you did today inside the current git repo.
-- Commits, files touched, lines added/removed, top changed files, focus
-- pomos completed (if pomo.nvim is loaded), and a per-hour edit sparkline.
local M = {}

local function git(args, cwd, cb)
  vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }, function(res)
    vim.schedule(function() cb(res.code == 0 and (res.stdout or "") or "") end)
  end)
end

local function repo_root(cb)
  vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }, function(res)
    vim.schedule(function() cb(res.code == 0 and (res.stdout or ""):gsub("%s+$", "") or nil) end)
  end)
end

local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local function sparkline(values)
  if #values == 0 then return "" end
  local max = 0
  for _, v in ipairs(values) do if v > max then max = v end end
  if max == 0 then return string.rep("·", #values) end
  local out = {}
  for _, v in ipairs(values) do
    local idx = math.max(1, math.ceil((v / max) * #SPARK))
    table.insert(out, SPARK[idx])
  end
  return table.concat(out)
end

local function pomos_completed()
  local ok, pomo = pcall(require, "pomo")
  if not ok then return nil end
  -- pomo.nvim's public API exposes `get_all_timers()`. The plugin returns
  -- nil instead of {} when no timers exist, so default with `or {}`. We
  -- also defend against the function itself being absent (in case a future
  -- version renames it again) — the chip just hides instead of crashing.
  local list_fn = pomo.get_all_timers or pomo.get_all
  if type(list_fn) ~= "function" then return nil end
  local count = 0
  for _, t in ipairs(list_fn() or {}) do
    if t._completed then count = count + 1 end
  end
  return count
end

local function render_window(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"; vim.bo[buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = 70
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", border = "rounded", style = "minimal",
    title = " 󰃭 today ", title_pos = "center",
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.wo[win].wrap = true; vim.wo[win].conceallevel = 2
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
end

function M.show()
  repo_root(function(root)
    if not root then vim.notify("today: not in a git repo", vim.log.levels.WARN); return end
    local since = os.date("%Y-%m-%d") .. " 00:00:00"

    -- Fire several git queries in parallel and join
    local results = {}
    local pending = 4
    local function done()
      pending = pending - 1
      if pending > 0 then return end

      -- Parse commit list to get count + per-hour bucket
      local commits = {}
      for line in (results.commits or ""):gmatch("([^\n]+)") do
        local h = tonumber(line:match("(%d%d):%d%d:%d%d"))
        if h then table.insert(commits, h) end
      end
      local hourly = {}
      for h = 0, 23 do hourly[h + 1] = 0 end
      for _, h in ipairs(commits) do hourly[h + 1] = hourly[h + 1] + 1 end

      -- Parse shortstat: "  3 files changed, 47 insertions(+), 9 deletions(-)"
      local files_n, added, removed = 0, 0, 0
      do
        local s = results.shortstat or ""
        local f = s:match("(%d+) files? changed")
        local a = s:match("(%d+) insertions?")
        local d = s:match("(%d+) deletions?")
        files_n, added, removed = tonumber(f) or 0, tonumber(a) or 0, tonumber(d) or 0
      end

      -- Top files
      local top_lines = {}
      do
        local nlines = 0
        for line in (results.numstat or ""):gmatch("[^\n]+") do
          if nlines >= 8 then break end
          local plus, minus, file = line:match("^(%S+)%s+(%S+)%s+(.+)$")
          if plus and file then
            table.insert(top_lines, string.format("  %-40s  +%-4s  -%-4s", file:sub(-40), plus, minus))
            nlines = nlines + 1
          end
        end
      end

      -- Branch summary
      local branch = ((results.branch or ""):gsub("%s+$", ""))
      if branch == "" then branch = "(detached)" end

      local pomos = pomos_completed()
      local lines = {
        "# 󰃭 Today  " .. os.date("%A, %B %d, %Y"),
        "",
        "##  Repo",
        "  " .. vim.fn.fnamemodify(root, ":~"),
        "  on branch  " .. branch,
        "",
        "##  Activity",
        string.format("  %d commits           %d files          +%d lines  -%d lines",
          #commits, files_n, added, removed),
        "",
        "##  Hourly commit pattern  (00 → 23)",
        "  " .. sparkline(hourly),
      }
      if pomos then
        table.insert(lines, "")
        table.insert(lines, "##  Pomodoros completed:  " .. pomos)
      end
      if #top_lines > 0 then
        table.insert(lines, "")
        table.insert(lines, "##  Top changed files")
        for _, l in ipairs(top_lines) do table.insert(lines, l) end
      end
      table.insert(lines, "")
      table.insert(lines, "                                              [q] close")
      render_window(lines)
    end

    git({ "log", "--since=" .. since, "--pretty=format:%cI %s" }, root, function(out) results.commits = out; done() end)
    git({ "log", "--since=" .. since, "--shortstat", "--no-merges", "--format=" }, root, function(out)
      -- Sum across all commits today
      local total = ""
      for line in out:gmatch("[^\n]+") do
        if line:find("files? changed") then total = (total ~= "" and (total .. "; ") or "") .. line end
      end
      -- Easier: take the totals via git diff --shortstat
      git({ "log", "--since=" .. since, "--shortstat", "--no-merges", "--pretty=format:" }, root, function(out2)
        local f, a, d = 0, 0, 0
        for line in out2:gmatch("[^\n]+") do
          f = f + (tonumber(line:match("(%d+) files? changed")) or 0)
          a = a + (tonumber(line:match("(%d+) insertions?")) or 0)
          d = d + (tonumber(line:match("(%d+) deletions?")) or 0)
        end
        results.shortstat = string.format("%d files changed, %d insertions, %d deletions", f, a, d)
        done()
      end)
    end)
    git({ "log", "--since=" .. since, "--numstat", "--no-merges", "--format=" }, root, function(out)
      -- Aggregate per-file: file → (plus, minus)
      local agg = {}
      for line in out:gmatch("[^\n]+") do
        local plus, minus, file = line:match("^(%S+)%s+(%S+)%s+(.+)$")
        if file and plus ~= "-" then
          agg[file] = agg[file] or { plus = 0, minus = 0 }
          agg[file].plus = agg[file].plus + (tonumber(plus) or 0)
          agg[file].minus = agg[file].minus + (tonumber(minus) or 0)
        end
      end
      local list = {}
      for f, v in pairs(agg) do table.insert(list, { f = f, plus = v.plus, minus = v.minus }) end
      table.sort(list, function(a, b) return (a.plus + a.minus) > (b.plus + b.minus) end)
      local rebuilt = {}
      for _, e in ipairs(list) do table.insert(rebuilt, ("%d\t%d\t%s"):format(e.plus, e.minus, e.f)) end
      results.numstat = table.concat(rebuilt, "\n")
      done()
    end)
    git({ "rev-parse", "--abbrev-ref", "HEAD" }, root, function(out) results.branch = out; done() end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("Today", M.show, { desc = "Show today's activity dashboard" })
end

return M
