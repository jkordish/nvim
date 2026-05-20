-- Yank ring: persistent history of the last N yanks with a floating picker.
-- Press <leader>p to browse, <CR> to paste, p/P to paste after/before.
local M = {}

local MAX = 50
local STORE = vim.fn.stdpath("state") .. "/yankring.json"
local ring = {}  -- newest first

local function load()
  local f = io.open(STORE, "r")
  if not f then return end
  local data = f:read("*a"); f:close()
  local ok, parsed = pcall(vim.json.decode, data)
  if ok and type(parsed) == "table" then ring = parsed end
end

local function save()
  vim.fn.mkdir(vim.fn.fnamemodify(STORE, ":h"), "p")
  local f = io.open(STORE, "w")
  if f then f:write(vim.json.encode(ring)); f:close() end
end

local function push(entry)
  -- dedup: if newest entry is identical, skip
  if ring[1] and ring[1].text == entry.text then return end
  table.insert(ring, 1, entry)
  while #ring > MAX do table.remove(ring) end
  save()
end

function M.setup()
  load()
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = vim.api.nvim_create_augroup("user_yankring", { clear = true }),
    callback = function()
      local ev = vim.v.event
      local text = table.concat(ev.regcontents or {}, "\n")
      if text == "" or #text > 100000 then return end
      push({
        text = text,
        regtype = ev.regtype,
        ft = vim.bo.filetype,
        time = os.time(),
      })
    end,
  })
end

local function format_preview(entry)
  local age = os.time() - (entry.time or os.time())
  local ago
  if age < 60 then ago = age .. "s"
  elseif age < 3600 then ago = math.floor(age / 60) .. "m"
  elseif age < 86400 then ago = math.floor(age / 3600) .. "h"
  else ago = math.floor(age / 86400) .. "d" end
  local first = vim.split(entry.text, "\n")[1] or ""
  if #first > 60 then first = first:sub(1, 57) .. "..." end
  local lines = select(2, entry.text:gsub("\n", "\n")) + 1
  return string.format("[%3s] %-7s %2dL │ %s", ago, (entry.ft or "?"):sub(1, 7), lines, first:gsub("\t", "  "))
end

function M.pick()
  if #ring == 0 then vim.notify("Yank ring empty", vim.log.levels.INFO); return end
  -- Try telescope first for nicer UI
  local ok, telescope = pcall(require, "telescope.pickers")
  if not ok then return M._pick_native() end

  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  telescope.new({}, {
    prompt_title = "Yank Ring (" .. #ring .. ")",
    finder = finders.new_table({
      results = ring,
      entry_maker = function(e)
        return {
          value = e,
          display = format_preview(e),
          ordinal = e.text,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      define_preview = function(self, entry)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.text, "\n"))
        if entry.value.ft and entry.value.ft ~= "" then
          pcall(vim.treesitter.start, self.state.bufnr, entry.value.ft)
        end
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      local function do_paste(after)
        local entry = action_state.get_selected_entry().value
        actions.close(prompt_bufnr)
        vim.fn.setreg('"', entry.text, entry.regtype)
        vim.cmd("normal! " .. (after and "p" or "P"))
      end
      actions.select_default:replace(function() do_paste(true) end)
      map({ "i", "n" }, "<C-p>", function() do_paste(false) end)
      map({ "i", "n" }, "<C-d>", function()
        local idx = action_state.get_selected_entry().index
        table.remove(ring, idx); save()
        actions.close(prompt_bufnr); M.pick()
      end)
      return true
    end,
  }):find()
end

function M.clear() ring = {}; save(); vim.notify("Yank ring cleared") end

return M
