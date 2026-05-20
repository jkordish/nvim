-- Dimensional Rift: select a region, then :Rift to open a floating window
-- showing every other place in the project where the same text appears,
-- with surrounding context. Like looking through your code at all the
-- universes where this snippet also lives.
local M = {}

local function selection_text()
  -- Grab the last visual selection
  local s = vim.api.nvim_buf_get_mark(0, "<")
  local e = vim.api.nvim_buf_get_mark(0, ">")
  if s[1] == 0 then return nil end
  local lines = vim.api.nvim_buf_get_lines(0, s[1] - 1, e[1], false)
  if #lines == 0 then return nil end
  -- For single-line selection, slice columns
  if #lines == 1 then
    return lines[1]:sub(s[2] + 1, e[2] + 1)
  end
  -- Multi-line: clip first and last lines
  lines[1] = lines[1]:sub(s[2] + 1)
  lines[#lines] = lines[#lines]:sub(1, e[2] + 1)
  return table.concat(lines, "\n")
end

local function find_echoes(query, callback)
  -- Use ripgrep to find verbatim matches. For multi-line queries, --multiline.
  local args = { "rg", "--no-heading", "--line-number", "--with-filename", "--color=never", "--max-count=20" }
  if query:find("\n") then table.insert(args, "--multiline") end
  table.insert(args, "--fixed-strings")
  table.insert(args, "--")
  table.insert(args, query)

  vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 and res.code ~= 1 then
        callback({}, "rg exit " .. res.code)
        return
      end
      local matches = {}
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        local file, lnum, text = line:match("^([^:]+):(%d+):(.*)$")
        if file then table.insert(matches, { file = file, lnum = tonumber(lnum), text = text }) end
      end
      callback(matches)
    end)
  end)
end

local function render_echoes(query, matches)
  local current_file = vim.api.nvim_buf_get_name(0)
  -- Filter out the originating buffer? Keep them, but mark.
  local lines = {
    "  ✦  DIMENSIONAL RIFT",
    "  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄",
    string.format("  looking through the membrane for echoes of %d chars…", #query),
    "",
  }
  if #matches == 0 then
    table.insert(lines, "  no echoes found. this fragment exists only here.")
  else
    table.insert(lines, string.format("  found %d echo%s across the project:", #matches, #matches == 1 and "" or "es"))
    table.insert(lines, "")
    local by_file = {}
    for _, m in ipairs(matches) do
      by_file[m.file] = by_file[m.file] or {}
      table.insert(by_file[m.file], m)
    end
    local file_order = vim.tbl_keys(by_file); table.sort(file_order)
    for _, f in ipairs(file_order) do
      local marker = (f == current_file) and " ◉" or " ○"
      local short = vim.fn.fnamemodify(f, ":~:.")
      table.insert(lines, string.format("  %s  %s", marker, short))
      for _, m in ipairs(by_file[f]) do
        table.insert(lines, string.format("     %4d │ %s", m.lnum, m.text:gsub("^%s+", ""):sub(1, 80)))
      end
      table.insert(lines, "")
    end
  end
  table.insert(lines, "  [ <CR> jump to echo under cursor ]   [ q close ]")
  return lines
end

local function pick_under_cursor()
  -- Parse "    NNNN │ ..." line, jump to that lnum in the file just above.
  local pos = vim.api.nvim_win_get_cursor(0)
  local row = pos[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local lnum = lines[row]:match("^%s*(%d+)%s+│")
  if not lnum then return end
  -- Scan upward for the file marker
  for r = row - 1, 1, -1 do
    local file = lines[r]:match("^%s+[◉○]%s+(.+)$")
    if file then
      vim.cmd("close")
      vim.cmd("edit " .. vim.fn.fnameescape(file))
      pcall(vim.api.nvim_win_set_cursor, 0, { tonumber(lnum), 0 })
      vim.cmd("normal! zz")
      return
    end
  end
end

function M.open()
  local q = selection_text()
  if not q or q == "" then vim.notify("rift: no visual selection"); return end
  -- Trim trailing whitespace for cleaner search
  q = q:gsub("%s+$", "")

  find_echoes(q, function(matches, err)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
    local lines = err and { "  rift error: " .. err } or render_echoes(q, matches)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    local W = math.min(120, vim.o.columns - 8)
    local H = math.min(#lines + 2, math.floor(vim.o.lines * 0.85))
    vim.api.nvim_open_win(buf, true, {
      relative = "editor", border = "rounded", style = "minimal",
      title = " ✦  dimensional rift ", title_pos = "center",
      width = W, height = H,
      row = math.floor((vim.o.lines - H) / 2),
      col = math.floor((vim.o.columns - W) / 2),
    })
    vim.keymap.set("n", "<CR>", pick_under_cursor, { buffer = buf })
    vim.keymap.set("n", "q",     "<cmd>close<CR>", { buffer = buf })
    vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("Rift", M.open, { desc = "See echoes of visual selection across project", range = true })
end

return M
