-- Tour: a 7-step guided walkthrough of the headline features. Brand-styled
-- floating card. n/p/<Space> to advance, q to exit. Marker so it only
-- auto-suggests once; user can replay any time with :Tour.
local M = {}

local MARKER = vim.fn.stdpath("state") .. "/.toured"

-- ─── steps ────────────────────────────────────────────────────────────────
-- Each step: { title, body (table of lines), hint (action to try) }
local STEPS = {
  {
    title = "welcome to your cockpit",
    body = {
      "this isn't just an editor — it's a workspace that watches",
      "your context and offers you what's relevant.",
      "",
      "this tour is seven slides. roughly two minutes.",
    },
    hint = "press  n  or  Space  to begin",
  },
  {
    title = "the spacebar is a question",
    body = {
      "press  Space Space  any time.",
      "",
      "a small card opens with 4-6 actions ranked by what's",
      "actually relevant right now — your current file, open",
      "diagnostics, git state, time of day, recent picks.",
      "",
      "press a number to fire. the panel stays open and re-ranks",
      "as you work. ● marks ones you've picked here before.",
    },
    hint = "later: try  Space Space  ·  press  n  to continue",
  },
  {
    title = "leader is your namespace",
    body = {
      "Space is the leader key. pressing it (and pausing 350ms)",
      "opens a which-key popup.",
      "",
      "by default it's filtered to ONLY the bindings relevant",
      "to your current buffer. in a non-git file you won't see",
      "git keymaps. in python you'll see REPL keys.",
      "",
      "press  Space ?  to escape into the full reference.",
    },
    hint = "press  n  to continue",
  },
  {
    title = "the editor learns",
    body = {
      "every action you fire from Suggest is remembered.",
      "if you keep doing  fix → save → commit  in a python",
      "project with errors, those weights climb.",
      "",
      "after three repetitions, that chain becomes a playbook.",
      "open  :Playbooks  to browse them. name them. pin them",
      "to  F2 - F5  to fire the whole sequence with one key.",
    },
    hint = "press  n  to continue",
  },
  {
    title = "engage mission control",
    body = {
      "Space ! !  brings up the full HUD layout:",
      "  · symbol tree on the left",
      "  · diagnostics on the right",
      "  · terminal on the bottom",
      "  · live compass + radar floating",
      "",
      "Space ! e  ejects when done. clean reset, single key.",
    },
    hint = "press  n  to continue",
  },
  {
    title = "talk to the AI",
    body = {
      "three surfaces, three flavors:",
      "",
      "  Alt-l    accept Copilot ghost text inline",
      "  Space aT  open Avante (chat with Claude in a side pane)",
      "  :AI <intent>      one-shot question with cursor context",
      "  :Explain          stream Claude under any diagnostic",
      "",
      "needs:  ANTHROPIC_API_KEY  in your shell rc.",
    },
    hint = "press  n  to continue",
  },
  {
    title = "you're set",
    body = {
      "  Space Space        what should I do next?",
      "  Space ?            every binding, unfiltered",
      "  Space ! !          full cockpit",
      "  Space ! e          eject (panic reset)",
      "  :Suggest           :Playbooks           :Throttle",
      "",
      "  ./scripts/doctor.sh issues   when something feels off.",
      "",
      "  re-run this tour any time with  :Tour",
    },
    hint = "press  q  or  Esc  to close",
  },
}

-- ─── state ────────────────────────────────────────────────────────────────
local state = { win = nil, buf = nil, idx = 1 }
local NS = vim.api.nvim_create_namespace("user_tour")

local function close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win, state.buf, state.idx = nil, nil, 1
end

local function progress_dots(idx, total)
  local out = {}
  for i = 1, total do table.insert(out, i == idx and "●" or "○") end
  return table.concat(out, "  ")
end

