-- Pre-flight checklist. Reads `.preflight.lua` from the project root if it
-- exists, else uses a sensible default. Each check is { name, run() ->
-- ok, detail }. Runs all, shows a floating list with pass/fail lights.
local M = {}

local function default_checks()
  return {
    {
      name = "Working tree clean",
      run = function()
        local out = vim.fn.systemlist("git status --porcelain")
        if vim.v.shell_error ~= 0 then return false, "not a git repo" end
        return #out == 0, (#out > 0) and (#out .. " changed file(s)") or "clean"
      end,
    },
    {
      name = "On a tracked branch",
      run = function()
        local b = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1] or ""
        local u = vim.fn.systemlist("git rev-parse --symbolic-full-name @{u} 2>/dev/null")[1] or ""
        return u ~= "", (u ~= "") and ("tracking " .. u) or ("branch '" .. b .. "' has no upstream")
      end,
    },
    {
      name = "No debug prints",
      run = function()
        local hits = vim.fn.systemlist({ "rg", "--no-heading", "--count-matches",
          "-e", "console%.log|debugger|print\\(.*DEBUG.*\\)|pdb%.set_trace|fmt%.Println.*TODO" })
        local total = 0
        for _, line in ipairs(hits) do
          local n = tonumber(line:match(":(%d+)$"))
          if n then total = total + n end
        end
        return total == 0, total > 0 and (total .. " hits") or "none"
      end,
    },
    {
      name = "No TODO/FIXME added today",
      run = function()
        local diff = vim.fn.systemlist({ "git", "diff", "HEAD", "-U0" })
        local added = 0
        for _, l in ipairs(diff) do
          if l:sub(1,1) == "+" and not l:sub(1,3):match("^%+%+%+") and l:match("TODO[:%s]") then added = added + 1 end
        end
        return added == 0, added > 0 and (added .. " new TODOs in diff") or "none"
      end,
    },
    {
      name = "All buffers saved",
      run = function()
        local dirty = 0
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then dirty = dirty + 1 end
        end
        return dirty == 0, dirty > 0 and (dirty .. " modified") or "all saved"
      end,
    },
    {
      name = "No LSP diagnostics: errors",
      run = function()
        local errs = #vim.diagnostic.get(nil, { severity = vim.diagnostic.severity.ERROR })
        return errs == 0, errs > 0 and (errs .. " errors") or "none"
      end,
    },
  }
end

local function load_project_checks()
  local f = vim.fn.getcwd() .. "/.preflight.lua"
  if vim.fn.filereadable(f) == 0 then return default_checks() end
  -- Gate dofile through the trust helper: prompts on first sight / sha change.
  local mod, err = require("user._trust").dofile_if_trusted(f, { label = ".preflight.lua" })
  if err then
    require("user.brand").notify("preflight: " .. err, vim.log.levels.WARN, { title = "preflight" })
    return default_checks()
  end
  if mod == nil then
    -- Declined or prompt pending; fall back to defaults this round.
    return default_checks()
  end
  if type(mod) ~= "table" then
    require("user.brand").notify("preflight: invalid " .. f, vim.log.levels.WARN, { title = "preflight" })
    return default_checks()
  end
  return mod
end

function M.run()
  local checks = load_project_checks()
  local results = {}
  for _, c in ipairs(checks) do
    local ok, detail = pcall(c.run)
    local pass, msg
    if not ok then pass, msg = false, "exception: " .. tostring(detail)
    else
      if type(detail) == "table" then pass, msg = detail[1], detail[2]
      else pass = detail; msg = "" end
    end
    if type(pass) == "boolean" then
      table.insert(results, { name = c.name, pass = pass, msg = msg or "" })
    end
  end

  -- Render
  local lines = { "  PRE-FLIGHT CHECKLIST", string.rep("─", 60) }
  local passed = 0
  for _, r in ipairs(results) do
    local light = r.pass and "🟢" or "🔴"
    if not r.pass then
      -- Use Unicode without emoji to keep monospacing — these can be wider
      light = "●"
    else light = "●"; passed = passed + 1 end
    -- Use plain markers and add color via extmark later if we want
    local mark = r.pass and " ✓ " or " ✗ "
    table.insert(lines, string.format("  %s %-40s  %s", mark, r.name, r.msg))
  end
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, string.format("  %d / %d passed%s",
    passed, #results, passed == #results and "   ✈  CLEARED FOR DEPARTURE" or "   ⚠  HOLD"))
  table.insert(lines, "")
  table.insert(lines, "  q to close")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local NS = vim.api.nvim_create_namespace("user_preflight")
  for i, r in ipairs(results) do
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, i + 1, 0, {
      end_col = #lines[i + 2],
      hl_group = r.pass and "DiagnosticOk" or "DiagnosticError",
    })
  end

  local width = 64
  local height = #lines + 2
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", border = "rounded", style = "minimal",
    title = " ✈ PRE-FLIGHT ", title_pos = "center",
    width = width, height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
end

function M.setup()
  vim.api.nvim_create_user_command("Preflight", M.run, { desc = "Run pre-flight checklist" })
end

return M
