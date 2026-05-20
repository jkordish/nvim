-- Commandeer: a filter on which-key that hides leader bindings irrelevant
-- to the current context. Press `?` while which-key is open (or use
-- :CommandeerAll) to escape into the full list. Same muscle memory — every
-- keymap still works — but the panel is much quieter by default.
--
-- ADAPTIVE: every <leader>? escape is observed. The very next leader key
-- the user presses is recorded as "what they were looking for." If they
-- escape ≥3 times in a given filetype to reach the same namespace, that
-- namespace gets quietly loosened — it stays visible in that filetype going
-- forward. The filter learns the way Suggest learns.
local M = {}

local _show_all = false   -- session-level toggle
local _git_cache = { t = 0, in_git = false }

-- ─── adaptive learning state ──────────────────────────────────────────────
local LEARN_FILE = vim.fn.stdpath("state") .. "/commandeer_state.json"
local LOOSEN_THRESHOLD = 3
local OBSERVATION_WINDOW_MS = 30 * 1000
local DECAY_DAYS = 60
local DECAY_SECONDS = DECAY_DAYS * 86400

local learn = {
  escapes  = {},  -- ft -> { first_char -> count of "user escaped → pressed this" }
  loosened = {},  -- ft -> { first_char -> { since, last_used } (force show) }
                  -- Legacy: value may be `true` from older state files; migrated on load.
}

local function load_learn()
  local f = io.open(LEARN_FILE, "r"); if not f then return end
  local ok, parsed = pcall(vim.json.decode, f:read("*a"))
  f:close()
  if ok and type(parsed) == "table" then learn = vim.tbl_deep_extend("force", learn, parsed) end
  -- Migrate legacy `loosened[ft][ch] = true` → table form
  local now = os.time()
  for ft, chars in pairs(learn.loosened or {}) do
    for ch, info in pairs(chars) do
      if info == true then chars[ch] = { since = now, last_used = now } end
    end
  end
end

local function save_learn()
  vim.fn.mkdir(vim.fn.fnamemodify(LEARN_FILE, ":h"), "p")
  local f = io.open(LEARN_FILE, "w"); if f then f:write(vim.json.encode(learn)); f:close() end
end

-- Debounced save so per-keystroke "last_used" updates don't thrash disk.
local _dirty_timer = nil
local function debounced_save()
  if _dirty_timer then return end
  _dirty_timer = vim.uv.new_timer()
  _dirty_timer:start(30 * 1000, 0, vim.schedule_wrap(function()
    if _dirty_timer then _dirty_timer:close(); _dirty_timer = nil end
    save_learn()
  end))
end

-- Decay loosenings whose last_used is older than DECAY_DAYS. Reset their
-- escape counts too so they re-prove themselves. Returns list of removed.
local function decay_stale()
  local now = os.time()
  local removed = {}
  for ft, chars in pairs(learn.loosened or {}) do
    for ch, info in pairs(chars) do
      local last = (type(info) == "table" and info.last_used) or now
      if (now - last) > DECAY_SECONDS then
        chars[ch] = nil
        if learn.escapes[ft] then learn.escapes[ft][ch] = nil end
        table.insert(removed, ("%s · <leader>%s*"):format(ft, ch))
      end
    end
    if next(chars) == nil then learn.loosened[ft] = nil end
  end
  if #removed > 0 then save_learn() end
  return removed
end

local function bump_loosened_usage(ft, ch)
  local entry = learn.loosened[ft] and learn.loosened[ft][ch]
  if not entry then return end
  if entry == true then
    learn.loosened[ft][ch] = { since = os.time(), last_used = os.time() }
  else
    entry.last_used = os.time()
  end
  debounced_save()
end

-- ─── context probe (cached) ────────────────────────────────────────────────
local function is_in_git_repo()
  local now = vim.uv.now()
  if now - _git_cache.t < 5000 then return _git_cache.in_git end
  _git_cache.in_git = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(vim.fn.getcwd()) .. " rev-parse --is-inside-work-tree 2>/dev/null"
  )[1] == "true"
  _git_cache.t = now
  return _git_cache.in_git
end

local REPL_FT = {
  python = true, lua = true, javascript = true, typescript = true,
  javascriptreact = true, typescriptreact = true, ruby = true,
  clojure = true, julia = true, haskell = true, ocaml = true,
  elixir = true, r = true, sh = true, bash = true, zsh = true, fish = true,
}
local FRONTEND_FT = {
  html = true, css = true, scss = true, javascript = true, typescript = true,
  javascriptreact = true, typescriptreact = true, vue = true, svelte = true, astro = true,
}

