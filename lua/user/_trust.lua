-- Trust-on-first-use for project-local Lua files (.suggest.lua / .preflight.lua).
-- Mirrors vim's `exrc`/`secure` model: prompt the user once per (path, content
-- sha256); if either changes, re-prompt. Persisted at
-- ~/.local/state/nvim/exec_trust.json.
--
-- Public:
--   trust.dofile_if_trusted(path, opts) -> (result, err)
--     result = whatever the file's chunk returned (typically a table), or nil
--     err    = string when the file is unreadable / chunk failed / not a table.
--              nil err + nil result = user declined the prompt.
--   trust.list()           -> { { path, sha, trusted_at }, ... }
--   trust.forget(path)     -> boolean removed
--   trust.setup()          -> registers :NvimTrustList / :NvimTrustForget
local M = {}

local STORE_PATH = vim.fn.stdpath("state") .. "/exec_trust.json"

local function brand_notify(msg, level, opts)
  local ok, brand = pcall(require, "user.brand")
  if ok and brand and brand.notify then
    brand.notify(msg, level, opts)
  else
    vim.notify(msg, level)
  end
end

-- ─── store I/O (atomic write) ─────────────────────────────────────────────
local _cache = nil

local function load_store()
  if _cache then return _cache end
  local f = io.open(STORE_PATH, "r")
  if not f then _cache = {}; return _cache end
  local raw = f:read("*a"); f:close()
  local ok, decoded = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  _cache = (ok and type(decoded) == "table") and decoded or {}
  return _cache
end

local function save_store(store)
  _cache = store
  local tmp = STORE_PATH .. ".tmp." .. vim.fn.getpid()
  local f, err = io.open(tmp, "w")
  if not f then
    brand_notify("trust: cannot write store: " .. tostring(err), vim.log.levels.ERROR, { title = "trust" })
    return false
  end
  f:write(vim.json.encode(store))
  f:close()
  local ok = os.rename(tmp, STORE_PATH)
  if not ok then os.remove(tmp) end
  return ok
end

-- ─── helpers ──────────────────────────────────────────────────────────────
local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a"); f:close()
  return content
end

local function shorten(path)
  local cwd = vim.fn.getcwd()
  if path:sub(1, #cwd) == cwd then return "." .. path:sub(#cwd + 1) end
  local home = vim.env.HOME or ""
  if home ~= "" and path:sub(1, #home) == home then return "~" .. path:sub(#home + 1) end
  return path
end

-- ─── core ─────────────────────────────────────────────────────────────────
-- Caller-supplied callback invoked synchronously when the user has decided.
-- vim.ui.select can be async (e.g. fzf-lua handler), so we route the dofile
-- itself through the callback to keep ordering correct.
local function prompt_and_run(path, sha, content, label, changed, on_result)
  local prompt_title = changed
    and (label .. ": contents changed since last trust — review before trusting")
    or  (label .. ": untrusted file, will execute Lua")
  local choices = {
    "Trust this file (remember sha256)",
    "Trust once (don't remember)",
    "Refuse",
  }
  vim.ui.select(choices, {
    prompt = prompt_title .. " · " .. shorten(path),
  }, function(choice)
    if not choice or choice == "Refuse" then
      brand_notify("refused: " .. shorten(path), vim.log.levels.WARN, { title = "trust" })
      on_result(nil, nil)
      return
    end
    if choice == "Trust this file (remember sha256)" then
      local store = load_store()
      store[path] = { sha = sha, trusted_at = os.time() }
      save_store(store)
      brand_notify("trusted: " .. shorten(path), vim.log.levels.INFO, { title = "trust" })
    end
    -- Execute by loading from the (cached) content, so we don't re-read and
    -- race against an attacker who could swap the file between sha and dofile.
    local chunk, lerr = loadstring(content, "=" .. path)
    if not chunk then on_result(nil, "load error: " .. tostring(lerr)); return end
    local ok, result = pcall(chunk)
    if not ok then on_result(nil, "exec error: " .. tostring(result)); return end
    on_result(result, nil)
  end)
end

-- Synchronous-style API. If a prompt is needed we drive it through vim.ui.select
-- which is allowed to be async; in that case we return nil, nil and the caller
-- treats the file as "skip this round". Subsequent calls after the user trusts
-- will succeed immediately from the store.
--
-- This is the right shape for our two call sites (suggest and checklist),
-- which already gracefully handle empty/missing project files.
function M.dofile_if_trusted(path, opts)
  opts = opts or {}
  local label = opts.label or path
  local content = read_file(path)
  if not content then return nil, "unreadable: " .. path end
  local sha = vim.fn.sha256(content)

  local store = load_store()
  local entry = store[path]
  if entry and entry.sha == sha then
    local chunk, lerr = loadstring(content, "=" .. path)
    if not chunk then return nil, "load error: " .. tostring(lerr) end
    local ok, result = pcall(chunk)
    if not ok then return nil, "exec error: " .. tostring(result) end
    return result, nil
  end

  local changed = entry ~= nil
  -- Fire the prompt; result lands asynchronously via vim.ui.select. We don't
  -- block, so this call returns nil now; next time around the trust store
  -- entry will short-circuit through the fast path above.
  prompt_and_run(path, sha, content, label, changed, function(_, _) end)
  return nil, nil
end

function M.list()
  local out = {}
  for path, entry in pairs(load_store()) do
    table.insert(out, { path = path, sha = entry.sha, trusted_at = entry.trusted_at })
  end
  table.sort(out, function(a, b) return (a.trusted_at or 0) > (b.trusted_at or 0) end)
  return out
end

function M.forget(path)
  local store = load_store()
  if store[path] == nil then return false end
  store[path] = nil
  save_store(store)
  return true
end

function M.setup()
  vim.api.nvim_create_user_command("NvimTrustList", function()
    local rows = M.list()
    if #rows == 0 then
      brand_notify("trust store is empty", vim.log.levels.INFO, { title = "trust" })
      return
    end
    local lines = { string.format("Trusted files (%d):", #rows), "" }
    for _, r in ipairs(rows) do
      local age = r.trusted_at and os.date("%Y-%m-%d", r.trusted_at) or "?"
      table.insert(lines, string.format("  [%s]  %s", age, shorten(r.path)))
    end
    brand_notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "trust" })
  end, { desc = "List trusted project-local Lua files" })

  vim.api.nvim_create_user_command("NvimTrustForget", function(args)
    local path = args.args ~= "" and vim.fn.fnamemodify(args.args, ":p") or nil
    if not path then
      brand_notify(":NvimTrustForget <path>", vim.log.levels.WARN, { title = "trust" })
      return
    end
    if M.forget(path) then
      brand_notify("forgot: " .. shorten(path), vim.log.levels.INFO, { title = "trust" })
    else
      brand_notify("not in trust store: " .. shorten(path), vim.log.levels.WARN, { title = "trust" })
    end
  end, { nargs = 1, complete = "file", desc = "Remove a path from the trust store" })
end

return M
