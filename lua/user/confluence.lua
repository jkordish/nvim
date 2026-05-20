-- Confluence: native Atlassian Cloud REST client + reading-pane buffer.
--
-- Shares Jira's env vars: JIRA_BASE_URL + JIRA_USER_EMAIL + JIRA_API_TOKEN.
-- For Atlassian Cloud, Confluence lives at <site>/wiki/api/v2/...
--
-- Surfaces:
--   :ConfluenceSearch <text>   CQL search (or free text → text~"…" auto-wrap)
--   :ConfluencePage <id|url>   fetch & render a page
--   :ConfluenceRecent          recent pages you've worked on
local M = {}

local brand = require("user.brand")

-- ─── persistent cache (recent pages) ──────────────────────────────────────
local CACHE_FILE = vim.fn.stdpath("state") .. "/confluence_cache.json"
local RECENT_CAP = 25
local _cache = { recent = {} }  -- list of { id, title, ts }, most-recent first

local function load_cache()
  local f = io.open(CACHE_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a")); f:close()
  if ok and type(parsed) == "table" then _cache.recent = parsed.recent or {} end
end

local function save_cache()
  vim.fn.mkdir(vim.fn.fnamemodify(CACHE_FILE, ":h"), "p")
  local f = io.open(CACHE_FILE, "w")
  if f then f:write(vim.json.encode({ recent = _cache.recent })); f:close() end
end

local function push_recent(id, title)
  if not id then return end
  id = tostring(id)
  local out = { { id = id, title = title or "(untitled)", ts = os.time() } }
  for _, r in ipairs(_cache.recent) do
    if r.id ~= id and #out < RECENT_CAP then table.insert(out, r) end
  end
  _cache.recent = out; save_cache()
end

-- ─── shared config & auth (reuse jira module's setup) ─────────────────────
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
    brand.notify("set JIRA_BASE_URL / JIRA_USER_EMAIL / JIRA_API_TOKEN",
      vim.log.levels.WARN, { title = "confluence" })
    return nil
  end
  return c
end

local function b64(data)
  local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  local i = 1
  while i <= #data do
    local a, bb, cc = data:byte(i, i + 2)
    bb = bb or 0; cc = cc or 0
    local n = a * 65536 + bb * 256 + cc
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

local function url_encode(s)
  return (s:gsub("([^%w%-_%.~])", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function request(method, path, body, cb)
  local c = ensure_configured(); if not c then return end
  local url = c.base .. "/wiki" .. path
  local args = {
    "curl", "-sS", "-X", method,
    "-H", "Authorization: Basic " .. b64(c.email .. ":" .. c.token),
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
        cb(false, "curl error: " .. (res.stderr or ""), 0); return
      end
      local raw = res.stdout or ""
      local status = tonumber(raw:match("__HTTPSTATUS__(%d+)%s*$") or "0") or 0
      local payload = raw:gsub("\n?__HTTPSTATUS__%d+%s*$", "")
      if status >= 200 and status < 300 then
        local ok, parsed = pcall(vim.json.decode, payload, { luanil = { object = true, array = true } })
        cb(ok, ok and parsed or ("bad JSON: " .. payload:sub(1, 200)), status)
      else
        cb(false, ("HTTP %d · %s"):format(status, payload:sub(1, 300)), status)
      end
    end)
  end)
end

-- ─── API wrappers ─────────────────────────────────────────────────────────
function M.search(cql, cb, limit)
  -- v1 CQL endpoint is still the canonical search surface
  request("GET",
    "/rest/api/search?cql=" .. url_encode(cql) .. "&limit=" .. (limit or 25),
    nil, cb)
end

function M.get_page(page_id, cb)
  -- v2 page with storage body
  request("GET",
    "/api/v2/pages/" .. url_encode(page_id) .. "?body-format=storage",
    nil, cb)
end

-- v1 still has the richest ancestors response (ordered top → leaf, each with
-- id+title). v2 only exposes parentId, requiring an N-deep walk.
function M.get_ancestors(page_id, cb)
  request("GET",
    "/rest/api/content/" .. url_encode(page_id) .. "?expand=ancestors",
    nil, cb)
end

function M.get_children(page_id, cb)
  request("GET",
    "/rest/api/content/" .. url_encode(page_id)
      .. "/child/page?limit=50&expand=",
    nil, cb)
end

-- ─── storage-format (HTML-ish) → plain text ───────────────────────────────
-- Confluence "storage" is HTML + AC custom tags. We render conservatively:
-- block tags become newlines, headings get prefixes, list items get bullets.
local function html_to_text(html)
  if not html or html == "" then return "" end
  local s = html
  -- normalize newlines first
  s = s:gsub("\r\n", "\n")

  -- decode common entities
  local entities = {
    ["&nbsp;"]  = " ",  ["&amp;"]   = "&",  ["&lt;"]    = "<",
    ["&gt;"]    = ">",  ["&quot;"]  = '"',  ["&#39;"]   = "'",
    ["&apos;"]  = "'",  ["&mdash;"] = "—",  ["&ndash;"] = "–",
    ["&hellip;"]= "…",
  }
  s = s:gsub("&[%w#]+;", function(e) return entities[e] or e end)

  -- headings
  s = s:gsub("<h1[^>]*>(.-)</h1>", "\n\n# %1\n")
  s = s:gsub("<h2[^>]*>(.-)</h2>", "\n\n## %1\n")
  s = s:gsub("<h3[^>]*>(.-)</h3>", "\n\n### %1\n")
  s = s:gsub("<h4[^>]*>(.-)</h4>", "\n\n#### %1\n")

  -- list items → bullets (do these BEFORE stripping <li>)
  s = s:gsub("<li[^>]*>(.-)</li>", "\n  • %1")

  -- code blocks (ac:structured-macro for code becomes a CDATA-ish blob;
  -- best-effort: just keep their text body)
  s = s:gsub("<pre[^>]*>(.-)</pre>",        function(body) return "\n\n    " .. body:gsub("\n", "\n    ") .. "\n" end)
  s = s:gsub("<code[^>]*>(.-)</code>",      "`%1`")

  -- links: <a href="X">Y</a> → Y (X)
  s = s:gsub('<a[^>]*href="([^"]+)"[^>]*>(.-)</a>', "%2 (%1)")

  -- emphasis (lightweight)
  s = s:gsub("<strong[^>]*>(.-)</strong>", "**%1**")
  s = s:gsub("<b[^>]*>(.-)</b>",           "**%1**")
  s = s:gsub("<em[^>]*>(.-)</em>",         "*%1*")
  s = s:gsub("<i[^>]*>(.-)</i>",           "*%1*")

  -- paragraph + line break
  s = s:gsub("<p[^>]*>",  "\n\n")
  s = s:gsub("</p>",       "")
  s = s:gsub("<br[^>]*>", "\n")
  s = s:gsub("<hr[^>]*>", "\n\n---\n\n")

  -- strip remaining tags (including ac:* and ri:*)
  s = s:gsub("<[^>]+>", "")

  -- collapse 3+ blank lines into 2
  s = s:gsub("\n\n\n+", "\n\n")
  s = s:gsub("^%s+", "")

  return s
end

-- ─── render page in a scratch buffer (with breadcrumb + children) ────────
local NAV_NS = vim.api.nvim_create_namespace("user_confluence_nav")

-- Render the full page buffer. ancestors/children may be nil if their fetch
-- hasn't returned yet; the buffer re-renders when they arrive.
local function render_page(page, c, ancestors, children, nav_map)
  local title = page.title or "(untitled)"
  local id    = tostring(page.id or "?")
  local body  = ((page.body or {}).storage or {}).value or ""
  local text  = html_to_text(body)

  -- nav_map: line number (1-based) -> { id = "...", title = "..." } so that
  -- <CR> on a breadcrumb/child row can navigate. We rebuild it every render.
  local nav = {}

  local lines = {}
  table.insert(lines, "")

  -- breadcrumb (rendered when ancestors are loaded)
  if ancestors and #ancestors > 0 then
    local crumbs = {}
    for _, a in ipairs(ancestors) do
      table.insert(crumbs, a.title or "(?)")
    end
    table.insert(lines, "    " .. table.concat(crumbs, "  ›  ") .. "  ›  " .. title)
    nav[#lines] = { kind = "breadcrumb", ancestors = ancestors }
    table.insert(lines, "")
  end

  table.insert(lines, "    # " .. title)
  table.insert(lines, "")
  if c then
    table.insert(lines, "    " .. c.base .. "/wiki/spaces/_/pages/" .. id)
    table.insert(lines, "")
  end
  table.insert(lines, "    " .. brand.divider(80))
  table.insert(lines, "")
  for _, line in ipairs(vim.split(text, "\n")) do
    table.insert(lines, "    " .. line)
  end

  -- children footer (rendered when children are loaded and non-empty)
  if children and #children > 0 then
    table.insert(lines, "")
    table.insert(lines, "    " .. brand.divider(80))
    table.insert(lines, ("    child pages · %d   (cursor on a row · <CR> to open)"):format(#children))
    table.insert(lines, "")
    for _, ch in ipairs(children) do
      table.insert(lines, "      ▸ " .. (ch.title or "(?)"))
      nav[#lines] = { kind = "child", id = tostring(ch.id), title = ch.title }
    end
  end

  if nav_map then
    -- preserve the existing buffer if we already have one, just refresh contents
    local buf = nav_map.buf
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      vim.api.nvim_buf_clear_namespace(buf, NAV_NS, 0, -1)
      nav_map.nav = nav
      nav_map.lines = lines
      -- highlight nav rows
      for lnum, entry in pairs(nav) do
        local hl = entry.kind == "child" and "BrandAccent" or "BrandMuted"
        pcall(vim.api.nvim_buf_set_extmark, buf, NAV_NS, lnum - 1, 0,
          { end_line = lnum, hl_group = hl })
      end
      return
    end
  end

  -- first render: open in a tab
  local buf = vim.api.nvim_create_buf(true, true)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype  = "markdown"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf,
    "confluence://" .. id .. "/" .. title:gsub("[^%w]+", "-"))

  vim.cmd("tabnew")
  vim.api.nvim_set_current_buf(buf)
  vim.wo.wrap = true; vim.wo.linebreak = true

  -- stash nav state on the buffer
  local state = { buf = buf, nav = nav, lines = lines }
  vim.b[buf]._confluence_state = true
  -- highlight nav rows
  for lnum, entry in pairs(nav) do
    local hl = entry.kind == "child" and "BrandAccent" or "BrandMuted"
    pcall(vim.api.nvim_buf_set_extmark, buf, NAV_NS, lnum - 1, 0,
      { end_line = lnum, hl_group = hl })
  end

  vim.keymap.set("n", "q", "<cmd>tabclose<CR>", { buffer = buf, silent = true })
  vim.keymap.set("n", "o", function()
    if c then vim.ui.open(c.base .. "/wiki/spaces/_/pages/" .. id) end
  end, { buffer = buf, silent = true })
  -- <CR> on a nav row navigates
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local entry = state.nav[row]
    if not entry then return end
    if entry.kind == "child" then
      vim.cmd("tabclose"); vim.schedule(function() M.show_page(entry.id) end)
    elseif entry.kind == "breadcrumb" then
      -- pick which ancestor to go to: prompt
      local items = vim.tbl_map(function(a) return a.title or "(?)" end, entry.ancestors)
      vim.ui.select(items, { prompt = "go to ancestor: " }, function(_, idx)
        if not idx then return end
        local a = entry.ancestors[idx]
        vim.cmd("tabclose"); vim.schedule(function() M.show_page(a.id) end)
      end)
    end
  end, { buffer = buf, silent = true })

  return state
end

-- ─── public commands ──────────────────────────────────────────────────────
local function parse_page_id(input)
  -- direct id (digits) or any pageId=NNN in a URL or trailing /pages/NNN/
  if input:match("^%d+$") then return input end
  return input:match("pageId=(%d+)") or input:match("/pages/(%d+)")
end

function M.show_page(input)
  if not input or input == "" then
    vim.ui.input({ prompt = "page id or URL: " }, function(v)
      if v and v ~= "" then M.show_page(v) end
    end)
    return
  end
  local id = parse_page_id(input)
  if not id then
    brand.notify("could not parse a page id from input", vim.log.levels.WARN, { title = "confluence" })
    return
  end
  brand.notify("loading page " .. id .. " …", nil, { title = "confluence" })
  local c = ensure_configured()

  -- Fire all three fetches in parallel. We hold their results in shared
  -- locals so completion order doesn't matter; the buffer opens on page
  -- arrival, then re-renders whenever ancestors/children land afterward.
  local got = { page = nil, ancestors = nil, children = nil, state = nil }
  local function rerender()
    if not got.page then return end
    if got.state then
      render_page(got.page, c, got.ancestors, got.children, got.state)
    else
      got.state = render_page(got.page, c, got.ancestors, got.children)
    end
  end
  M.get_page(id, function(ok, page)
    if not ok then
      brand.notify("page failed: " .. tostring(page), vim.log.levels.ERROR, { title = "confluence" })
      return
    end
    push_recent(id, page.title)
    got.page = page; rerender()
  end)
  M.get_ancestors(id, function(ok, data)
    if ok then got.ancestors = data.ancestors or {}; rerender() end
  end)
  M.get_children(id, function(ok, data)
    if ok then got.children = data.results or {}; rerender() end
  end)
end

function M.show_search(query)
  if not query or query == "" then
    vim.ui.input({ prompt = "search (CQL or plain text): " }, function(q)
      if q and q ~= "" then M.show_search(q) end
    end)
    return
  end
  local cql = query
  -- Heuristic: if no operator looks present, treat as text search.
  if not query:find("=") and not query:find("~") then
    cql = ('text ~ "%s" ORDER BY lastmodified DESC'):format(query:gsub('"', '\\"'))
  end
  brand.notify("searching confluence …", nil, { title = "confluence" })
  M.search(cql, function(ok, data)
    if not ok then
      brand.notify("search failed: " .. tostring(data), vim.log.levels.ERROR, { title = "confluence" })
      return
    end
    local results = data.results or {}
    if #results == 0 then
      brand.notify("no results", nil, { title = "confluence" }); return
    end
    local items, ids = {}, {}
    for _, r in ipairs(results) do
      local content = r.content or {}
      local title = (content.title or r.title or "(untitled)"):gsub("@@@hl@@@", ""):gsub("@@@endhl@@@", "")
      local typ = content.type or "—"
      table.insert(items, ("%-8s  %s"):format(typ, title:sub(1, 80)))
      table.insert(ids,   content.id or r.id)
    end
    vim.ui.select(items, { prompt = "confluence · pick: " }, function(_, idx)
      if not idx then return end
      M.show_page(ids[idx])
    end)
  end)
end

-- ─── recently viewed (persisted) ──────────────────────────────────────────
-- Was previously a CQL "modified in last 7 days" query; now backed by the
-- pages YOU actually opened. The CQL flavor lives at :ConfluenceRecentEdits.
function M.show_recent()
  if #_cache.recent == 0 then
    brand.notify("no recent pages yet · open one first", nil, { title = "confluence" })
    return
  end
  local items = {}
  for _, r in ipairs(_cache.recent) do
    table.insert(items, ("%-12s  %s"):format(r.id, (r.title or "(untitled)"):sub(1, 80)))
  end
  vim.ui.select(items, { prompt = "recent confluence pages: " }, function(_, idx)
    if not idx then return end
    M.show_page(_cache.recent[idx].id)
  end)
end

function M.show_recent_edits()
  -- The CQL flavor — what changed across the wiki recently, regardless of you.
  M.show_search('lastmodified > now("-7d") AND type = "page" ORDER BY lastmodified DESC')
end

-- ─── insert page ref at cursor (md-aware) ─────────────────────────────────
-- Source = "recent" (default · cheap, persistent) or "search" (prompt for CQL).
function M.insert_ref(source)
  source = source or "recent"
  local c = ensure_configured(); if not c then return end
  local src_win = vim.api.nvim_get_current_win()
  local src_buf = vim.api.nvim_get_current_buf()
  local src_pos = vim.api.nvim_win_get_cursor(src_win)
  local ft      = vim.bo[src_buf].filetype
  local md_like = (ft == "markdown" or ft == "gitcommit" or ft == "octo" or ft == "asciidoc")

  local function do_insert(id, title)
    local url = c.base .. "/wiki/spaces/_/pages/" .. id
    local snippet
    if md_like then
      snippet = ("[%s](%s)"):format(title or "page", url)
    else
      snippet = (title or "page") .. " (" .. url .. ")"
    end
    if not vim.api.nvim_win_is_valid(src_win) then return end
    vim.api.nvim_set_current_win(src_win)
    vim.api.nvim_win_set_cursor(src_win, src_pos)
    vim.api.nvim_put({ snippet }, "c", true, true)
  end

  if source == "search" then
    vim.ui.input({ prompt = "search (CQL or plain text): " }, function(q)
      if not q or q == "" then return end
      local cql = q
      if not q:find("=") and not q:find("~") then
        cql = ('text ~ "%s" ORDER BY lastmodified DESC'):format(q:gsub('"', '\\"'))
      end
      M.search(cql, function(ok, data)
        if not ok then
          brand.notify("search failed: " .. tostring(data), vim.log.levels.ERROR, { title = "confluence" })
          return
        end
        local results = data.results or {}
        if #results == 0 then brand.notify("no results", nil, { title = "confluence" }); return end
        local items, picks = {}, {}
        for _, r in ipairs(results) do
          local content = r.content or {}
          local title = (content.title or r.title or "(untitled)"):gsub("@@@hl@@@", ""):gsub("@@@endhl@@@", "")
          table.insert(items, ("%-8s  %s"):format(content.type or "—", title:sub(1, 80)))
          table.insert(picks, { id = content.id or r.id, title = title })
        end
        vim.ui.select(items, { prompt = "insert ref · pick: " }, function(_, idx)
          if not idx then return end
          do_insert(picks[idx].id, picks[idx].title)
        end)
      end)
    end)
  else
    if #_cache.recent == 0 then
      brand.notify("no recent pages · open one first or use :ConfluenceInsert search",
        vim.log.levels.WARN, { title = "confluence" })
      return
    end
    local items = {}
    for _, r in ipairs(_cache.recent) do
      table.insert(items, ("%-12s  %s"):format(r.id, (r.title or "(untitled)"):sub(1, 80)))
    end
    vim.ui.select(items, { prompt = "insert ref · pick: " }, function(_, idx)
      if not idx then return end
      do_insert(_cache.recent[idx].id, _cache.recent[idx].title)
    end)
  end
end

-- ─── setup ────────────────────────────────────────────────────────────────
function M.setup()
  load_cache()
  vim.api.nvim_create_user_command("ConfluenceSearch",
    function(a) M.show_search(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Search Confluence (CQL or plain text)" })
  vim.api.nvim_create_user_command("ConfluencePage",
    function(a) M.show_page(a.args ~= "" and a.args or nil) end,
    { nargs = "?", desc = "Fetch + render a Confluence page (id or URL)" })
  vim.api.nvim_create_user_command("ConfluenceRecent", M.show_recent,
    { desc = "Recently viewed pages (yours)" })
  vim.api.nvim_create_user_command("ConfluenceRecentEdits", M.show_recent_edits,
    { desc = "Recently modified pages (across the wiki)" })
  vim.api.nvim_create_user_command("ConfluenceInsert",
    function(a) M.insert_ref(a.args ~= "" and a.args or "recent") end,
    { nargs = "?", complete = function() return { "recent", "search" } end,
      desc = "Pick + insert a page ref at cursor (md-aware)" })
end

return M
