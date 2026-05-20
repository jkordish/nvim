-- Quill: every keystroke logged with timestamp to a stenograph file.
-- Replay the day as a typing animation. Off by default, opt-in per session.
local M = {}

local LOG_DIR = vim.fn.stdpath("state") .. "/quill"
local enabled = false
local current_file
local fh

local function open_log()
  vim.fn.mkdir(LOG_DIR, "p")
  current_file = LOG_DIR .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".steno"
  fh = io.open(current_file, "a")
  if fh then fh:write(("# steno session begun %s\n"):format(os.date("%Y-%m-%dT%H:%M:%S"))); fh:flush() end
end

local function write_event(kind, payload)
  if not fh then return end
  fh:write(string.format("%d\t%s\t%s\n", vim.uv.now(), kind, payload or ""))
  fh:flush()
end

local function on_key(_, typed)
  if not enabled then return end
  if not typed or typed == "" then return end
  write_event("k", typed:gsub("\n", "\\n"):gsub("\t", "\\t"))
end

function M.enable()
  if enabled then return end
  enabled = true
  open_log()
  vim.on_key(on_key, vim.api.nvim_create_namespace("user_quill"))
  vim.notify("quill: recording → " .. vim.fn.fnamemodify(current_file, ":~"))
end

function M.disable()
  enabled = false
  vim.on_key(nil, vim.api.nvim_create_namespace("user_quill"))
  if fh then fh:write("# session ended " .. os.date("%H:%M:%S") .. "\n"); fh:close(); fh = nil end
  vim.notify("quill: stopped (" .. (current_file or "?") .. ")")
end

function M.toggle() if enabled then M.disable() else M.enable() end end

-- Replay: open a picker of saved sessions, play back into a scratch buffer
-- at original speed (relative-timestamp scaled by `speed`).
function M.replay()
  local files = vim.fn.glob(LOG_DIR .. "/*.steno", false, true)
  if #files == 0 then vim.notify("quill: no recordings yet") return end
  table.sort(files, function(a, b) return a > b end)
  local entries = {}
  for _, f in ipairs(files) do
    table.insert(entries, vim.fn.fnamemodify(f, ":t"):gsub("%.steno$", ""))
  end
  vim.ui.select(entries, { prompt = "Replay session" }, function(choice)
    if not choice then return end
    M._do_replay(LOG_DIR .. "/" .. choice .. ".steno", 1.0)
  end)
end

function M._do_replay(path, speed)
  speed = speed or 1.0
  local events = {}
  for line in io.lines(path) do
    local t, k, p = line:match("^(%d+)\t([^\t]+)\t(.*)$")
    if t then table.insert(events, { t = tonumber(t), kind = k, payload = p }) end
  end
  if #events == 0 then vim.notify("quill: empty session") return end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_open_win(buf, true, {
    relative = "editor", border = "rounded", style = "minimal",
    title = " ✎  replay  ·  " .. vim.fn.fnamemodify(path, ":t") .. " ", title_pos = "center",
    width = math.floor(vim.o.columns * 0.7),
    height = math.floor(vim.o.lines * 0.6),
    row = math.floor(vim.o.lines * 0.2),
    col = math.floor(vim.o.columns * 0.15),
  })
  vim.cmd("startinsert")

  local start = events[1].t
  for _, e in ipairs(events) do
    local delay = (e.t - start) / speed
    vim.defer_fn(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if e.kind == "k" then
        local text = e.payload:gsub("\\n", "\n"):gsub("\\t", "\t")
        -- Translate control sequences to inserted text only (skip mode keys)
        if text:match("^[%w%s%p]+$") then
          vim.api.nvim_buf_set_text(buf, vim.api.nvim_buf_line_count(buf) - 1,
            #(vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""),
            vim.api.nvim_buf_line_count(buf) - 1,
            #(vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""),
            { text })
        end
      end
    end, delay)
  end
end

function M.setup()
  vim.api.nvim_create_user_command("Quill",       M.toggle, { desc = "Toggle steno recording" })
  vim.api.nvim_create_user_command("QuillReplay", M.replay, { desc = "Replay a past steno session" })
end

return M
