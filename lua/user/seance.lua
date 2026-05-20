-- Seance: surfaces git blame of every line as you cursor through them.
-- On CursorHold, runs `git blame -L lnum,lnum` and shows the author + age
-- + commit subject as virtual text at end-of-line. Like the past whispers.
local M = {}

local NS = vim.api.nvim_create_namespace("user_seance")
local cache = {}   -- key="bufnr:lnum" -> { author, age, subject }
local active = {}  -- bufnr -> autocmd id

local function age_phrase(when_iso)
  local y, m, d = when_iso:match("(%d+)-(%d+)-(%d+)")
  if not y then return "?" end
  local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  local days = math.floor((os.time() - ts) / 86400)
  if days < 1   then return "today" end
  if days == 1  then return "yesterday" end
  if days < 7   then return days .. " days ago" end
  if days < 30  then return math.floor(days / 7) .. " weeks ago" end
  if days < 365 then return math.floor(days / 30) .. " months ago" end
  return math.floor(days / 365) .. " years ago"
end

local function whisper_for(bufnr, lnum)
  local key = bufnr .. ":" .. lnum
  if cache[key] then return cache[key] end
  cache[key] = false  -- prevent re-entry

  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then return nil end
  local cwd = vim.fn.fnamemodify(file, ":h")
  vim.system({
    "git", "-C", cwd, "blame", "-L", lnum .. "," .. lnum, "--porcelain", "--", file,
  }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then cache[key] = nil; return end
      local sha = (res.stdout or ""):match("^(%x+)")
      local author = (res.stdout or ""):match("\nauthor%s+([^\n]+)")
      local when = (res.stdout or ""):match("\ncommitter%-time%s+(%d+)")
      local tz = (res.stdout or ""):match("\ncommitter%-tz%s+([%+%-]%d+)") or ""
      local subject = (res.stdout or ""):match("\nsummary%s+([^\n]+)") or ""
      if not sha or sha == "0000000000000000000000000000000000000000" then
        cache[key] = { author = "uncommitted", age = "now", subject = "(local edit)" }
      else
        local iso = when and os.date("%Y-%m-%d", tonumber(when)) or ""
        cache[key] = {
          author = (author or "?"):match("^[^%s]+") or "?",  -- first name
          age = age_phrase(iso),
          subject = subject:sub(1, 50),
        }
      end
      -- Trigger a redraw to surface the whisper
      pcall(M._render, bufnr, lnum)
    end)
  end)
  return nil
end

function M._render(bufnr, lnum)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  vim.api.nvim_buf_clear_namespace(bufnr, NS, lnum - 1, lnum)
  local key = bufnr .. ":" .. lnum
  local data = cache[key]
  if not data or type(data) ~= "table" then return end
  local text = string.format(" ⟁  %s · %s · %s", data.author, data.age, data.subject)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum - 1, 0, {
    virt_text = { { text, "Comment" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = 220,
  })
end

local function on_cursor(bufnr)
  -- Clear any previous whisper, only show one at a time
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local data = whisper_for(bufnr, lnum)
  if data then M._render(bufnr, lnum) end
end

function M.enable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then return end
  active[bufnr] = vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    buffer = bufnr,
    callback = function() on_cursor(bufnr) end,
  })
  vim.notify("seance: the past is listening (pause cursor on a line)")
end

function M.disable(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  if active[bufnr] then vim.api.nvim_del_autocmd(active[bufnr]); active[bufnr] = nil end
  -- Drop cache for this buffer
  for k in pairs(cache) do if k:sub(1, #tostring(bufnr) + 1) == bufnr .. ":" then cache[k] = nil end end
  vim.notify("seance: silenced")
end

function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if active[bufnr] then M.disable(bufnr) else M.enable(bufnr) end
end

function M.setup() vim.api.nvim_create_user_command("Seance", M.toggle, { desc = "Toggle line-by-line git blame whispers" }) end
return M