-- ─── relevance rules — keyed by the FIRST char after <leader> ─────────────
-- Return true to keep the mapping, false to hide.
local RULES = {
  -- Always relevant — core editor actions
  ["!"] = function() return true end,           -- cockpit
  [" "] = function() return true end,           -- <leader><space> = Suggest
  ["?"] = function() return true end,           -- which-key help itself
  ["w"] = function() return true end,           -- write
  ["q"] = function() return true end,           -- quit
  ["c"] = function() return true end,           -- code (LSP)
  ["s"] = function() return true end,           -- search
  ["f"] = function() return true end,           -- find
  ["b"] = function() return true end,           -- buffers
  ["e"] = function() return true end,           -- explorer
  ["E"] = function() return true end,           -- explorer focus
  ["u"] = function() return true end,           -- utilities (yankring/today/...)
  ["a"] = function() return true end,           -- AI
  ["t"] = function() return true end,           -- toggles / tests
  ["d"] = function() return true end,           -- debug
  ["p"] = function() return true end,           -- paste (yank ring)
  ["P"] = function(ctx) return ctx.ft == "markdown" end,
  ["m"] = function() return true end,           -- multicursor or markdown
  ["1"] = function() return true end,           -- harpoon
  ["2"] = function() return true end,
  ["3"] = function() return true end,
  ["4"] = function() return true end,
  ["H"] = function() return true end,           -- harpoon add
  ["h"] = function() return true end,           -- harpoon menu
  ["z"] = function() return false end,          -- fzf-lua removed (kept for safety)
  ["Z"] = function() return false end,

  -- Git-conditional
  ["g"] = function() return is_in_git_repo() end,
  ["O"] = function() return is_in_git_repo() end,   -- Octo (GitHub)
  ["W"] = function() return is_in_git_repo() end,   -- workspace snapshots
  ["x"] = function() return #vim.diagnostic.get() > 0 end,  -- Trouble

  -- Filetype-conditional
  ["r"] = function(ctx) return REPL_FT[ctx.ft] == true end,
  ["R"] = function(ctx) return ctx.ft == "http" or ctx.ft == "rest" end,
  ["Q"] = function(ctx) return ctx.ft == "quarto" or ctx.ft == "markdown" end,
  ["J"] = function(ctx) return ctx.ft == "python" or ctx.ft == "markdown" or ctx.ft == "quarto" end,
  ["n"] = function(ctx) return ctx.ft == "markdown" or vim.fn.isdirectory(vim.fn.expand("~/notes")) == 1 end,

  -- Tasks: only meaningful if there's a runnable in the cwd
  ["T"] = function()
    local cwd = vim.fn.getcwd()
    for _, f in ipairs({ "Makefile", "Justfile", "justfile", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", ".overseer" }) do
      if vim.uv.fs_stat(cwd .. "/" .. f) then return true end
    end
    return false
  end,

  -- App-style — always available where they make sense everywhere
  ["D"] = function() return true end,           -- Database UI
  ["k"] = function() return true end,           -- Kubernetes
  ["C"] = function() return true end,           -- Devcontainer
}

-- ─── filter callable for which-key.opts.filter ─────────────────────────────
function M.filter(mapping)
  if _show_all then return true end
  if not mapping or not mapping.lhs then return true end

  -- Only apply filtering to leader-prefixed bindings; leave standalone ones alone.
  local lhs = mapping.lhs
  if not (lhs:sub(1, 1) == " " or lhs:sub(1, 8):lower() == "<leader>") then
    return true
  end

  -- Strip leader to get the next char
  local rest = lhs:gsub("^[ ]", ""):gsub("^<[Ll]eader>", "")
  local first = rest:sub(1, 1)
  if first == "" then return true end

  local ft = vim.bo.filetype

  -- Adaptive override: if user has historically escaped to reach this
  -- namespace in this filetype ≥ threshold times, force show.
  if learn.loosened[ft] and learn.loosened[ft][first] then
    return true
  end

  local rule = RULES[first]
  if rule then
    local ctx = { ft = ft, bufnr = vim.api.nvim_get_current_buf() }
    local ok, keep = pcall(rule, ctx)
    return ok and keep or false
  end
  return true   -- default: show unknown prefixes
end

-- ─── toggles ───────────────────────────────────────────────────────────────
function M.toggle_show_all()
  _show_all = not _show_all
  local label = _show_all and "showing all bindings" or "filtered to context"
  pcall(require("user.brand").notify, label, nil, { title = "leader" })
end

function M.show_all()
  _show_all = true
  pcall(function() require("which-key").show() end)
end

function M.show_filtered()
  _show_all = false
  pcall(function() require("which-key").show() end)
end

-- ─── unified leader-keystroke observer ────────────────────────────────────
-- Single state machine. `_leader_pending` is set to true any time the user
-- presses space in normal mode; the next normal-mode keystroke is then the
-- character after <leader>. From that one detection we drive both:
--   (1) ALWAYS — track usage of loosened rules so decay can re-tighten
--   (2) IF ARMED post-escape — observe what the user actually wanted
local _leader_pending = false
local _armed = false
local _armed_ts = 0
local _armed_ft = nil

local function record_escape_target(ft, ch)
  if ft == "" or ch == "" then return end
  learn.escapes[ft]  = learn.escapes[ft]  or {}
  learn.loosened[ft] = learn.loosened[ft] or {}

  learn.escapes[ft][ch] = (learn.escapes[ft][ch] or 0) + 1
  local count = learn.escapes[ft][ch]

  -- Cross threshold for the first time → loosen + notify
  if not learn.loosened[ft][ch] and count >= LOOSEN_THRESHOLD then
    learn.loosened[ft][ch] = { since = os.time(), last_used = os.time() }
    pcall(function()
      require("user.brand").notify(
        ("loosened  <leader>%s*  in  %s   (%d escapes here — now always shown)"):format(ch, ft, count),
        nil, { title = "commandeer" })
    end)
  end
  save_learn()
end

local function on_key(typed)
  if not typed or typed == "" then return end
  -- Only normal mode: in insert/cmdline/etc. " " has different semantics.
  if vim.api.nvim_get_mode().mode ~= "n" then
    _leader_pending = false
    return
  end

  local was_leader = _leader_pending
  _leader_pending = (typed == " ")
  if not was_leader then return end

  -- This keystroke is the char immediately after <leader>.
  local ft = vim.bo.filetype
  local ch = typed:sub(1, 1)

  -- (1) Track usage of a currently-loosened rule (always on)
  if learn.loosened[ft] and learn.loosened[ft][ch] then
    bump_loosened_usage(ft, ch)
  end

  -- (2) Escape observation (only when armed)
  if _armed then
    if vim.uv.now() - _armed_ts > OBSERVATION_WINDOW_MS then
      _armed = false
      return
    end
    if ch == "?" then
      _armed_ts = vim.uv.now()
      return
    end
    local rule = RULES[ch]
    if rule then
      local ok, keep = pcall(rule, { ft = _armed_ft, bufnr = 0 })
      if ok and keep == false then
        record_escape_target(_armed_ft, ch)
      end
    end
    _armed = false
  end
end

-- ─── stats + reset + decay ────────────────────────────────────────────────
local function fmt_age(ts)
  if not ts then return "—" end
  local d = math.floor((os.time() - ts) / 86400)
  if d == 0 then return "today" end
  if d == 1 then return "1d ago" end
  return d .. "d ago"
end

function M.stats()
  load_learn()
  local lines = { "  ▸ commandeer · learned loosenings", "" }
  if vim.tbl_isempty(learn.escapes) then
    table.insert(lines, "    no escape patterns observed yet.")
    table.insert(lines, "    press  <leader>?  to escape into the full menu;")
    table.insert(lines, "    after 3 escapes to the same namespace in a ft, it loosens.")
  else
    local fts = vim.tbl_keys(learn.escapes); table.sort(fts)
    for _, ft in ipairs(fts) do
      table.insert(lines, "    " .. ft)
      for ch, n in pairs(learn.escapes[ft]) do
        local info = learn.loosened[ft] and learn.loosened[ft][ch]
        local mark = info and "●" or "○"
        local age = info and (type(info) == "table") and (" · used " .. fmt_age(info.last_used)) or ""
        table.insert(lines, ("      %s  <leader>%s*       %d escape%s%s"):format(
          mark, ch, n, n == 1 and "" or "s", age))
      end
    end
  end
  table.insert(lines, "")
  table.insert(lines, ("    ● = loosened   ·   decay after %d days unused"):format(DECAY_DAYS))
  pcall(function() require("user.brand").notify(table.concat(lines, "\n"), nil, { title = "commandeer" }) end)
end

function M.reset()
  learn = { escapes = {}, loosened = {} }
  save_learn()
  pcall(function() require("user.brand").notify("commandeer learning reset", nil, { title = "commandeer" }) end)
end

function M.decay()
  load_learn()
  local removed = decay_stale()
  pcall(function()
    if #removed == 0 then
      require("user.brand").notify("no loosenings stale enough to decay", nil, { title = "commandeer" })
    else
      require("user.brand").notify(
        ("decayed %d loosening%s:\n  %s"):format(#removed, #removed == 1 and "" or "s",
          table.concat(removed, "\n  ")),
        nil, { title = "commandeer" })
    end
  end)
end

function M.setup()
  load_learn()
  -- Run decay once per startup. Quiet — no notification unless something fell.
  decay_stale()

  vim.api.nvim_create_user_command("CommandeerToggle", M.toggle_show_all, { desc = "Toggle which-key filtering (context-only ↔ show all)" })
  vim.api.nvim_create_user_command("CommandeerAll",    M.show_all,        { desc = "Open which-key with the full binding list" })
  vim.api.nvim_create_user_command("CommandeerStats",  M.stats,           { desc = "Show what Commandeer has learned (with last-used age)" })
  vim.api.nvim_create_user_command("CommandeerReset",  M.reset,           { desc = "Reset Commandeer's learned loosenings" })
  vim.api.nvim_create_user_command("CommandeerDecay",  M.decay,           { desc = "Force decay pass — tighten loosenings unused >60d" })

  -- <leader>? is the escape hatch AND the trigger that arms observation.
  vim.keymap.set("n", "<leader>?", function()
    _armed = true
    _armed_ts = vim.uv.now()
    _saw_leader = false
    _armed_ft = vim.bo.filetype
    M.show_all()
  end, { silent = true, desc = "All bindings (escape filter)" })

  -- Permanent vim.on_key listener; the state machine inside is cheap.
  vim.on_key(on_key, vim.api.nvim_create_namespace("user_commandeer_observe"))
end

return M
