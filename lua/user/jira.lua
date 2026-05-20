-- Jira: native Atlassian Cloud REST client + buffer UI.
--
-- Reads JIRA_BASE_URL, JIRA_USER_EMAIL, JIRA_API_TOKEN from the environment.
-- All HTTP via vim.system+curl (no extra deps). All floats via user.brand.win
-- so they inherit the curtain animation + mode-reactive border accent.
--
-- Surfaces:
--   :JiraIssue [KEY]      detail float (summary/status/assignee/desc/comments)
--   :JiraMine             picker of issues assigned to you & open
--   :JiraSearch <jql>     run a JQL query, pick a result
--   :JiraOpen [KEY]       open in browser
--   :JiraComment [KEY]    prompt and POST a comment
--   :JiraTransition [KEY] pick a status to move the ticket to
--   :JiraBranch [KEY]     pin the cwd to a specific ticket (overrides parse)
local M = {}

local brand = require("user.brand")
local icons = require("user.icons")

-- ─── config from env ──────────────────────────────────────────────────────
local function cfg()
  return {
    base  = (vim.env.JIRA_BASE_URL or ""):gsub("/+$", ""),
    email = vim.env.JIRA_USER_EMAIL or "",
    token = vim.env.JIRA_API_TOKEN or "",
  }
end

local function ensure_configured()
  local c = cfg()
  if c.base == "" or c.email == "" or c.token == "" then
    brand.notify("set JIRA_BASE_URL / JIRA_USER_EMAIL / JIRA_API_TOKEN in your shell",
      vim.log.levels.WARN, { title = "jira" })
    return nil
  end
  return c
end

-- ─── persistent + memory cache ────────────────────────────────────────────
local CACHE_FILE = vim.fn.stdpath("state") .. "/jira_cache.json"
local _cache = {
  issues      = {},   -- key -> { ts, data } (in-memory only)
  branch_pins = {},   -- cwd -> KEY
  recent      = {},   -- list of recently-viewed keys (most-recent first, capped)
  filters     = {},   -- name -> JQL
  last_jql    = nil,  -- most recent JQL ran (for :JiraSaveFilter)
}
local _mem_ttl     = 90    -- in-memory issue TTL (seconds)
local RECENT_CAP   = 20

local function load_cache()
  local f = io.open(CACHE_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a")); f:close()
  if ok and type(parsed) == "table" then
    _cache.branch_pins = parsed.branch_pins or {}
    _cache.recent      = parsed.recent      or {}
    _cache.filters     = parsed.filters     or {}
  end
end

local function save_cache()
  vim.fn.mkdir(vim.fn.fnamemodify(CACHE_FILE, ":h"), "p")
  local f = io.open(CACHE_FILE, "w")
  if f then
    f:write(vim.json.encode({
      branch_pins = _cache.branch_pins,
      recent      = _cache.recent,
      filters     = _cache.filters,
    }))
    f:close()
  end
end

-- Move a key to the front of the recent list; cap length, dedup, persist.
local function push_recent(key)
  if not key or key == "" then return end
  local out = { key }
  for _, k in ipairs(_cache.recent) do
    if k ~= key and #out < RECENT_CAP then table.insert(out, k) end
  end
  _cache.recent = out
  save_cache()
end

-- ─── auth + HTTP ──────────────────────────────────────────────────────────
-- Lua-only base64 (RFC 4648). Avoids depending on `openssl` being on PATH.
local function b64(data)
  local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  local i = 1
  while i <= #data do
    local a, b, c = data:byte(i, i + 2)
    b = b or 0; c = c or 0
    local n = a * 65536 + b * 256 + c
    table.insert(out, alpha:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1))
    table.insert(out, alpha:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1))
    table.insert(out, alpha:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1))
    table.insert(out, alpha:sub(n % 64 + 1, n % 64 + 1))
    i = i + 3
  end
  local pad = (3 - (#data % 3)) % 3
  local s = table.concat(out)
  if pad > 0 then s = s:sub(1, -1 - pad) .. string.rep("=", pad) end
  return s
end

local function auth_header(c) return "Authorization: Basic " .. b64(c.email .. ":" .. c.token) end

-- Extract a friendly message from a Jira error body. Jira returns either
-- `{errorMessages: [...], errors: {field: msg}}` or a plain string. Falls
-- back to a short slice of the raw body if neither shape is present.
local function friendly_error(body)
  if type(body) == "string" then
    -- might be the "HTTP 400 · {…}" string we built; try to extract the JSON tail
    local json_tail = body:match("·%s*(.+)$") or body
    local ok, parsed = pcall(vim.json.decode, json_tail, { luanil = { object = true, array = true } })
    if ok and type(parsed) == "table" then body = parsed
    else return (body):sub(1, 200) end
  end
  if type(body) ~= "table" then return tostring(body):sub(1, 200) end
  local parts = {}
  for _, m in ipairs(body.errorMessages or {}) do table.insert(parts, m) end
  for field, msg in pairs(body.errors or {}) do
    table.insert(parts, field .. ": " .. tostring(msg))
  end
  if #parts == 0 then return vim.json.encode(body):sub(1, 200) end
  return table.concat(parts, "  ·  ")
end

-- Async HTTP via curl. Calls `cb(ok, body|err, status)` on the main loop.
local function request(method, path, body, cb)
  local c = ensure_configured(); if not c then return end
  local url = c.base .. path
  local args = {
    "curl", "-sS", "-X", method,
    "-H", auth_header(c),
    "-H", "Accept: application/json",
    "-H", "Content-Type: application/json",
    "-w", "\n__HTTPSTATUS__%{http_code}",
    url,
  }
  if body then
    table.insert(args, "--data")
    table.insert(args, vim.json.encode(body))
  end
  vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb(false, "curl error (code " .. res.code .. "): " .. (res.stderr or ""), 0)
        return
      end
      local raw = res.stdout or ""
      local status_s = raw:match("__HTTPSTATUS__(%d+)%s*$") or "0"
      local status = tonumber(status_s) or 0
      local payload = raw:gsub("\n?__HTTPSTATUS__%d+%s*$", "")
      if status >= 200 and status < 300 then
        if payload == "" then return cb(true, {}, status) end
        -- luanil=object turns JSON nulls into real Lua nil (otherwise we get
        -- vim.NIL userdata, which `or {}` doesn't replace — every field
        -- access like `(fields.assignee or {}).displayName` then crashes
        -- with "attempt to index a userdata value" on unassigned issues).
        local ok, parsed = pcall(vim.json.decode, payload, { luanil = { object = true, array = true } })
        if ok then cb(true, parsed, status) else cb(false, "bad JSON: " .. payload:sub(1, 200), status) end
      else
        -- Parse Jira's error envelope so callers get "Issue does not exist"
        -- instead of a 200-char wall of JSON.
        local ok, parsed = pcall(vim.json.decode, payload, { luanil = { object = true, array = true } })
        local msg = ok and friendly_error(parsed) or payload:sub(1, 300)
        cb(false, ("HTTP %d · %s"):format(status, msg), status)
      end
    end)
  end)
end

-- ─── API wrappers ─────────────────────────────────────────────────────────
local function url_encode(s)
  return (s:gsub("([^%w%-_%.~])", function(c)
    return ("%%%02X"):format(c:byte())
  end))
end

function M.get_issue(key, cb)
  if not key then return end
  local hit = _cache.issues[key]
  if hit and (os.time() - hit.ts) < _mem_ttl then return cb(true, hit.data) end
  request("GET",
    "/rest/api/3/issue/" .. url_encode(key) .. "?fields=summary,status,assignee,reporter,priority,issuetype,description,comment,labels,updated,issuelinks,subtasks,parent,timetracking,worklog",
    nil,
    function(ok, data, status)
      if ok then _cache.issues[key] = { ts = os.time(), data = data } end
      cb(ok, data, status)
    end)
end

function M.search(jql, cb, max)
  _cache.last_jql = jql
  -- The `status` field carries `statusCategory.colorName` by default, so the
  -- picker chips get Jira's real category color without extra `expand`.
  request("POST", "/rest/api/3/search/jql", {
    jql = jql,
    fields = { "summary", "status", "assignee", "priority", "updated", "issuetype" },
    maxResults = max or 50,
  }, cb)
end

function M.my_open_issues(cb)
  M.search(
    'assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC',
    cb, 50)
end

function M.add_comment(key, body_text, cb)
  -- ADF (Atlassian Document Format) — minimal paragraph
  local adf = {
    type = "doc", version = 1,
    content = { { type = "paragraph", content = { { type = "text", text = body_text } } } },
  }
  request("POST", "/rest/api/3/issue/" .. url_encode(key) .. "/comment",
    { body = adf }, cb)
end

