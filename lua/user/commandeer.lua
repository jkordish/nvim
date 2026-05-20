-- Commandeer: a filter on which-key that hides leader bindings irrelevant
-- to the current context. Press `?` while which-key is open (or use
-- :CommandeerAll) to escape into the full list. Same muscle memory — every
-- keymap still works — but the panel is much quieter by default.
local M = {}

local _show_all = false   -- session-level toggle
local _git_cache = { t = 0, in_git = false }

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
  -- Some mappings come with " " prefix because <leader>=<Space>
  if not (lhs:sub(1, 1) == " " or lhs:sub(1, 8):lower() == "<leader>") then
    return true
  end

  -- Strip leader to get the next char
  local rest = lhs:gsub("^[ ]", ""):gsub("^<[Ll]eader>", "")
  local first = rest:sub(1, 1)
  if first == "" then return true end

  local rule = RULES[first]
  if rule then
    local ctx = {
      ft = vim.bo.filetype,
      bufnr = vim.api.nvim_get_current_buf(),
    }
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

function M.setup()
  vim.api.nvim_create_user_command("CommandeerToggle", M.toggle_show_all, { desc = "Toggle which-key filtering (context-only ↔ show all)" })
  vim.api.nvim_create_user_command("CommandeerAll",    M.show_all,        { desc = "Open which-key with the full binding list" })

  -- <leader>? opens which-key with show-all (escape hatch)
  vim.keymap.set("n", "<leader>?", function() M.show_all() end, { silent = true, desc = "All bindings (escape filter)" })
end

return M
