-- Contribution calendar: GitHub-style 7×53 commit heatmap of YOUR git
-- activity for the past year. Floating panel, current week on the right.
local M = {}

local NS = vim.api.nvim_create_namespace("user_contribcal")
local LEVELS = { "#1e1e2e", "#1a4928", "#2d7a3a", "#4cae4d", "#7fdb83" }

local function bucket(count)
  if count == 0 then return 1 end
  if count == 1 then return 2 end
  if count <= 3 then return 3 end
  if count <= 6 then return 4 end
  return 5
end

local function color_hl(idx)
  local name = "Contrib_" .. idx
  vim.api.nvim_set_hl(0, name, { fg = LEVELS[idx], bg = LEVELS[idx] })
  return name
end

local function collect_commits()
  -- Get commit dates from last year for current user. Across ALL repos under
  -- $HOME would be ideal but expensive — restrict to the current repo unless
  -- vim.g.contribcal_repos is set to a list of paths.
  local repos = vim.g.contribcal_repos or { vim.fn.getcwd() }
  local me = vim.fn.systemlist("git config user.email")[1] or ""
  local counts = {}
  for _, repo in ipairs(repos) do
    local lines = vim.fn.systemlist({
      "git", "-C", repo, "log", "--since=1.year",
      "--author=" .. me, "--format=%cd", "--date=short",
    })
    for _, d in ipairs(lines) do
      counts[d] = (counts[d] or 0) + 1
    end
  end
  return counts
end

local function build_grid(counts)
  -- 53 weeks × 7 days. Newest week is the rightmost column. Days run Mon→Sun
  -- top to bottom. Each cell is { date, count, level }.
  local grid = {}
  for d = 1, 7 do grid[d] = {} end

  local today = os.date("*t")
  -- Start from today, walk back 53*7 days. To align: today is week-end column.
  local end_t = os.time({ year = today.year, month = today.month, day = today.day, hour = 12 })
  local total_days = 53 * 7
  for offset = 0, total_days - 1 do
    local t = end_t - offset * 86400
    local d = os.date("*t", t)
    local week = math.floor(offset / 7) + 1  -- 1 = current week
    local dow = (d.wday - 1) -- 0=Sun..6=Sat — but we want Mon-first
    dow = (dow == 0) and 6 or (dow - 1)
    local date_str = os.date("%Y-%m-%d", t)
    local cnt = counts[date_str] or 0
    grid[dow + 1][54 - week] = { date = date_str, count = cnt, level = bucket(cnt) }
  end
  return grid
end

local function render_grid(grid, counts)
  local lines = { "  CONTRIBUTION CALENDAR  ·  past year" }
  table.insert(lines, "")
  -- Month header row spanning the columns
  local months = { "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec" }
  local hdr = "    "
  -- Find which week each month starts in
  local seen = {}
  for week_idx = 1, 53 do
    local cell = grid[1][week_idx]
    if cell and cell.date then
      local m = tonumber(cell.date:sub(6, 7))
      if not seen[m] then
        seen[m] = true
        hdr = hdr .. string.format("%-4s", months[m]:sub(1,3))
        goto continue
      end
    end
    hdr = hdr .. "  "
    ::continue::
  end
  table.insert(lines, hdr)

  local day_labels = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
  local cell_extmarks = {}  -- {{row, col, hl}}
  for d = 1, 7 do
    local row_str = string.format(" %s ", day_labels[d])
    for w = 1, 53 do
      local c = grid[d][w]
      if c then
        row_str = row_str .. "■ "
        local col = #(" XXX ") + (w - 1) * 2
        local level = c.level
        table.insert(cell_extmarks, { #lines, col, color_hl(level), c })
      else
        row_str = row_str .. "  "
      end
    end
    table.insert(lines, row_str)
  end

  -- Legend + stats
  local total = 0; for _, c in pairs(counts) do total = total + c end
  table.insert(lines, "")
  table.insert(lines, string.format("  %d commits in the last year", total))
  table.insert(lines, "    Less  ■ ■ ■ ■ ■  More")

  return lines, cell_extmarks
end

function M.show()
  local counts = collect_commits()
  local grid = build_grid(counts)
  local lines, extmarks = render_grid(grid, counts)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  for _, em in ipairs(extmarks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, em[1], em[2], {
      end_col = em[2] + 1, hl_group = em[3],
    })
  end
  -- Legend row colors
  local legend_row = #lines - 1
  for i = 1, 5 do
    local col = 10 + (i - 1) * 2
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, legend_row, col, {
      end_col = col + 1, hl_group = color_hl(i),
    })
  end

  local w = math.max(unpack(vim.tbl_map(function(s) return vim.api.nvim_strwidth(s) end, lines))) + 4
  local h = #lines + 2
  vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = "  contributions ", title_pos = "center",
    width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
  })
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
end

function M.setup() vim.api.nvim_create_user_command("Contributions", M.show, { desc = "GitHub-style commit heatmap" }) end
return M
