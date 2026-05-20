-- Git time machine: scrub the current file across every commit that touched
-- it. ← prev commit, → next commit, q quit. Each step rewrites the buffer
-- with `git show <sha>:<file>` and shows the commit metadata in the title.
local M = {}

local state = { commits = {}, idx = 1, bufnr = nil, original_file = nil, original_lines = nil, original_modified = nil, original_ft = nil }

local function fetch_commits(file, cb)
  local rel = vim.fn.fnamemodify(file, ":.")
  vim.system({ "git", "log", "--follow", "--format=%H%x00%cI%x00%an%x00%s", "--", rel }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then cb(nil, "not a git file") return end
      local commits = {}
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        local sha, date, author, subj = line:match("([^%z]+)%z([^%z]+)%z([^%z]+)%z(.+)")
        if sha then table.insert(commits, { sha = sha, date = date, author = author, subject = subj }) end
      end
      cb(commits)
    end)
  end)
end

local function show_commit(idx)
  local c = state.commits[idx]
  if not c then return end
  state.idx = idx

  local rel = vim.fn.fnamemodify(state.original_file, ":.")
  vim.system({ "git", "show", c.sha .. ":" .. rel }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then vim.notify("git show failed: " .. (res.stderr or ""), vim.log.levels.ERROR); return end
      local lines = vim.split(res.stdout or "", "\n", { plain = true })
      if lines[#lines] == "" then table.remove(lines) end
      vim.bo[state.bufnr].modifiable = true
      vim.bo[state.bufnr].readonly = false
      vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
      vim.bo[state.bufnr].modifiable = false
      vim.bo[state.bufnr].readonly = true
      vim.bo[state.bufnr].modified = false
      local short = c.sha:sub(1, 7)
      local age = c.date:sub(1, 10)
      vim.api.nvim_buf_set_name(state.bufnr, ("[timetravel %d/%d  %s  %s]"):format(idx, #state.commits, short, age))
      vim.notify(string.format("[%d/%d] %s  %s  %s — %s",
        idx, #state.commits, short, age, c.author, c.subject))
    end)
  end)
end

local function setup_keymaps(bufnr)
  local opts = { buffer = bufnr, silent = true, nowait = true }
  vim.keymap.set("n", "<Left>",  function() if state.idx < #state.commits then show_commit(state.idx + 1) end end, opts) -- older
  vim.keymap.set("n", "<Right>", function() if state.idx > 1 then show_commit(state.idx - 1) end end, opts)               -- newer
  vim.keymap.set("n", "h",       function() if state.idx < #state.commits then show_commit(state.idx + 1) end end, opts)
  vim.keymap.set("n", "l",       function() if state.idx > 1 then show_commit(state.idx - 1) end end, opts)
  vim.keymap.set("n", "g",       function() show_commit(#state.commits) end, opts)
  vim.keymap.set("n", "G",       function() show_commit(1) end, opts)
  vim.keymap.set("n", "q",       function() M.exit() end, opts)
  vim.keymap.set("n", "<Esc>",   function() M.exit() end, opts)
end

function M.start()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then vim.notify("timetravel: no file") return end
  if vim.bo.modified then vim.notify("timetravel: save the buffer first", vim.log.levels.WARN); return end

  fetch_commits(file, function(commits, err)
    if not commits or #commits == 0 then vim.notify("timetravel: " .. (err or "no history found")); return end

    state.commits = commits
    state.bufnr = vim.api.nvim_get_current_buf()
    state.original_file = file
    state.original_lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
    state.original_ft = vim.bo[state.bufnr].filetype

    setup_keymaps(state.bufnr)
    show_commit(1)
    vim.notify(("Time machine engaged: %d commits.  ← older  → newer  g/G first/last  q exit"):format(#commits))
  end)
end

function M.exit()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then return end
  vim.bo[state.bufnr].modifiable = true
  vim.bo[state.bufnr].readonly = false
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, state.original_lines)
  vim.api.nvim_buf_set_name(state.bufnr, state.original_file)
  vim.bo[state.bufnr].filetype = state.original_ft or ""
  vim.bo[state.bufnr].modified = false
  -- Unmap our temp keys
  for _, k in ipairs({ "<Left>", "<Right>", "h", "l", "g", "G", "q", "<Esc>" }) do
    pcall(vim.keymap.del, "n", k, { buffer = state.bufnr })
  end
  state = { commits = {}, idx = 1 }
  vim.notify("Time machine disengaged")
end

function M.setup()
  vim.api.nvim_create_user_command("TimeTravel", M.start, { desc = "Scrub current file through every commit that touched it" })
end

return M