function M.list_transitions(key, cb)
  request("GET", "/rest/api/3/issue/" .. url_encode(key) .. "/transitions", nil, cb)
end

function M.search_assignable(key, query, cb)
  request("GET",
    "/rest/api/3/user/assignable/search?issueKey=" .. url_encode(key)
      .. "&query=" .. url_encode(query or "") .. "&maxResults=20",
    nil, cb)
end

function M.set_assignee(key, account_id, cb)
  -- Passing accountId = nil unassigns; "-1" assigns to default.
  request("PUT", "/rest/api/3/issue/" .. url_encode(key) .. "/assignee",
    { accountId = account_id }, cb)
end

-- Update arbitrary fields on an issue. Pass `{ description = "...text..." }`
-- as plain text; we wrap it as a single-paragraph ADF doc here.
function M.update_description(key, text, cb)
  local adf = {
    type = "doc", version = 1,
    content = { { type = "paragraph", content = { { type = "text", text = text } } } },
  }
  request("PUT", "/rest/api/3/issue/" .. url_encode(key),
    { fields = { description = adf } }, cb)
end

-- Worklog: time_spent is Jira's compact format ("30m", "2h 15m", "1d").
function M.add_worklog(key, time_spent, comment_text, cb)
  local body = { timeSpent = time_spent }
  if comment_text and comment_text ~= "" then
    body.comment = {
      type = "doc", version = 1,
      content = { { type = "paragraph", content = { { type = "text", text = comment_text } } } },
    }
  end
  request("POST", "/rest/api/3/issue/" .. url_encode(key) .. "/worklog", body, cb)
end

function M.do_transition(key, transition_id, cb)
  request("POST", "/rest/api/3/issue/" .. url_encode(key) .. "/transitions",
    { transition = { id = transition_id } }, cb)
end

-- ─── ADF → markdown-ish text ───────────────────────────────────────────────
-- Handles the node types that show up in real tickets:
--   text (with link/code/strong/em marks), paragraph, heading (1–6),
--   bulletList, orderedList, listItem, codeBlock (with language fence),
--   blockquote, rule, hardBreak, mention, inlineCard, panel.
-- Unknown nodes fall through to their content so we don't lose text.
local function adf_to_text(node)
  if type(node) ~= "table" then return "" end

  -- leaf nodes first
  if node.type == "mention" then
    local txt = (node.attrs and node.attrs.text) or (node.attrs and node.attrs.id) or "?"
    -- Atlassian stores mention text already prefixed with "@" most of the time
    if not txt:match("^@") then txt = "@" .. txt end
    return txt
  end
  if node.type == "inlineCard" then
    local url = node.attrs and node.attrs.url or ""
    return ("<%s>"):format(url)
  end
  if node.type == "hardBreak" then return "\n" end
  if node.type == "rule"       then return "\n\n---\n\n" end
  if node.text then
    local out = node.text
    -- apply marks (Atlassian sends them in order, outermost last)
    for _, mark in ipairs(node.marks or {}) do
      if mark.type == "code"   then out = "`" .. out .. "`"
      elseif mark.type == "strong" then out = "**" .. out .. "**"
      elseif mark.type == "em"     then out = "*" .. out .. "*"
      elseif mark.type == "strike" then out = "~~" .. out .. "~~"
      elseif mark.type == "link" and mark.attrs and mark.attrs.href then
        out = ("[%s](%s)"):format(out, mark.attrs.href)
      end
    end
    return out
  end

  -- collect children
  local parts = {}
  for _, child in ipairs(node.content or {}) do
    table.insert(parts, adf_to_text(child))
  end
  local joined = table.concat(parts, "")

  -- block types
  local t = node.type
  if t == "heading" then
    local lvl = math.max(1, math.min(6, (node.attrs and node.attrs.level) or 2))
    return "\n\n" .. string.rep("#", lvl) .. " " .. joined .. "\n"
  elseif t == "paragraph" then
    return joined .. "\n\n"
  elseif t == "listItem" then
    -- the parent list adds the bullet; we just emit one logical line per item
    return joined:gsub("\n+$", "") .. "\n"
  elseif t == "bulletList" then
    local out = {}
    for _, line in ipairs(vim.split(joined, "\n")) do
      if line ~= "" then table.insert(out, "  • " .. line) end
    end
    return table.concat(out, "\n") .. "\n\n"
  elseif t == "orderedList" then
    local out, n = {}, 0
    for _, line in ipairs(vim.split(joined, "\n")) do
      if line ~= "" then n = n + 1; table.insert(out, ("  %d. "):format(n) .. line) end
    end
    return table.concat(out, "\n") .. "\n\n"
  elseif t == "codeBlock" then
    local lang = (node.attrs and node.attrs.language) or ""
    return ("\n```%s\n%s\n```\n\n"):format(lang, joined:gsub("\n+$", ""))
  elseif t == "blockquote" then
    local out = {}
    for _, line in ipairs(vim.split(joined, "\n")) do
      table.insert(out, "> " .. line)
    end
    return table.concat(out, "\n") .. "\n\n"
  elseif t == "panel" then
    local kind = (node.attrs and node.attrs.panelType) or "info"
    return ("\n[!%s] %s\n\n"):format(kind:upper(), joined:gsub("\n+$", ""))
  end
  return joined
end

-- ─── branch ticket detection ──────────────────────────────────────────────
local _branch_cache = { t = 0, branch = nil, cwd = nil }
local function current_branch(cwd)
  local now = vim.uv.now()
  if now - _branch_cache.t < 3000 and _branch_cache.cwd == cwd then
    return _branch_cache.branch
  end
  local res = vim.system({ "git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD" }, { text = true }):wait(500)
  local b = (res.code == 0) and (res.stdout or ""):gsub("%s+$", "") or nil
  _branch_cache = { t = now, branch = (b ~= "" and b) or nil, cwd = cwd }
  return _branch_cache.branch
end

function M.ticket_from_branch(branch)
  if not branch then return nil end
  return branch:match("([A-Z][A-Z0-9]+%-%d+)")
end

function M.current_ticket()
  local cwd = vim.fn.getcwd()
  if _cache.branch_pins[cwd] then return _cache.branch_pins[cwd] end
  return M.ticket_from_branch(current_branch(cwd))
end

function M.pin_ticket(key)
  local cwd = vim.fn.getcwd()
  if key and key ~= "" then _cache.branch_pins[cwd] = key:upper()
  else _cache.branch_pins[cwd] = nil end
  save_cache()
end

-- ─── issue detail float ───────────────────────────────────────────────────
local NS = vim.api.nvim_create_namespace("user_jira")

-- Map Jira's statusCategory.colorName to one of our brand chip highlights.
-- Atlassian's documented colorName values: blue-gray (To Do), yellow (In
-- Progress), green (Done) — older instances also send "warm-red" or "red".
local function chip_group_for_category(color_name)
  if not color_name then return nil end
  color_name = color_name:lower()
  if color_name == "green"            then return "BrandChipOk"   end
  if color_name == "yellow"           then return "BrandChipInfo" end
  if color_name == "blue-gray"
     or color_name == "medium-gray"   then return "BrandChipSurface" end
  if color_name:find("red")           then return "BrandChipErr"  end
  return nil
end

-- Pick a chip highlight group for a status. Prefers Jira's own category
-- color when we have the full status object; falls back to name-heuristic
-- when we only have a name string (search-result rows + statusline chip
-- before the full issue is cached).
local function status_chip_group(status_or_name)
  if type(status_or_name) == "table" then
    local hl = chip_group_for_category(((status_or_name.statusCategory or {}).colorName))
    if hl then return hl end
    status_or_name = status_or_name.name
  end
  local n = (status_or_name or ""):lower()
  if n:find("done") or n:find("closed") or n:find("resolved") then return "BrandChipOk" end
  if n:find("progress") or n:find("review") or n:find("test")  then return "BrandChipInfo" end
  if n:find("block")    or n:find("hold")                       then return "BrandChipErr" end
  return "BrandChipSurface"
end

