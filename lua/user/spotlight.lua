-- Spotlight: one keymap, every navigation source at once. Files, buffers,
-- recent files, marks, jumplist, LSP symbols (current buf + workspace),
-- diagnostics, commands, AI shortcuts. Each entry shows its source category.
local M = {}

local function gather_files(cb)
  vim.system({ "rg", "--files", "--hidden", "--glob=!.git/" }, { text = true }, function(res)
    vim.schedule(function()
      local out = {}
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        table.insert(out, { kind = "file", display = "  " .. line, value = line })
      end
      cb(out)
    end)
  end)
end

local function gather_buffers()
  local out = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" then
        local short = vim.fn.fnamemodify(name, ":~:.")
        table.insert(out, { kind = "buf", display = "  " .. short, value = name, bufnr = b })
      end
    end
  end
  return out
end

local function gather_recent()
  local out = {}
  for _, f in ipairs(vim.v.oldfiles) do
    if vim.fn.filereadable(f) == 1 then
      table.insert(out, { kind = "recent", display = "  " .. vim.fn.fnamemodify(f, ":~:."), value = f })
    end
    if #out >= 30 then break end
  end
  return out
end

local function gather_marks()
  local out = {}
  for _, m in ipairs(vim.fn.getmarklist()) do
    if m.mark:match("'[A-Z0-9]") then
      table.insert(out, {
        kind = "mark",
        display = string.format("  %s  %s:%d", m.mark:sub(2), vim.fn.fnamemodify(m.file or "", ":~:."), m.pos[2]),
        value = m.file, line = m.pos[2],
      })
    end
  end
  return out
end

local function gather_diagnostics()
  local out = {}
  local severity_icon = { [1] = " ", [2] = " ", [3] = " ", [4] = "󰌵 " }
  for _, d in ipairs(vim.diagnostic.get()) do
    local fn = vim.api.nvim_buf_get_name(d.bufnr)
    table.insert(out, {
      kind = "diag",
      display = string.format("%s %s:%d  %s", severity_icon[d.severity] or " ",
        vim.fn.fnamemodify(fn, ":t"), d.lnum + 1, (d.message or ""):gsub("\n", " "):sub(1, 80)),
      value = fn, line = d.lnum + 1, col = d.col,
    })
  end
  return out
end

local function gather_commands()
  local out = {}
  for _, c in ipairs(vim.api.nvim_get_commands({})) do
    -- skip; the dict form is keyed differently
  end
  for name, _ in pairs(vim.api.nvim_get_commands({})) do
    table.insert(out, { kind = "cmd", display = "  :" .. name, value = ":" .. name })
  end
  return out
end

local function gather_jumps()
  local out = {}
  local jl = vim.fn.getjumplist()
  local jumps = jl[1] or {}
  for i = math.max(1, #jumps - 20), #jumps do
    local j = jumps[i]
    if j and j.bufnr and vim.api.nvim_buf_is_valid(j.bufnr) then
      local fn = vim.api.nvim_buf_get_name(j.bufnr)
      if fn ~= "" then
        table.insert(out, { kind = "jump",
          display = string.format("  %s:%d", vim.fn.fnamemodify(fn, ":t"), j.lnum),
          value = fn, line = j.lnum })
      end
    end
  end
  return out
end

local function gather_ai_shortcuts()
  return {
    { kind = "ai", display = " ✦  Ask: explain this code",        value = "ai:explain" },
    { kind = "ai", display = " ✦  Ask: review for bugs",          value = "ai:review" },
    { kind = "ai", display = " ✦  Ask: add type annotations",     value = "ai:types" },
    { kind = "ai", display = " ✦  Ask: write a test for this",    value = "ai:test" },
    { kind = "ai", display = " ✦  Ask: refactor more idiomatic",  value = "ai:refactor" },
  }
end

local function on_select(entry)
  if entry.kind == "file" or entry.kind == "recent" or entry.kind == "mark" or entry.kind == "diag" or entry.kind == "jump" then
    vim.cmd("edit " .. vim.fn.fnameescape(entry.value))
    if entry.line then pcall(vim.api.nvim_win_set_cursor, 0, { entry.line, entry.col or 0 }) end
  elseif entry.kind == "buf" then
    vim.cmd("buffer " .. entry.bufnr)
  elseif entry.kind == "cmd" then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(entry.value, true, false, true), "n", false)
  elseif entry.kind == "ai" then
    local prompt = ({ explain = "explain this code", review = "review for bugs",
      types = "add type annotations", test = "write a test for this code",
      refactor = "refactor this to be more idiomatic" })[entry.value:sub(4)]
    vim.cmd("AI " .. prompt)
  end
end

function M.open()
  local items = {}
  vim.list_extend(items, gather_buffers())
  vim.list_extend(items, gather_recent())
  vim.list_extend(items, gather_marks())
  vim.list_extend(items, gather_jumps())
  vim.list_extend(items, gather_diagnostics())
  vim.list_extend(items, gather_commands())
  vim.list_extend(items, gather_ai_shortcuts())

  -- Files arrive async via rg; merge in once back
  gather_files(function(files)
    vim.list_extend(items, files)

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers.new({}, {
      prompt_title = " ✦ Spotlight (" .. #items .. " results)",
      finder = finders.new_table({
        results = items,
        entry_maker = function(e)
          return {
            value = e,
            display = e.display,
            ordinal = e.display,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry().value
          actions.close(prompt_bufnr)
          on_select(entry)
        end)
        return true
      end,
    }):find()
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("Spotlight", M.open, { desc = "Unified Raycast-style picker" })
end

return M