local function render()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  local s = STEPS[state.idx]
  if not s then close(); return end

  local W = vim.api.nvim_win_get_width(state.win)
  local lines = { "" }
  -- title line
  table.insert(lines, "  ◆  " .. s.title)
  table.insert(lines, "")
  -- body
  for _, line in ipairs(s.body) do
    table.insert(lines, "    " .. line)
  end
  -- pad body to consistent height across steps
  local target_body = 10
  while #lines < target_body + 3 do table.insert(lines, "") end
  -- divider
  table.insert(lines, "    " .. string.rep("─", math.min(W - 8, 50)))
  table.insert(lines, "")
  -- hint
  table.insert(lines, "    " .. s.hint)
  table.insert(lines, "")
  -- progress dots + step counter on the same line
  local dots = progress_dots(state.idx, #STEPS)
  local counter = string.format("%d / %d", state.idx, #STEPS)
  local pad = math.max(2, W - 8 - vim.api.nvim_strwidth(dots) - vim.api.nvim_strwidth(counter))
  table.insert(lines, "    " .. dots .. string.rep(" ", pad) .. counter .. "  ")

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Highlights
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for r, line in ipairs(lines) do
    local row = r - 1
    -- title row
    if line:find("◆") and r == 2 then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandAccent" })
    end
    -- hint line and divider in muted/subtext
    if line:find("press ") or line:find("later: try") then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandSubtext" })
    end
    if line:find("^%s+─") then
      pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, 0,
        { end_line = row + 1, hl_group = "BrandMuted" })
    end
    -- progress dots — paint active dot accent, inactive dots muted
    local first_dot = line:find("●", 1, true)
    if first_dot then
      -- naive: paint each ● accent and ○ muted; safe because we control the string
      local col = 0
      while col < #line do
        local c = line:sub(col + 1, col + 3)   -- ● and ○ are 3 bytes each
        if c == "●" then
          pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, col,
            { end_col = col + 3, hl_group = "BrandAccent" })
          col = col + 3
        elseif c == "○" then
          pcall(vim.api.nvim_buf_set_extmark, state.buf, NS, row, col,
            { end_col = col + 3, hl_group = "BrandMuted" })
          col = col + 3
        else
          col = col + 1
        end
      end
    end
  end
end

local function next_step()
  if state.idx >= #STEPS then close(); return end
  state.idx = state.idx + 1
  render()
end

local function prev_step()
  if state.idx <= 1 then return end
  state.idx = state.idx - 1
  render()
end

function M.start()
  if state.win and vim.api.nvim_win_is_valid(state.win) then close() end
  state.idx = 1

  local W, H = 64, 22
  local r = require("user.brand").win({
    title = "tour",
    width = W, height = H,
    anchor = "center",
    close_keys = {},   -- we manage close ourselves to control marker write
    animate = true,
  })
  state.win, state.buf = r.win, r.buf

  -- Nav keymaps
  local opts = { buffer = state.buf, silent = true, nowait = true }
  for _, k in ipairs({ "n", "<Space>", "<Right>", "<CR>" }) do
    vim.keymap.set("n", k, next_step, opts)
  end
  for _, k in ipairs({ "p", "<Left>", "<BS>" }) do
    vim.keymap.set("n", k, prev_step, opts)
  end
  vim.keymap.set("n", "q",     function() M.finish() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.finish() end, opts)

  render()
end

function M.finish()
  -- Mark as toured so we don't auto-suggest again
  vim.fn.mkdir(vim.fn.fnamemodify(MARKER, ":h"), "p")
  local f = io.open(MARKER, "w")
  if f then f:write(os.date("%Y-%m-%dT%H:%M:%S")); f:close() end
  close()
end

function M.reset()
  vim.fn.delete(MARKER)
  pcall(function()
    require("user.brand").notify("tour will surface on next nvim launch", nil, { title = "tour" })
  end)
end

function M.maybe_offer()
  -- Called from welcome's "auto-fire on first launch" — only if welcome
  -- already ran AND tour hasn't been seen yet, and we're on bare nvim.
  if vim.fn.filereadable(MARKER) == 1 then return end
  if vim.fn.argc(-1) ~= 0 then return end
  vim.defer_fn(function()
    pcall(function()
      require("user.brand").notify(
        "take a 2-min tour of the headline features?  :Tour  to start",
        nil, { title = "first time?" })
    end)
  end, 4000)
end

function M.setup()
  vim.api.nvim_create_user_command("Tour",      M.start, { desc = "Take the guided tour of headline features" })
  vim.api.nvim_create_user_command("TourReset", M.reset, { desc = "Reset the tour marker so it's offered again" })

  -- One-shot first-launch nudge (post-welcome)
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("user_tour_offer", { clear = true }),
    once = true,
    callback = function() M.maybe_offer() end,
  })
end

return M
