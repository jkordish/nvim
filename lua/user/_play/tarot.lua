-- Tarot: a developer's tarot deck. One card per day, deterministic by date
-- so the same card surfaces all day. Beautiful ASCII border, name, meaning.
local M = {}

-- 18-card developer's deck. Each has an ASCII glyph, a name, and a brief
-- interpretation (upright meaning only — the deck is intentionally kind).
local DECK = {
  { glyph = "    ✺  ✺\n      ✺",         name = "The Refactor",      meaning = "Necessary destruction. The thing that exists was true for its moment; what comes next will be true for now." },
  { glyph = "    ▲ ▲ ▲\n   ▲ ▲ ▲ ▲",     name = "The Build",         meaning = "Patience. Each layer needs the one below it to be solid. Move slowly. Move once." },
  { glyph = "      ◉\n      |",          name = "The Bug",           meaning = "Hidden truth revealed. The bug was always there; today the system showed it to you. Listen." },
  { glyph = "    ⇣⇣⇣\n    ⇣⇣⇣",          name = "The Merge",         meaning = "Synthesis. Two streams becoming one. Trust the conflict; it's where the work is." },
  { glyph = "      ⚡\n     /|\\",        name = "The Deploy",        meaning = "Sudden transformation. What you ship is no longer yours; it belongs to its users now. Let go." },
  { glyph = "    ↓ ↓ ↓\n    ↓ ↓ ↓",      name = "The Stack Trace",   meaning = "Descent into the underworld. Each frame is a teacher. Follow them down without flinching." },
  { glyph = "    ▣ ▣ ▣\n    ▣ ▣ ▣",      name = "The Cache",         meaning = "Memory and forgetting. What you remember is true until the world changes around it. Invalidate freely." },
  { glyph = "      ⚖\n     / \\",        name = "The Linter",        meaning = "Judgment without malice. The rule wasn't made for you, but it applies to you. Honor it or break it deliberately." },
  { glyph = "    ▸ ▸ ▸\n    > > >",      name = "The Console",       meaning = "Voice of the unconscious. The print statement says what the test cannot. Trust the dirty tool today." },
  { glyph = "     ◯ ◯\n     ◯ ◯",        name = "The Pull Request",  meaning = "Surrender to community. The code belongs to the team now. Their questions are gifts." },
  { glyph = "     ⤴ ⤴\n    ⤴ ⤴ ⤴",      name = "The Force Push",    meaning = "Hubris recognized in time. Pause before this card. Whose work are you about to erase?" },
  { glyph = "     ┌─┐\n     └─┘",        name = "The README",        meaning = "First step on the journey. Someone in the future is reading this. Write for them, not for you." },
  { glyph = "     △△△\n      △",         name = "The Test Suite",    meaning = "Trial by fire. The thing that breaks here was always broken. You just made it loud." },
  { glyph = "     ⏰ ⚡\n      ?",         name = "The Race Condition", meaning = "Fate and timing. Two truths happen in the wrong order. Reach for the mutex, not the retry." },
  { glyph = "     ░ ▒ ▓\n     █ █ █",    name = "The Memory Leak",   meaning = "The slow betrayal. Something small is keeping a reference to something large. Be the one who lets go." },
  { glyph = "      ▮\n      ▮",          name = "The Mutex",         meaning = "Boundaries. Not everyone enters at once. Holding the door is the work; opening it is the reward." },
  { glyph = "    ⌒ ⌒ ⌒\n   ⌒ ⌒ ⌒ ⌒",   name = "The Async",         meaning = "Trust the future. The function returns before its answer. Live with the suspense." },
  { glyph = "     ✦ ✦\n      ✦",         name = "The Commit",        meaning = "A moment fixed in time. Past you and future you meet here. Write the message they both need to read." },
}

local function pick_today()
  local seed = tonumber(os.date("%Y%m%d"))
  math.randomseed(seed)
  return DECK[math.random(#DECK)]
end

local function pick_random() math.randomseed(os.time()); return DECK[math.random(#DECK)] end

local function frame(card)
  local W = 50
  local function center(s) local pad = math.max(0, math.floor((W - vim.api.nvim_strwidth(s)) / 2)); return string.rep(" ", pad) .. s end
  local function wrap(text, width)
    local out, line = {}, ""
    for word in text:gmatch("%S+") do
      if #line + #word + 1 > width then table.insert(out, line); line = word
      else line = (line == "") and word or (line .. " " .. word) end
    end
    if line ~= "" then table.insert(out, line) end
    return out
  end
  local border_top = "╭" .. string.rep("─", W) .. "╮"
  local border_bot = "╰" .. string.rep("─", W) .. "╯"
  local lines = { border_top, "│" .. string.rep(" ", W) .. "│" }
  for line in (card.glyph .. "\n"):gmatch("([^\n]*)\n") do
    local padded = center(line); padded = padded .. string.rep(" ", W - vim.api.nvim_strwidth(padded))
    table.insert(lines, "│" .. padded .. "│")
  end
  table.insert(lines, "│" .. string.rep(" ", W) .. "│")
  local nm = center(card.name)
  table.insert(lines, "│" .. nm .. string.rep(" ", W - vim.api.nvim_strwidth(nm)) .. "│")
  table.insert(lines, "│" .. string.rep(" ", W) .. "│")
  table.insert(lines, "│" .. center("─ ─ ─ ─ ─ ─ ─ ─") .. string.rep(" ", W - 17) .. "│")
  table.insert(lines, "│" .. string.rep(" ", W) .. "│")
  for _, l in ipairs(wrap(card.meaning, W - 6)) do
    local padded = "  " .. l; padded = padded .. string.rep(" ", W - vim.api.nvim_strwidth(padded))
    table.insert(lines, "│" .. padded .. "│")
  end
  table.insert(lines, "│" .. string.rep(" ", W) .. "│")
  table.insert(lines, border_bot)
  return lines
end

local function show_card(card, title)
  local lines = frame(card)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local w = vim.api.nvim_strwidth(lines[1]) + 2
  local h = #lines + 2
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", style = "minimal", border = "double",
    title = " " .. (title or "✦  tarot") .. " ", title_pos = "center",
    width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
  })
  -- Soft purple/lavender tint
  vim.api.nvim_set_hl(0, "TarotCard", { fg = "#cba6f7", bold = true })
  vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:TarotCard,FloatTitle:TarotCard"
  vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf })
  vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf })
end

function M.today()  show_card(pick_today(),  "✦  today's card  ·  " .. os.date("%a %b %d")) end
function M.draw()   show_card(pick_random(), "✦  drawn card") end

function M.setup()
  vim.api.nvim_create_user_command("Tarot",     M.today, { desc = "Today's developer tarot card" })
  vim.api.nvim_create_user_command("TarotDraw", M.draw,  { desc = "Draw a random tarot card" })
end

return M
