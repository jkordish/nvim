-- Git churn heatmap: color each line's number gutter by how recently it
-- was last modified. Red = today, cooling through yellow → green → blue
-- for older. Uses extmarks in a private namespace.
local M = {}

local NS = vim.api.nvim_create_namespace("user_heatmap")
local active = {}

-- 9-step gradient red → blue (recent → ancient)
local PALETTE = {
  "#f38ba8", "#fab387", "#f9e2af", "#a6e3a1", "#94e2d5",
  "#74c7ec", "#89b4fa", "#b4befe", "#7287fd",
}

local function ensure_hl()
  for i, c in ipairs(PALETTE) do
    vim.api.nvim_set_hl(0, "UserHeatmap" .. i, { fg = c, bold = true })
  end
end

local function apply(bufnr, blame)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  ensure_hl()
  local now = os.time()
  -- Find min/max age across this file's blame
  local min_age, max_age = math.huge, 0
  for _, ts in pairs(blame) do
    local age = now - ts
    if age < min_age then min_age = age end
    if age > max_age then max_age = age end
  end
  local span = math.max(1, max_age - min_age)

  for lnum, ts in pairs(blame) do
    local age = now - ts
    local norm = (age - min_age) / span                    -- 0..1
    local bucket = math.floor(norm * (#PALETTE - 1)) + 1
    pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum - 1, 0, {
      sign_text = "▎",
      sign_hl_group = "UserHeatmap" .. bucket,
    })
  end
end

local function parse_blame(out)
  -- git blame --line-porcelain emits per-line records starting with
  -- "<sha> orig final lines", followed by author-time on a separate line.
  local blame = {}
  local current_line, current_time
  for line in out:gmatch("[^\n]+") do
    local sha, orig, final = line:match("^(%x+) (%d+) (%d+)")
    if sha then
      current_line = tonumber(final)
    else
      local t = line:match("^author%-time (%d+)")
      if t then current_time = tonumber(t) end
      if line:sub(1,1) == "\t" and current_line and current_time then
        blame[current_line] = current_time
        current_line, current_time = nil, nil
      end
    end
  end
  return blame
end

function M.show(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then vim.notify("Heatmap: no file") return end
  local cwd = vim.fn.fnamemodify(file, ":h")
  vim.system({ "git", "blame", "--line-porcelain", file }, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then vim.notify("Heatmap: not in git repo", vim.log.levels.WARN); return end
      local blame = parse_blame(res.stdout or "")
      apply(bufnr, blame)
      active[bufnr] = true
      vim.notify(string.format("Heatmap on (%d lines)", vim.tbl_count(blame)))
    end)
  end)
end

function M.hide(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  active[bufnr] = nil
  vim.notify("Heatmap off")
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then M.hide(bufnr) else M.show(bufnr) end
end

function M.setup()
  vim.api.nvim_create_user_command("Heatmap", function(args)
    if args.args == "off" then M.hide()
    elseif args.args == "on"  then M.show()
    else M.toggle() end
  end, { nargs = "?", desc = "Toggle git-churn heatmap on current buffer" })
end

return M
