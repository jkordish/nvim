-- Performance HUD: live floating window showing redraw FPS, LSP request rate,
-- RSS memory, top 5 slowest-loading plugins, attached LSP clients per buffer.
-- Toggle with :PerfHUD or <leader>uP.
local M = {}

local state = { win = nil, buf = nil, timer = nil, last_redraw = 0, frames = 0, fps = 0, lsp_reqs = 0, last_reset = 0 }

local function rss_mb()
  -- Cross-platform RSS via getrusage isn't in vim.uv directly; use ps for portability.
  local out = vim.fn.system("ps -o rss= -p " .. vim.fn.getpid()):gsub("%s+", "")
  return math.floor(tonumber(out or 0) / 1024)
end

local function top_plugins(n)
  local stats = require("lazy").stats()
  local plugins = require("lazy.core.config").plugins
  local list = {}
  for _, p in pairs(plugins) do
    if p._.loaded and p._.loaded.time then
      table.insert(list, { name = p.name, ms = p._.loaded.time })
    end
  end
  table.sort(list, function(a, b) return a.ms > b.ms end)
  local out = {}
  for i = 1, math.min(n, #list) do table.insert(out, list[i]) end
  return out, stats
end

local function attached_lsps()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  local names = {}
  for _, c in ipairs(clients) do table.insert(names, c.name) end
  return names
end

local function ts_active() return vim.b.ts_highlight and "yes" or "no" end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  local top, stats = top_plugins(5)
  local lsps = attached_lsps()
  -- Premium card layout: label/value pairs, right-aligned values, single
  -- divider, generous breathing room above and below.
  local function row(label, value)
    local pad = 48 - vim.api.nvim_strwidth(label) - vim.api.nvim_strwidth(value) - 4
    return "  " .. label .. string.rep(" ", math.max(1, pad)) .. value .. "  "
  end
  local lines = {
    "",
    row("fps",           tostring(state.fps)),
    row("memory",        rss_mb() .. " mb"),
    row("uptime",        string.format("%.0f s", (vim.uv.now() - (state.start_ms or vim.uv.now())) / 1000)),
    row("plugins",       stats.loaded .. " / " .. stats.count),
    row("startup",       string.format("%.0f ms", stats.startuptime or 0)),
    row("lsp clients",   #lsps == 0 and "—" or table.concat(lsps, ", ")),
    row("treesitter",    ts_active() == "yes" and "on" or "—"),
    row("lsp req/sec",   tostring(state.lsp_reqs)),
    "",
    "    ───────────────  slowest to load",
    "",
  }
  for _, p in ipairs(top) do
    table.insert(lines, row(p.name, string.format("%.0f ms", p.ms)))
  end
  table.insert(lines, "")
  table.insert(lines, "    " .. "r reset    c close")

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function tick()
  state.frames = state.frames + 1
  local now = vim.uv.now()
  if now - state.last_redraw >= 1000 then
    state.fps = state.frames
    state.frames = 0
    state.last_redraw = now
  end
  if now - state.last_reset >= 1000 then
    state.lsp_reqs = state._reqs_this_sec or 0
    state._reqs_this_sec = 0
    state.last_reset = now
  end
  render()
end

local function open()
  state.start_ms = state.start_ms or vim.uv.now()
  state.last_redraw = vim.uv.now()
  state.last_reset = vim.uv.now()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "perfhud"

  local width, height = 50, 22
  state.win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor", style = "minimal", border = "rounded",
    title = "  ◆  perf  ", title_pos = "left",
    width = width, height = height,
    row = 1, col = vim.o.columns - width - 2, focusable = true,
  })
  vim.wo[state.win].winhighlight = "Normal:BrandFloat,FloatBorder:BrandFloatBorder,FloatTitle:BrandFloatTitle"

  vim.keymap.set("n", "c", function() M.close() end, { buffer = state.buf, silent = true })
  vim.keymap.set("n", "q", function() M.close() end, { buffer = state.buf, silent = true })
  vim.keymap.set("n", "r", function() state.start_ms = vim.uv.now() end, { buffer = state.buf, silent = true })

  state.timer = vim.uv.new_timer()
  state.timer:start(0, 500, vim.schedule_wrap(tick))

  -- Count LSP requests (best-effort: hook vim.lsp.buf_request)
  if not state._hooked then
    state._hooked = true
    local orig = vim.lsp.buf_request_all
    if orig then
      vim.lsp.buf_request_all = function(...)
        state._reqs_this_sec = (state._reqs_this_sec or 0) + 1
        return orig(...)
      end
    end
  end
end

function M.close()
  if state.timer then state.timer:stop(); state.timer:close(); state.timer = nil end
  if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
  state.win, state.buf = nil, nil
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then M.close() else open() end
end

function M.setup()
  vim.api.nvim_create_user_command("PerfHUD", M.toggle, { desc = "Toggle performance HUD" })
end

return M
