-- Homunculus: an idle agent that, when called, gathers today's git diff
-- and asks Claude to summarize it in journal form, then appends to a
-- daily file under ~/notes/journal/YYYY-MM-DD.md.
-- Auto-runs at session end (VimLeavePre) if anything happened today.
local M = {}

local JOURNAL_DIR = vim.fn.expand("~/notes/journal")
local MODEL = "claude-haiku-4-5-20251001"
local ENDPOINT = "https://api.anthropic.com/v1/messages"
local _last_run = 0

local function key()
  local k = vim.env.ANTHROPIC_API_KEY
  if not k or k == "" then return nil end
  return k
end

local function gather_diff_today(cwd, cb)
  -- Diff of working tree against HEAD as of midnight today + committed-today log
  vim.system({ "git", "-C", cwd, "log", "--since=midnight", "--no-merges",
               "--format=%h %s%n%b%n---", "--stat" }, { text = true }, function(log_res)
    vim.system({ "git", "-C", cwd, "diff", "HEAD" }, { text = true }, function(diff_res)
      vim.schedule(function()
        cb({
          log = log_res.stdout or "",
          diff = diff_res.stdout or "",
        })
      end)
    end)
  end)
end

local function summarize(text, cb)
  local k = key(); if not k then cb(nil, "no API key") return end

  local prompt = string.format([[You are the user's journal-keeper. Below are TODAY's git activities in their current project (commits + uncommitted diff).

Write a concise journal entry in their voice (first person, past tense), 4-8 sentences. Focus on:
- What was accomplished or attempted
- What problems were encountered or solved
- Any apparent themes or decisions
- Skip routine noise (whitespace, formatting, version bumps)

If there's nothing meaningful, just write one line like "Mostly housekeeping today."

Today's data:
%s

Reply with ONLY the journal entry. No heading, no markdown, no preamble.]], text:sub(1, 30000))

  vim.system({
    "curl", "-sS",
    "-H", "Content-Type: application/json",
    "-H", "x-api-key: " .. k,
    "-H", "anthropic-version: 2023-06-01",
    "-d", vim.json.encode({
      model = MODEL, max_tokens = 600,
      messages = { { role = "user", content = prompt } },
    }),
    ENDPOINT,
  }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then cb(nil, "curl exit " .. res.code) return end
      local ok, parsed = pcall(vim.json.decode, res.stdout or "")
      if not ok or not parsed.content then cb(nil, "bad response") return end
      cb(parsed.content[1] and parsed.content[1].text or "")
    end)
  end)
end

local function repo_name(cwd)
  return vim.fn.fnamemodify(cwd, ":t")
end

local function append_to_journal(repo, entry)
  vim.fn.mkdir(JOURNAL_DIR, "p")
  local path = JOURNAL_DIR .. "/" .. os.date("%Y-%m-%d") .. ".md"
  local f = io.open(path, "a")
  if not f then return false, "could not open " .. path end
  local ts = os.date("%H:%M")
  f:write(string.format("\n## %s · %s\n\n%s\n", ts, repo, vim.trim(entry)))
  f:close()
  return true, path
end

function M.wake(opts)
  opts = opts or {}
  local cwd = vim.fn.getcwd()
  if vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --is-inside-work-tree 2>/dev/null")[1] ~= "true" then
    if not opts.silent then vim.notify("homunculus: not a git repo") end
    return
  end

  -- Throttle: don't wake more than once per 10 minutes
  if vim.uv.now() - _last_run < 10 * 60 * 1000 then
    if not opts.silent then vim.notify("homunculus: just slept (throttled, 10m)") end
    return
  end
  _last_run = vim.uv.now()

  if not opts.silent then vim.notify("✦ homunculus is gathering the day…") end

  gather_diff_today(cwd, function(data)
    local combined = "## Commits since midnight\n" .. data.log .. "\n\n## Uncommitted diff\n" .. data.diff
    if vim.trim(combined) == "## Commits since midnight\n\n\n## Uncommitted diff\n" then
      if not opts.silent then vim.notify("homunculus: nothing happened today, nothing to write") end
      return
    end
    summarize(combined, function(entry, err)
      if not entry then
        if not opts.silent then vim.notify("homunculus: " .. (err or "failed"), vim.log.levels.ERROR) end
        return
      end
      local ok, path = append_to_journal(repo_name(cwd), entry)
      if ok then
        vim.notify("✦ journal written → " .. vim.fn.fnamemodify(path, ":~:."))
      else
        vim.notify("homunculus: " .. (path or "write failed"), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.read()
  local path = JOURNAL_DIR .. "/" .. os.date("%Y-%m-%d") .. ".md"
  if vim.fn.filereadable(path) == 0 then vim.notify("homunculus: no entry today yet"); return end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function M.setup()
  -- Auto-wake on VimLeavePre if changes happened today (silent)
  local grp = vim.api.nvim_create_augroup("user_homunculus", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = grp,
    callback = function()
      -- Quick sync version: fire-and-forget the wake. May or may not finish
      -- before nvim exits. User can rerun :HomunculusWake manually.
      M.wake({ silent = true })
      vim.cmd("sleep 200m")  -- give curl a head start; not a guarantee
    end,
  })

  vim.api.nvim_create_user_command("HomunculusWake", function() M.wake() end, { desc = "Write today's journal entry now" })
  vim.api.nvim_create_user_command("HomunculusRead", M.read, { desc = "Open today's journal entry" })
end

return M