-- Returns { lines, nav } where nav is row(1-based) -> { kind, key } so that
-- <CR> on a row navigates to that issue.
local function render_issue(buf, data, key)
  local fields    = data.fields or {}
  local status    = (fields.status    or {}).name     or "?"
  local assignee  = (fields.assignee  or {}).displayName or "unassigned"
  local reporter  = (fields.reporter  or {}).displayName or "?"
  local priority  = (fields.priority  or {}).name     or "—"
  local itype     = (fields.issuetype or {}).name     or "—"
  local summary   = fields.summary or "(no summary)"
  local desc_txt  = (fields.description and adf_to_text(fields.description)) or "(no description)"
  desc_txt = desc_txt:gsub("\r", "")

  local lines = {}
  local nav   = {}    -- row → { kind = "issue", key = "..." }
  local ticon = icons.issuetype(itype).icon
  local picon = icons.priority(priority).icon
  table.insert(lines, "")
  table.insert(lines, ("    %s %s    %s"):format(ticon, key, summary))
  table.insert(lines, "")
  table.insert(lines, "     status    " .. status)
  table.insert(lines, ("     type      %s %s      priority  %s %s"):format(ticon, itype, picon, priority))
  table.insert(lines, "     assignee  " .. assignee .. "      reporter  " .. reporter)
  -- parent (epic / story)
  if fields.parent then
    local p = fields.parent
    local pk = p.key or "?"
    local ps = ((p.fields or {}).summary or ""):sub(1, 60)
    table.insert(lines, "     parent    " .. pk .. "  ·  " .. ps)
    nav[#lines] = { kind = "issue", key = pk }
  end
  -- time tracking (when present)
  local tt = fields.timetracking
  if tt and (tt.originalEstimate or tt.timeSpent) then
    table.insert(lines, ("     time      est %s · spent %s · remaining %s"):format(
      tt.originalEstimate or "—",
      tt.timeSpent or "—",
      tt.remainingEstimate or "—"))
  end
  if fields.labels and #fields.labels > 0 then
    table.insert(lines, "     labels    " .. table.concat(fields.labels, ", "))
  end
  table.insert(lines, "")
  table.insert(lines, "    " .. brand.divider(80))
  table.insert(lines, "")
  for _, l in ipairs(vim.split(desc_txt, "\n")) do
    table.insert(lines, "    " .. l)
  end

  -- subtasks
  local subtasks = fields.subtasks or {}
  if #subtasks > 0 then
    table.insert(lines, "")
    table.insert(lines, "    " .. brand.divider(80))
    table.insert(lines, ("    subtasks · %d   (cursor on row · <CR> to open)"):format(#subtasks))
    table.insert(lines, "")
    for _, s in ipairs(subtasks) do
      local sk = s.key or "?"
      local sn = ((s.fields or {}).status or {}).name or ""
      local ss = ((s.fields or {}).summary or ""):sub(1, 60)
      table.insert(lines, ("      ▸ %-10s  [%s]  %s"):format(sk, sn, ss))
      nav[#lines] = { kind = "issue", key = sk }
    end
  end

  -- issue links (blocks / blocked by / relates to)
  local links = fields.issuelinks or {}
  if #links > 0 then
    table.insert(lines, "")
    table.insert(lines, "    " .. brand.divider(80))
    table.insert(lines, ("    links · %d   (cursor on row · <CR> to open)"):format(#links))
    table.insert(lines, "")
    for _, link in ipairs(links) do
      local target = link.outwardIssue or link.inwardIssue
      if target then
        local relation = link.outwardIssue
          and (link.type and link.type.outward) or (link.type and link.type.inward) or "rel"
        local tk = target.key or "?"
        local tn = ((target.fields or {}).status or {}).name or ""
        local ts = ((target.fields or {}).summary or ""):sub(1, 60)
        table.insert(lines, ("      %-14s  %-10s  [%s]  %s"):format(relation, tk, tn, ts))
        nav[#lines] = { kind = "issue", key = tk }
      end
    end
  end

  local comments = ((fields.comment or {}).comments) or {}
  if #comments > 0 then
    table.insert(lines, "")
    table.insert(lines, "    " .. brand.divider(80))
    table.insert(lines, ("    comments · %d"):format(#comments))
    table.insert(lines, "")
    for _, c in ipairs(comments) do
      local who = (c.author or {}).displayName or "?"
      local when = (c.created or ""):sub(1, 16):gsub("T", " ")
      table.insert(lines, "    " .. who .. "  ·  " .. when)
      for _, l in ipairs(vim.split(adf_to_text(c.body) or "", "\n")) do
        if l ~= "" then table.insert(lines, "      " .. l) end
      end
      table.insert(lines, "")
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  -- highlight key + summary (account for ticon glyph prefix)
  local key_col = 4 + #ticon + 1
  pcall(vim.api.nvim_buf_set_extmark, buf, NS, 1, 4,
    { end_col = 4 + #ticon, hl_group = "BrandAccent" })
  pcall(vim.api.nvim_buf_set_extmark, buf, NS, 1, key_col,
    { end_col = key_col + #key, hl_group = "BrandChipAccent" })
  pcall(vim.api.nvim_buf_set_extmark, buf, NS, 1, key_col + #key,
    { end_col = #lines[2], hl_group = "BrandFloatTitle" })
  -- highlight status chip — pass the full status object so we get its
  -- statusCategory color when available, not just a name heuristic
  pcall(vim.api.nvim_buf_set_extmark, buf, NS, 3, 14,
    { end_col = 14 + #status + 1, hl_group = status_chip_group(fields.status) })
  -- muted labels
  for i, line in ipairs(lines) do
    local label = line:match("^%s+([%a]+)%s%s")
    if label and ({ status = 1, type = 1, priority = 1, assignee = 1, reporter = 1,
                    labels = 1, parent = 1, time = 1 })[label] then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, 0,
        { end_col = 4 + #label + 4, hl_group = "BrandMuted" })
    end
    if line:find("^%s+─") then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, 0,
        { end_line = i, hl_group = "BrandMuted" })
    end
    if line:find("^%s+comments · ") or line:find("^%s+subtasks · ") or line:find("^%s+links · ") then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, 0,
        { end_line = i, hl_group = "BrandAccent" })
    end
  end
  return nav
end

function M.show_issue(key)
  if not key or key == "" then
    key = M.current_ticket()
    if not key then
      vim.ui.input({ prompt = "issue key (e.g. ABC-123): " }, function(input)
        if input and input ~= "" then M.show_issue(input:upper()) end
      end)
      return
    end
  end
  key = key:upper()
  local r = brand.win({
    title = "jira · " .. key,
    width = 0.7, height = 0.7, anchor = "center",
  })
  vim.bo[r.buf].modifiable = true
  vim.api.nvim_buf_set_lines(r.buf, 0, -1, false, { "", "    " .. brand.spinner("jira") .. "  loading " .. key .. " …" })
  vim.bo[r.buf].modifiable = false

  M.get_issue(key, function(ok, data)
    if not vim.api.nvim_buf_is_valid(r.buf) then return end
    if not ok then
      vim.bo[r.buf].modifiable = true
      vim.api.nvim_buf_set_lines(r.buf, 0, -1, false, { "", "    error: " .. tostring(data) })
      vim.bo[r.buf].modifiable = false
      return
    end
    local nav = render_issue(r.buf, data, key) or {}
    push_recent(key)
    -- buffer-local actions
    local opts = { buffer = r.buf, silent = true, nowait = true }
    -- <CR> on a related-issue row navigates
    vim.keymap.set("n", "<CR>", function()
      local row = vim.api.nvim_win_get_cursor(r.win)[1]
      local entry = nav[row]
      if entry and entry.kind == "issue" then
        r.close()
        vim.schedule(function() M.show_issue(entry.key) end)
      end
    end, opts)
    vim.keymap.set("n", "o", function() M.open_in_browser(key) end, opts)
    vim.keymap.set("n", "c", function() r.close(); vim.schedule(function() M.prompt_comment(key) end) end, opts)
    vim.keymap.set("n", "t", function() r.close(); vim.schedule(function() M.prompt_transition(key) end) end, opts)
    vim.keymap.set("n", "a", function() r.close(); vim.schedule(function() M.prompt_assignee(key) end) end, opts)
    vim.keymap.set("n", "e", function() r.close(); vim.schedule(function() M.edit_description(key) end) end, opts)
    vim.keymap.set("n", "w", function() r.close(); vim.schedule(function() M.log_work(key) end) end, opts)
    vim.keymap.set("n", "r", function()
      _cache.issues[key] = nil
      r.close(); vim.schedule(function() M.show_issue(key) end)
    end, opts)
  end)
end

-- ─── browser ──────────────────────────────────────────────────────────────
function M.open_in_browser(key)
  local c = ensure_configured(); if not c then return end
  if not key or key == "" then key = M.current_ticket() end
  if not key then brand.notify("no issue key", vim.log.levels.WARN, { title = "jira" }); return end
  vim.ui.open(c.base .. "/browse/" .. key)
end

-- ─── multi-line comment composer ──────────────────────────────────────────
-- Opens a markdown scratch buffer in a centered float. `:w` posts the
-- comment, `:q` (or q in normal mode) cancels. Standard vim verbs — no new
-- keybinds to learn. Buffer name is unique per-key+timestamp so multiple
-- composers can coexist.
function M.prompt_comment(key)
  if not key or key == "" then key = M.current_ticket() end
  if not key then
    vim.ui.input({ prompt = "issue key for comment: " }, function(k)
      if k and k ~= "" then M.prompt_comment(k:upper()) end
    end)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "acwrite"   -- enables BufWriteCmd
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "markdown"
  vim.api.nvim_buf_set_name(buf, "jira-comment://" .. key .. "-" .. os.time())

  local W = math.max(60, math.floor(vim.o.columns * 0.6))
  local H = math.max(10, math.floor(vim.o.lines   * 0.38))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = brand.title("comment · " .. key .. "   :w submit  ·  :q cancel", { glyph = "◆" }),
    title_pos = "left",
    width = W, height = H,
    row = math.floor((vim.o.lines   - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
  pcall(function()
    vim.wo[win].winhighlight = "Normal:BrandFloat,NormalFloat:BrandFloat,FloatBorder:BrandFloatBorder,FloatTitle:BrandFloatTitle"
    vim.wo[win].wrap = true; vim.wo[win].linebreak = true
    vim.wo[win].number = false; vim.wo[win].signcolumn = "no"
  end)
  vim.cmd("startinsert")

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf, once = true,
    callback = function()
      local text = vim.fn.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
      vim.bo[buf].modified = false
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if text == "" then
        brand.notify("comment empty — cancelled", vim.log.levels.WARN, { title = "jira" })
        return
      end
      brand.notify("posting comment …", nil, { title = "jira" })
      M.add_comment(key, text, function(ok, err)
        if ok then
          _cache.issues[key] = nil
          brand.notify("commented on " .. key, nil, { title = "jira" })
        else
          brand.notify("comment failed: " .. tostring(err), vim.log.levels.ERROR, { title = "jira" })
        end
      end)
    end,
  })

  -- normal-mode quick cancel
  vim.keymap.set("n", "q", "<cmd>close<CR>",
    { buffer = buf, silent = true, nowait = true })
end

-- ─── description editor ──────────────────────────────────────────────────
-- Opens the issue's current description in a markdown composer pre-filled
-- with the text we know about. :w PUTs the issue with the new description
-- (wrapped in a single-paragraph ADF doc). Plain-text fidelity only —
-- richer ADF (tables, panels, mixed marks) isn't round-trippable here.
function M.edit_description(key)
  if not key or key == "" then key = M.current_ticket() end
  if not key then brand.notify("no issue key", vim.log.levels.WARN, { title = "jira" }); return end

  -- Fetch fresh (don't trust the cache — the user may be reacting to stale view)
  brand.notify("loading description for " .. key .. " …", nil, { title = "jira" })
  _cache.issues[key] = nil
  M.get_issue(key, function(ok, data)
    if not ok then
      brand.notify("load failed: " .. tostring(data), vim.log.levels.ERROR, { title = "jira" })
      return
    end
    local body_text = (data.fields and adf_to_text(data.fields.description)) or ""
    body_text = body_text:gsub("\r", "")

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype   = "acwrite"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype  = "markdown"
    vim.api.nvim_buf_set_name(buf, "jira-description://" .. key .. "-" .. os.time())
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(body_text, "\n"))

    local W = math.max(72, math.floor(vim.o.columns * 0.7))
    local H = math.max(16, math.floor(vim.o.lines   * 0.6))
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor", style = "minimal", border = "rounded",
      title = brand.title("edit description · " .. key .. "   :w submit  ·  :q cancel",
        { glyph = "◆" }),
      title_pos = "left",
      width = W, height = H,
      row = math.floor((vim.o.lines   - H) / 2),
      col = math.floor((vim.o.columns - W) / 2),
    })
    pcall(function()
      vim.wo[win].winhighlight = "Normal:BrandFloat,NormalFloat:BrandFloat,FloatBorder:BrandFloatBorder,FloatTitle:BrandFloatTitle"
      vim.wo[win].wrap = true; vim.wo[win].linebreak = true
      vim.wo[win].number = false; vim.wo[win].signcolumn = "no"
    end)

    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf, once = true,
      callback = function()
        local text = vim.fn.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
        vim.bo[buf].modified = false
        if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
        brand.notify("updating description …", nil, { title = "jira" })
        M.update_description(key, text, function(uok, err)
          if uok then
            _cache.issues[key] = nil
            brand.notify("description updated · " .. key, nil, { title = "jira" })
          else
            brand.notify("update failed: " .. tostring(err), vim.log.levels.ERROR, { title = "jira" })
          end
        end)
      end,
    })

    vim.keymap.set("n", "q", "<cmd>close<CR>",
      { buffer = buf, silent = true, nowait = true })
  end)
end

-- ─── worklog composer ─────────────────────────────────────────────────────
-- :JiraLog 30m fixed the bug
-- Or interactively: `w` in the issue float prompts duration + optional comment.
-- Jira time format: w=weeks, d=days, h=hours, m=minutes. Mix freely: "2h 15m".
local TIME_PAT = "^%s*[%d.]+%s*[wdhm]"
function M.log_work(key, time_spent, comment_text)
  if not key or key == "" then key = M.current_ticket() end
  if not key then brand.notify("no issue key", vim.log.levels.WARN, { title = "jira" }); return end

  local function go(ts, cmt)
    if not ts or not ts:match(TIME_PAT) then
      brand.notify("invalid time format · use 30m / 2h / 1d 4h / 1w", vim.log.levels.WARN,
        { title = "jira" })
      return
    end
    brand.notify("logging " .. ts .. " on " .. key .. " …", nil, { title = "jira" })
    M.add_worklog(key, ts, cmt, function(ok, err)
      if ok then
        _cache.issues[key] = nil
        brand.notify("logged " .. ts .. " · " .. key, nil, { title = "jira" })
      else
        brand.notify("worklog failed: " .. tostring(err), vim.log.levels.ERROR, { title = "jira" })
      end
    end)
  end

  if time_spent and time_spent ~= "" then return go(time_spent, comment_text) end
  vim.ui.input({ prompt = "log time on " .. key .. " (e.g. 30m, 2h 15m): " }, function(ts)
    if not ts or ts == "" then return end
    vim.ui.input({ prompt = "worklog comment (optional): " }, function(cmt)
      go(ts, cmt or "")
    end)
  end)
end

-- ─── assignee prompt ──────────────────────────────────────────────────────
-- Prompts for a search query (name/email substring), lets you pick from
-- assignable users, then PUTs the new assignee. Empty pick unassigns.
function M.prompt_assignee(key)
  if not key or key == "" then key = M.current_ticket() end
  if not key then brand.notify("no issue key", vim.log.levels.WARN, { title = "jira" }); return end
  vim.ui.input({ prompt = "assignee search (blank = unassign): " }, function(q)
    if q == nil then return end
    if q == "" then
      M.set_assignee(key, vim.NIL, function(ok, err)
        if ok then
          _cache.issues[key] = nil
          brand.notify("unassigned  " .. key, nil, { title = "jira" })
        else
          brand.notify("unassign failed: " .. tostring(err), vim.log.levels.ERROR, { title = "jira" })
        end
      end)
      return
    end
    M.search_assignable(key, q, function(ok, users)
      if not ok then
        brand.notify("user search failed: " .. tostring(users), vim.log.levels.ERROR, { title = "jira" })
        return
      end
      if type(users) ~= "table" or #users == 0 then
        brand.notify("no users matched", nil, { title = "jira" }); return
      end
      local items = vim.tbl_map(function(u)
        return ("%-26s  %s"):format(u.displayName or "?", u.emailAddress or "")
      end, users)
      vim.ui.select(items, { prompt = "assign " .. key .. " to: " }, function(_, idx)
        if not idx then return end
        local pick = users[idx]
        M.set_assignee(key, pick.accountId, function(ok2, err)
          if ok2 then
            _cache.issues[key] = nil
            brand.notify(key .. "  →  " .. (pick.displayName or "?"),
              nil, { title = "jira" })
          else
            brand.notify("assign failed: " .. tostring(err), vim.log.levels.ERROR, { title = "jira" })
          end
        end)
      end)
    end)
  end)
end

-- ─── transition prompt ────────────────────────────────────────────────────
function M.prompt_transition(key)
  if not key or key == "" then key = M.current_ticket() end
  if not key then brand.notify("no issue key", vim.log.levels.WARN, { title = "jira" }); return end
  M.list_transitions(key, function(ok, data)
    if not ok then
      brand.notify("transitions failed: " .. tostring(data), vim.log.levels.ERROR, { title = "jira" })
      return
    end
    local trans = data.transitions or {}
    if #trans == 0 then brand.notify("no transitions available", nil, { title = "jira" }); return end
    local items = vim.tbl_map(function(t)
      return ("%-4s  →  %s"):format(t.id, t.name)
    end, trans)
    vim.ui.select(items, { prompt = "transition " .. key .. " to: " }, function(_, idx)
      if not idx then return end
      local pick = trans[idx]
      M.do_transition(key, pick.id, function(ok2, err)
        if ok2 then
          _cache.issues[key] = nil
          brand.notify(key .. "  →  " .. pick.name, nil, { title = "jira" })
        else
          brand.notify("transition failed: " .. tostring(err), vim.log.levels.ERROR, { title = "jira" })
        end
      end)
    end)
  end)
end

-- ─── native list+preview picker ───────────────────────────────────────────
-- Two coupled floats: an issue list on the left, a live preview on the right.
-- j/k navigates · preview re-renders on CursorMoved · <CR> opens full detail ·
-- o opens in browser · q/Esc closes. Lazy-fetches full descriptions through
-- the same in-memory cache the chip + detail view use.
local function brand_winhl(win)
  pcall(function()
    vim.wo[win].winhighlight = table.concat({
      "Normal:BrandFloat", "NormalFloat:BrandFloat",
      "FloatBorder:BrandFloatBorder", "FloatTitle:BrandFloatTitle",
      "CursorLine:Visual",
    }, ",")
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
  end)
end

-- on_select: optional override called instead of show_issue(key) on <CR>
-- opts table: { on_select(key)?, on_refresh(cb(new_issues))? }
-- Legacy: passing a function as the 3rd arg is treated as on_select.
local function pick_from_search(title, issues, opts)
  if type(opts) == "function" then opts = { on_select = opts } end
  opts = opts or {}
  if not issues or #issues == 0 then
    brand.notify("no results", nil, { title = "jira" }); return
  end

  local cols, lines = vim.o.columns, vim.o.lines
  local W = math.floor(cols * 0.86)
  local H = math.floor(lines * 0.72)
  local list_w = math.max(46, math.floor(W * 0.42))
  local prev_w = W - list_w - 2
  local row = math.floor((lines - H) / 2)
  local col = math.floor((cols - W) / 2)

  local list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].buftype = "nofile"; vim.bo[list_buf].bufhidden = "wipe"
  local list_win = vim.api.nvim_open_win(list_buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = brand.title(title, { glyph = "◆" }), title_pos = "left",
    width = list_w, height = H, row = row, col = col,
  })
  brand_winhl(list_win)
  vim.wo[list_win].cursorline = true

  local prev_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[prev_buf].buftype = "nofile"; vim.bo[prev_buf].bufhidden = "wipe"
  vim.bo[prev_buf].filetype = "markdown"
  local prev_win = vim.api.nvim_open_win(prev_buf, false, {
    relative = "editor", style = "minimal", border = "rounded",
    title = brand.title("preview", { glyph = "◆" }), title_pos = "left",
    width = prev_w, height = H, row = row, col = col + list_w + 2,
  })
  brand_winhl(prev_win)
  vim.wo[prev_win].wrap = true; vim.wo[prev_win].linebreak = true

  -- live filter state — `filtered` is the subset of `issues` actually shown.
  local filter = ""
  local filtered = issues
  local lns = vim.api.nvim_create_namespace("user_jira_picker_" .. list_buf)

  local function apply_filter()
    if filter == "" then
      filtered = issues
    else
      local needle = filter:lower()
      filtered = {}
      for _, it in ipairs(issues) do
        local f = it.fields or {}
        local hay = (it.key .. " " .. ((f.summary or "")) .. " " ..
                     ((f.status or {}).name or "") .. " " ..
                     ((f.assignee or {}).displayName or "")):lower()
        if hay:find(needle, 1, true) then table.insert(filtered, it) end
      end
    end
  end

  local function render_list()
    apply_filter()
    local title_text = title .. (filter ~= "" and ("  ·  filter: " .. filter) or "")
                       .. ("  ·  " .. #filtered .. "/" .. #issues)
    pcall(vim.api.nvim_win_set_config, list_win, { title = brand.title(title_text, { glyph = "◆" }) })
    local rows = {}
    for _, it in ipairs(filtered) do
      local f = it.fields or {}
      local status = ((f.status or {}).name or "?"):sub(1, 14)
      local summ   = ((f.summary or ""):gsub("\n.*", "")):sub(1, list_w - 42)
      local ticon  = icons.issuetype((f.issuetype or {}).name).icon
      local picon  = icons.priority((f.priority or {}).name).icon
      table.insert(rows, string.format(" %s %-12s %s %-14s  %s",
        ticon, it.key, picon, status, summ))
    end
    if #rows == 0 then rows = { "", "    (no matches — press \\ to clear filter)" } end
    vim.bo[list_buf].modifiable = true
    vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, rows)
    vim.bo[list_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(list_buf, lns, 0, -1)
    for i, it in ipairs(filtered) do
      local f = it.fields or {}
      local ticon = icons.issuetype((f.issuetype or {}).name).icon
      local picon = icons.priority((f.priority or {}).name).icon
      -- " " + ticon + " " + %-12s(key) + " " + picon + " " + %-14s(status) + "  " + summ
      local key_start    = 1 + #ticon + 1
      local key_end      = key_start + #it.key
      local status_start = key_start + 12 + 1 + #picon + 1
      local status_obj   = f.status or {}
      local sname        = status_obj.name or ""
      -- icon highlights
      pcall(vim.api.nvim_buf_set_extmark, list_buf, lns, i - 1, 1,
        { end_col = 1 + #ticon, hl_group = "BrandAccent" })
      pcall(vim.api.nvim_buf_set_extmark, list_buf, lns, i - 1, key_end + 1,
        { end_col = key_end + 1 + #picon, hl_group = "BrandAccent" })
      -- key + status chip
      pcall(vim.api.nvim_buf_set_extmark, list_buf, lns, i - 1, key_start,
        { end_col = key_end, hl_group = "BrandAccent" })
      pcall(vim.api.nvim_buf_set_extmark, list_buf, lns, i - 1, status_start,
        { end_col = status_start + math.min(14, #sname), hl_group = status_chip_group(status_obj) })
    end
    if #filtered > 0 then pcall(vim.api.nvim_win_set_cursor, list_win, { 1, 0 }) end
  end
  render_list()

  local render_lock = false
  local function render_preview()
    if render_lock or not vim.api.nvim_buf_is_valid(prev_buf) then return end
    local cur = vim.api.nvim_win_get_cursor(list_win)[1]
    local it = filtered[cur]; if not it then return end
    local f = it.fields or {}
    local out = {
      "",
      "  " .. it.key .. "   " .. (f.summary or ""),
      "",
      "   status    " .. ((f.status or {}).name or "?"),
      "   assignee  " .. ((f.assignee or {}).displayName or "unassigned"),
      "   priority  " .. ((f.priority or {}).name or "—"),
      "   updated   " .. ((f.updated or "—"):sub(1, 16):gsub("T", " ")),
      "",
      "  " .. brand.divider(prev_w - 4),
      "",
    }
    local hit = _cache.issues[it.key]
    if hit and hit.data.fields then
      local desc = adf_to_text(hit.data.fields.description) or ""
      desc = desc:gsub("\r", ""):sub(1, 4000)
      for _, l in ipairs(vim.split(desc, "\n")) do
        table.insert(out, "  " .. l)
      end
      local comments = ((hit.data.fields.comment or {}).comments) or {}
      if #comments > 0 then
        table.insert(out, ""); table.insert(out, "  " .. brand.divider(prev_w - 4))
        table.insert(out, ("  comments · %d"):format(#comments)); table.insert(out, "")
        for _, cm in ipairs(comments) do
          table.insert(out, "  " .. ((cm.author or {}).displayName or "?")
            .. "  ·  " .. (cm.created or ""):sub(1, 16):gsub("T", " "))
          for _, l in ipairs(vim.split(adf_to_text(cm.body) or "", "\n")) do
            if l ~= "" then table.insert(out, "    " .. l) end
          end
          table.insert(out, "")
        end
      end
    else
      table.insert(out, "  " .. brand.spinner("jira_picker") .. "  loading description …")
      M.get_issue(it.key, function(ok)
        if not ok then return end
        if not vim.api.nvim_win_is_valid(list_win) then return end
        if vim.api.nvim_win_get_cursor(list_win)[1] == cur then
          render_preview()   -- re-render now that cache is populated
        end
      end)
    end
    render_lock = true
    vim.bo[prev_buf].modifiable = true
    vim.api.nvim_buf_set_lines(prev_buf, 0, -1, false, out)
    vim.bo[prev_buf].modifiable = false
    render_lock = false
  end
  render_preview()

  local grp = vim.api.nvim_create_augroup("user_jira_picker_" .. list_buf, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = grp, buffer = list_buf, callback = render_preview,
  })

  local function close_all()
    pcall(vim.api.nvim_del_augroup_by_id, grp)
    if vim.api.nvim_win_is_valid(list_win) then vim.api.nvim_win_close(list_win, true) end
    if vim.api.nvim_win_is_valid(prev_win) then vim.api.nvim_win_close(prev_win, true) end
  end
  local function selected_key()
    local r = vim.api.nvim_win_get_cursor(list_win)[1]
    return (filtered[r] or {}).key
  end

  local opts = { buffer = list_buf, silent = true, nowait = true }
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, close_all, opts)
  end
  local on_select  = opts.on_select
  local on_refresh = opts.on_refresh
  local kopts = { buffer = list_buf, silent = true, nowait = true }
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, close_all, kopts)
  end
  local function activate()
    local k = selected_key(); if not k then return end
    close_all()
    if on_select then vim.schedule(function() on_select(k) end)
    else vim.schedule(function() M.show_issue(k) end) end
  end
  vim.keymap.set("n", "<CR>",          activate, kopts)
  vim.keymap.set("n", "<2-LeftMouse>", activate, kopts)   -- double-click executes
  vim.keymap.set("n", "o", function()
    local k = selected_key(); if k then M.open_in_browser(k) end
  end, kopts)
  vim.keymap.set("n", "c", function()
    local k = selected_key(); close_all()
    if k then vim.schedule(function() M.prompt_comment(k) end) end
  end, kopts)
  vim.keymap.set("n", "t", function()
    local k = selected_key(); close_all()
    if k then vim.schedule(function() M.prompt_transition(k) end) end
  end, kopts)
  -- right-click → action menu (cursor follows the click, so single-click first
  -- selects the row; the menu acts on that row)
  vim.keymap.set("n", "<RightMouse>", function()
    vim.cmd("normal! \\<LeftMouse>")
    local k = selected_key(); if not k then return end
    vim.ui.select({
      "open detail", "open in browser", "comment", "transition", "assign", "cancel",
    }, { prompt = k .. ": " }, function(choice)
      if not choice or choice == "cancel" then return end
      if     choice == "open detail"     then close_all(); vim.schedule(function() M.show_issue(k) end)
      elseif choice == "open in browser" then M.open_in_browser(k)
      elseif choice == "comment"         then close_all(); vim.schedule(function() M.prompt_comment(k) end)
      elseif choice == "transition"      then close_all(); vim.schedule(function() M.prompt_transition(k) end)
      elseif choice == "assign"          then close_all(); vim.schedule(function() M.prompt_assignee(k) end)
      end
    end)
  end, kopts)
  -- live filter
  vim.keymap.set("n", "/", function()
    vim.ui.input({ prompt = "filter: ", default = filter }, function(v)
      filter = v or ""
      render_list(); render_preview()
    end)
  end, kopts)
  vim.keymap.set("n", "\\", function()
    filter = ""
    render_list(); render_preview()
  end, kopts)
  -- refresh (re-runs the source query, preserves cursor row)
  if on_refresh then
    vim.keymap.set("n", "R", function()
      local saved_row = vim.api.nvim_win_get_cursor(list_win)[1]
      brand.notify("refreshing …", nil, { title = "jira" })
      on_refresh(function(new_issues)
        if not vim.api.nvim_buf_is_valid(list_buf) then return end
        -- mutate the existing `issues` table in place so render_list sees it
        for k in pairs(issues) do issues[k] = nil end
        for i, v in ipairs(new_issues or {}) do issues[i] = v end
        -- bust per-key memory cache so previews re-fetch fresh data
        for _, it in ipairs(issues) do _cache.issues[it.key] = nil end
        render_list(); render_preview()
        pcall(vim.api.nvim_win_set_cursor, list_win,
          { math.min(saved_row, math.max(1, #filtered)), 0 })
      end)
    end, kopts)
  end
end

function M.show_mine()
  brand.notify("loading your issues …", nil, { title = "jira" })
  M.my_open_issues(function(ok, data)
    if not ok then
      brand.notify("search failed: " .. tostring(data), vim.log.levels.ERROR, { title = "jira" })
      return
    end
    pick_from_search("my open issues", data.issues or {}, {
      on_refresh = function(cb)
        M.my_open_issues(function(rok, rdata) cb(rok and rdata.issues or {}) end)
      end,
    })
  end)
end

-- Decide whether `input` looks like real JQL or freeform text. We treat it
-- as JQL only if it contains one of the structural tokens — any operator
-- (=, !=, ~, <, >), an explicit IN/IS, a parenthesized clause, or a keyword
-- like ORDER BY. Anything else (bare words, multi-word phrases) is wrapped
-- as `text ~ "..."` so the search just works.
local function looks_like_jql(s)
  if s:find("[=~<>]") then return true end
  if s:find("[%(%)]") then return true end
  local up = " " .. s:upper() .. " "
  for _, tok in ipairs({ " IN ", " IS ", " NOT ", " AND ", " OR ", " ORDER BY ", " EMPTY " }) do
    if up:find(tok, 1, true) then return true end
  end
  return false
end

function M.show_search(jql)
  if not jql or jql == "" then
    vim.ui.input({ prompt = "JQL or text: " }, function(q)
      if q and q ~= "" then M.show_search(q) end
    end)
    return
  end

  -- Shortcut: bare issue key (e.g. "XDR-123") → just open the issue.
  local bare_key = jql:match("^%s*([A-Z][A-Z0-9]+%-%d+)%s*$")
  if bare_key then return M.show_issue(bare_key:upper()) end

  -- If it doesn't look like JQL, wrap it as a text search so users can type
  -- plain phrases without learning the query language.
  local query = jql
  if not looks_like_jql(jql) then
    local escaped = jql:gsub('\\', '\\\\'):gsub('"', '\\"')
    query = ('text ~ "%s" ORDER BY updated DESC'):format(escaped)
    brand.notify("(text search) " .. query, nil, { title = "jira" })
  else
    brand.notify("searching …", nil, { title = "jira" })
  end

  M.search(query, function(ok, data)
    if not ok then
      brand.notify("search failed: " .. tostring(data), vim.log.levels.ERROR, { title = "jira" })
      return
    end
    pick_from_search("search", data.issues or {}, {
      on_refresh = function(cb)
        M.search(query, function(rok, rdata) cb(rok and rdata.issues or {}) end, 50)
      end,
    })
  end, 50)
end

-- ─── recently viewed picker ───────────────────────────────────────────────
-- Issues are fetched in parallel, then handed to the standard picker. Keys
-- already in the in-memory cache resolve instantly. Failed fetches drop out
-- silently so the picker still opens for whatever resolved.
-- Fetch the full set of recent issues. cb(issues) on completion (drops keys
-- whose fetches failed). cache_busted = true forces a re-fetch.
local function fetch_recent_issues(cb, cache_busted)
  local keys = _cache.recent or {}
  if #keys == 0 then return cb({}) end
  if cache_busted then
    for _, k in ipairs(keys) do _cache.issues[k] = nil end
  end
  local remaining, results = #keys, {}
  for i, key in ipairs(keys) do
    M.get_issue(key, function(ok, data)
      if ok then results[i] = data end
      remaining = remaining - 1
      if remaining == 0 then
        local out = {}
        for j = 1, #keys do if results[j] then table.insert(out, results[j]) end end
        cb(out)
      end
    end)
  end
end

function M.show_recent()
  local keys = _cache.recent or {}
  if #keys == 0 then
    brand.notify("no recent issues yet · open a ticket first", nil, { title = "jira" })
    return
  end
  brand.notify("loading recent (" .. #keys .. ") …", nil, { title = "jira" })
  fetch_recent_issues(function(issues)
    if #issues == 0 then
      brand.notify("none of the recent issues could be fetched",
        vim.log.levels.WARN, { title = "jira" })
      return
    end
    pick_from_search("recent", issues, {
      on_refresh = function(cb) fetch_recent_issues(cb, true) end,
    })
  end)
end

-- ─── follow JIRA-123 under cursor (any buffer) ────────────────────────────
-- Best-effort key extraction:
--   1. cword exactly matches KEY-NNN → use it
--   2. any KEY-NNN on the current line whose span covers the cursor column
--   3. first KEY-NNN on the current line
--   4. fall back to current_ticket() (the branch's ticket)
local function key_at_cursor()
  local cword = vim.fn.expand("<cword>")
  if cword:match("^[A-Z][A-Z0-9]+%-%d+$") then return cword:upper() end
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1   -- 1-based
  local first
  local s, e = 1, #line
  while s <= e do
    local ms, me, m = line:find("([A-Z][A-Z0-9]+%-%d+)", s)
    if not ms then break end
    first = first or m
    if col >= ms and col <= me then return m:upper() end
    s = me + 1
  end
  if first then return first:upper() end
  return M.current_ticket()
end

function M.peek_under_cursor()
  local key = key_at_cursor()
  if not key then
    brand.notify("no JIRA-NNN under cursor or on current line",
      vim.log.levels.WARN, { title = "jira" })
    return
  end
  M.show_issue(key)
end

-- ─── insert ref at cursor (markdown-aware) ────────────────────────────────
-- Source defaults to "mine"; pass "recent" or pre-fetched issues otherwise.
-- In a markdown buffer (or commit messages), inserts `[KEY](url) summary`.
-- Elsewhere, inserts a bare `KEY`.
function M.insert_ref(source)
  source = source or "mine"
  local fetcher
  if source == "recent" then
    fetcher = function(cb)
      local keys = _cache.recent or {}
      if #keys == 0 then return cb(false, "no recent issues yet") end
      local remaining, results = #keys, {}
      for i, k in ipairs(keys) do
        M.get_issue(k, function(ok, data)
          if ok then results[i] = data end
          remaining = remaining - 1
          if remaining == 0 then
            local out = {}
            for j = 1, #keys do if results[j] then table.insert(out, results[j]) end end
            cb(true, { issues = out })
          end
        end)
      end
    end
  else
    fetcher = function(cb) M.my_open_issues(cb) end
  end

  local c = ensure_configured(); if not c then return end
  -- snapshot caller's window + cursor so we can splice back in after close
  local src_win = vim.api.nvim_get_current_win()
  local src_buf = vim.api.nvim_get_current_buf()
  local src_pos = vim.api.nvim_win_get_cursor(src_win)
  local ft      = vim.bo[src_buf].filetype
  local md_like = (ft == "markdown" or ft == "gitcommit" or ft == "octo" or ft == "asciidoc")

  brand.notify("loading " .. source .. " …", nil, { title = "jira" })
  fetcher(function(ok, data)
    if not ok then
      brand.notify(tostring(data), vim.log.levels.WARN, { title = "jira" }); return
    end
    pick_from_search("insert ref · pick", data.issues or {}, function(key)
      local hit = _cache.issues[key]
      local summ = (hit and ((hit.data.fields or {}).summary)) or ""
      local snippet
      if md_like then
        snippet = ("[%s](%s/browse/%s) %s"):format(key, c.base, key, summ)
      else
        snippet = key
      end
      if not vim.api.nvim_win_is_valid(src_win) then return end
      vim.api.nvim_set_current_win(src_win)
      vim.api.nvim_win_set_cursor(src_win, src_pos)
      vim.api.nvim_put({ snippet }, "c", true, true)
    end)
  end)
end

-- ─── saved JQL filters ────────────────────────────────────────────────────
function M.save_filter(name, jql)
  jql = jql or _cache.last_jql
  if not name or name == "" then
    brand.notify("filter needs a name", vim.log.levels.WARN, { title = "jira" }); return
  end
  if not jql or jql == "" then
    brand.notify("no JQL to save · run :JiraSearch first", vim.log.levels.WARN, { title = "jira" })
    return
  end
  _cache.filters[name] = jql; save_cache()
  brand.notify(("saved filter  %s"):format(name), nil, { title = "jira" })
end

function M.delete_filter(name)
  if not _cache.filters[name] then
    brand.notify("no such filter: " .. tostring(name), vim.log.levels.WARN, { title = "jira" })
    return
  end
  _cache.filters[name] = nil; save_cache()
  brand.notify(("deleted filter  %s"):format(name), nil, { title = "jira" })
end

function M.show_filters()
  local names = vim.tbl_keys(_cache.filters)
  if #names == 0 then
    brand.notify("no saved filters · :JiraSaveFilter <name> after a search",
      nil, { title = "jira" })
    return
  end
  table.sort(names)
  local items = vim.tbl_map(function(n)
    return ("%-20s  %s"):format(n, (_cache.filters[n] or ""):sub(1, 80))
  end, names)
  vim.ui.select(items, { prompt = "saved filters: " }, function(_, idx)
    if not idx then return end
    M.show_search(_cache.filters[names[idx]])
  end)
end

-- ─── project + issue-type discovery (cached) ─────────────────────────────
-- Cached in-memory only; cheap because each call is a single GET. Refresh by
-- closing nvim or calling refresh = true.
local _projects, _issuetypes_by_project = nil, {}

local function fetch_projects(cb, refresh)
  if _projects and not refresh then return cb(true, _projects) end
  request("GET", "/rest/api/3/project/search?maxResults=100&orderBy=lastIssueUpdatedTime", nil,
    function(ok, data)
      if ok then _projects = data.values or {} end
      cb(ok, ok and _projects or data)
    end)
end

local function fetch_issuetypes(project_key_or_id, cb)
  if _issuetypes_by_project[project_key_or_id] then
    return cb(true, _issuetypes_by_project[project_key_or_id])
  end
  request("GET",
    "/rest/api/3/issue/createmeta/" .. url_encode(project_key_or_id) .. "/issuetypes",
    nil,
    function(ok, data)
      if ok then _issuetypes_by_project[project_key_or_id] = data.issueTypes or data.values or {} end
      cb(ok, ok and _issuetypes_by_project[project_key_or_id] or data)
    end)
end

function M.create_issue(payload, cb)
  request("POST", "/rest/api/3/issue", payload, cb)
end

-- ─── :JiraCreate composer ─────────────────────────────────────────────────
-- Flow: project pick → issue-type pick → buffer (first line = summary,
-- blank, then description). :w creates the issue and opens it.
function M.create_flow(default_project)
  if not ensure_configured() then return end
  brand.notify("loading projects …", nil, { title = "jira" })
  fetch_projects(function(ok, projects)
    if not ok then
      brand.notify("projects failed: " .. tostring(projects), vim.log.levels.ERROR, { title = "jira" })
      return
    end
    -- pre-pick the project if a default key matches
    local pre = nil
    for _, p in ipairs(projects) do
      if default_project and (p.key == default_project:upper()) then pre = p end
    end
    local function pick_type_then_open(project)
      brand.notify("loading issue types for " .. project.key .. " …", nil, { title = "jira" })
      fetch_issuetypes(project.key, function(tok, types)
        if not tok then
          brand.notify("types failed: " .. tostring(types), vim.log.levels.ERROR, { title = "jira" })
          return
        end
        local labels = vim.tbl_map(function(t)
          return ("%-14s  %s"):format(t.name, t.description or "")
        end, types)
        vim.ui.select(labels, { prompt = "type for " .. project.key .. ": " }, function(_, idx)
          if not idx then return end
          M._open_create_composer(project, types[idx])
        end)
      end)
    end
    if pre then return pick_type_then_open(pre) end
    local items = vim.tbl_map(function(p) return ("%-8s  %s"):format(p.key, p.name) end, projects)
    vim.ui.select(items, { prompt = "project: " }, function(_, idx)
      if not idx then return end
      pick_type_then_open(projects[idx])
    end)
  end)
end

function M._open_create_composer(project, itype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype   = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "markdown"
  vim.api.nvim_buf_set_name(buf, "jira-create://" .. project.key .. "-" .. os.time())

  -- The buffer convention: line 1 = summary, line 2 blank, lines 3+ = body.
  -- Header line stays in the buffer so the user can see + edit it normally.
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "(summary on this line)", "",
    "<!-- write the description below this line · markdown OK · :w submits -->",
    "",
  })

  local W = math.max(64, math.floor(vim.o.columns * 0.7))
  local H = math.max(14, math.floor(vim.o.lines   * 0.55))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "rounded",
    title = brand.title("create · " .. project.key .. " · " .. itype.name
      .. "   :w submit · :q cancel", { glyph = "◆" }),
    title_pos = "left",
    width = W, height = H,
    row = math.floor((vim.o.lines   - H) / 2),
    col = math.floor((vim.o.columns - W) / 2),
  })
  pcall(function()
    vim.wo[win].winhighlight = "Normal:BrandFloat,NormalFloat:BrandFloat,FloatBorder:BrandFloatBorder,FloatTitle:BrandFloatTitle"
    vim.wo[win].wrap = true; vim.wo[win].linebreak = true
  end)
  -- jump to summary line and select-all so first keystroke replaces placeholder
  vim.api.nvim_win_set_cursor(win, { 1, 0 })
  vim.cmd("normal! V")
  vim.cmd("normal! \27")   -- exit visual; cursor still on line 1

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf, once = true,
    callback = function()
      local lines   = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local summary = vim.fn.trim(lines[1] or "")
      -- description: skip placeholder header lines (<!-- … --> + blanks)
      local body_lines = {}
      for i = 2, #lines do
        local l = lines[i] or ""
        if not l:match("^%s*<!%-%-") then table.insert(body_lines, l) end
      end
      local description = vim.fn.trim(table.concat(body_lines, "\n"))

      vim.bo[buf].modified = false
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end

      if summary == "" or summary == "(summary on this line)" then
        brand.notify("summary is required", vim.log.levels.WARN, { title = "jira" })
        return
      end

      local payload = {
        fields = {
          project   = { key = project.key },
          summary   = summary,
          issuetype = { id = itype.id },
        },
      }
      if description ~= "" then
        payload.fields.description = {
          type = "doc", version = 1,
          content = { { type = "paragraph", content = { { type = "text", text = description } } } },
        }
      end
      brand.notify("creating issue …", nil, { title = "jira" })
      M.create_issue(payload, function(ok, data)
        if not ok then
          brand.notify("create failed: " .. tostring(data), vim.log.levels.ERROR, { title = "jira" })
          return
        end
        local new_key = data.key
        brand.notify("created  " .. new_key, nil, { title = "jira" })
        vim.schedule(function() M.show_issue(new_key) end)
      end)
    end,
  })

  vim.keymap.set("n", "q", "<cmd>close<CR>",
    { buffer = buf, silent = true, nowait = true })
end

-- ─── inline KEY-NNN chip decoration (any buffer) ─────────────────────────
-- Every JIRA-NNN occurrence in any normal-text buffer lights up as a brand
-- chip. Color reflects the cached status if we've fetched the issue (else
-- neutral). Driven by a decoration provider so it only runs for lines that
-- are actually rendered — cheap on big files.
--
-- Skip rules:
--   • non-file buftypes (terminals, prompts, our own floats)
--   • filetypes obviously not text-bearing (help, qf, lazy panels, etc.)
--   • lines > 2000 chars (likely minified)
local CHIP_NS = vim.api.nvim_create_namespace("user_jira_inline_chips")
local CHIP_PAT = "([A-Z][A-Z0-9]+%-%d+)"
local CHIP_SKIP_FT = {
  help = 1, qf = 1, ["neo-tree"] = 1, lazy = 1, mason = 1,
  ["TelescopePrompt"] = 1, NvimTree = 1, dashboard = 1,
  starter = 1, snacks_dashboard = 1, alpha = 1, terminal = 1,
}

local function chip_should_decorate(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return false end
  local bt = vim.bo[bufnr].buftype
  if bt == "terminal" or bt == "prompt" or bt == "quickfix" then return false end
  if CHIP_SKIP_FT[vim.bo[bufnr].filetype] then return false end
  return true
end

local function chip_hl_for(key)
  local hit = _cache.issues[key]
  if hit and hit.data.fields and hit.data.fields.status then
    return status_chip_group(hit.data.fields.status)
  end
  return "BrandChipSurface"
end

function M._setup_chip_decoration()
  vim.api.nvim_set_decoration_provider(CHIP_NS, {
    on_win = function(_, _, bufnr) return chip_should_decorate(bufnr) end,
    on_line = function(_, _, bufnr, row)
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if not line or #line == 0 or #line > 2000 then return end
      local s = 1
      while s <= #line do
        local ms, me, m = line:find(CHIP_PAT, s)
        if not ms then break end
        pcall(vim.api.nvim_buf_set_extmark, bufnr, CHIP_NS, row, ms - 1, {
          end_col = me, hl_group = chip_hl_for(m:upper()), ephemeral = true,
        })
        s = me + 1
      end
    end,
  })
end

-- ─── statusline chip (for user.starship) ──────────────────────────────────
-- Returns a segment table {text, fg, bg, gui} or nil. Cheap: only reads the
-- in-memory cache + branch parse (no HTTP). When the user opens a ticket the
-- cache populates and the chip lights up with the status.
function M.statusline_segment(colors)
  local key = M.current_ticket()
  if not key then return nil end
  local hit = _cache.issues[key]
  local status_obj = hit and ((hit.data.fields or {}).status)
  local sname = status_obj and status_obj.name or nil
  local text = sname and (" " .. key .. " · " .. sname .. " ") or (" " .. key .. " ")
  local bg = colors and colors.surface or "#313244"
  -- Prefer Jira's statusCategory color when we have the object; fall back
  -- to a name heuristic for legacy/uncached cases.
  local cat = status_obj and ((status_obj.statusCategory or {}).colorName)
  if cat then
    cat = cat:lower()
    if cat == "green" then bg = colors and colors.green or "#a6e3a1"
    elseif cat == "yellow" then bg = colors and colors.sapphire or "#74c7ec"
    elseif cat == "blue-gray" or cat == "medium-gray" then bg = colors and colors.surface or "#313244"
    elseif cat:find("red") then bg = colors and colors.red or "#f38ba8"
    end
  elseif sname then
    local s = sname:lower()
    if s:find("done") or s:find("closed") or s:find("resolved") then bg = colors and colors.green or "#a6e3a1"
    elseif s:find("progress") or s:find("review") or s:find("test") then bg = colors and colors.sapphire or "#74c7ec"
    elseif s:find("block") or s:find("hold") then bg = colors and colors.red or "#f38ba8"
    end
  end
  local fg = colors and colors.base or "#1e1e2e"
  return { text = text, fg = fg, bg = bg, gui = "bold" }
end

-- ─── setup ────────────────────────────────────────────────────────────────
function M.setup()
  load_cache()
  M._setup_chip_decoration()

  vim.api.nvim_create_user_command("JiraIssue",
    function(a) M.show_issue(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Show a Jira issue (KEY or current branch)" })
  vim.api.nvim_create_user_command("JiraMine",       M.show_mine,
    { desc = "Pick from issues assigned to you" })
  vim.api.nvim_create_user_command("JiraSearch",
    function(a) M.show_search(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "JQL search" })
  vim.api.nvim_create_user_command("JiraOpen",
    function(a) M.open_in_browser(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Open issue in browser (KEY or current branch)" })
  vim.api.nvim_create_user_command("JiraComment",
    function(a) M.prompt_comment(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Comment on an issue" })
  vim.api.nvim_create_user_command("JiraTransition",
    function(a) M.prompt_transition(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Move issue to a different status" })
  vim.api.nvim_create_user_command("JiraBranch",
    function(a) M.pin_ticket(a.args); brand.notify(
      a.args ~= "" and ("pinned " .. a.args:upper() .. " to " .. vim.fn.getcwd())
                    or ("unpinned · " .. vim.fn.getcwd()),
      nil, { title = "jira" })
    end,
    { nargs = "?", desc = "Pin a ticket key to this cwd (overrides branch parse)" })

  vim.api.nvim_create_user_command("JiraRecent",     M.show_recent,
    { desc = "Pick from recently viewed issues" })
  vim.api.nvim_create_user_command("JiraPeek",       M.peek_under_cursor,
    { desc = "Open the JIRA-NNN under the cursor (or on current line)" })
  vim.api.nvim_create_user_command("JiraInsert",
    function(a) M.insert_ref(a.args ~= "" and a.args or "mine") end,
    { nargs = "?", complete = function() return { "mine", "recent" } end,
      desc = "Pick + insert an issue reference at cursor (md-aware)" })
  vim.api.nvim_create_user_command("JiraFilters",    M.show_filters,
    { desc = "Pick from saved JQL filters and run" })
  vim.api.nvim_create_user_command("JiraSaveFilter",
    function(a)
      if a.args == "" then
        vim.ui.input({ prompt = "filter name: " }, function(n)
          if n and n ~= "" then M.save_filter(n) end
        end)
      else
        M.save_filter(a.args)
      end
    end,
    { nargs = "?", desc = "Save the most recent JQL as a named filter" })
  vim.api.nvim_create_user_command("JiraDeleteFilter",
    function(a) M.delete_filter(a.args) end,
    { nargs = 1, complete = function() return vim.tbl_keys(_cache.filters or {}) end,
      desc = "Delete a saved filter" })

  vim.api.nvim_create_user_command("JiraCreate",
    function(a) M.create_flow(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Create a new issue (optionally pre-pick project KEY)" })
  vim.api.nvim_create_user_command("JiraAssign",
    function(a) M.prompt_assignee(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Assign an issue (KEY or current branch)" })

  vim.api.nvim_create_user_command("JiraEdit",
    function(a) M.edit_description(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Edit issue description (KEY or current branch)" })
  vim.api.nvim_create_user_command("JiraLog",
    function(a)
      local time_spent, comment = a.args:match("^(%S+)%s*(.*)$")
      M.log_work(nil, time_spent, comment)
    end,
    { nargs = "*", desc = "Log work on the current ticket · :JiraLog 30m [comment]" })
end

return M
