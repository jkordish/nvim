-- Synth: a soft, optional chord on save mapped to filetype. macOS uses the
-- built-in system sounds via `afplay`. Linux uses `paplay` against
-- freedesktop sound theme if available. Off by default — opt in with :Synth.
local M = {}

local enabled = false

-- Map filetype → macOS system sound name (in /System/Library/Sounds)
local MAC_SOUNDS = {
  default        = "Tink",
  lua            = "Glass",
  python         = "Hero",
  javascript     = "Pop",
  typescript     = "Pop",
  javascriptreact = "Pop",
  typescriptreact = "Pop",
  go             = "Funk",
  rust           = "Sosumi",
  c              = "Submarine",
  cpp            = "Submarine",
  bash           = "Frog",
  zsh            = "Frog",
  sh             = "Frog",
  markdown       = "Purr",
  json           = "Ping",
  yaml           = "Ping",
  toml           = "Ping",
  vim            = "Glass",
  gitcommit      = "Bottle",
  -- Special "events"
  __error        = "Basso",      -- played on save-with-errors
  __test_pass    = "Glass",
  __test_fail    = "Basso",
}

-- Linux: try freedesktop sound theme via paplay / canberra-gtk-play.
local LINUX_SOUNDS = {
  default     = "bell",
  __error     = "dialog-error",
  __test_pass = "complete",
  __test_fail = "dialog-error",
}

local function is_mac() return vim.fn.has("mac") == 1 end

local function play(name)
  if not enabled then return end
  if is_mac() then
    local path = "/System/Library/Sounds/" .. (name or "Tink") .. ".aiff"
    if vim.fn.filereadable(path) == 0 then return end
    vim.fn.jobstart({ "afplay", "-v", "0.4", path }, { detach = true })
  else
    if vim.fn.executable("canberra-gtk-play") == 1 then
      vim.fn.jobstart({ "canberra-gtk-play", "-i", name or "bell" }, { detach = true })
    elseif vim.fn.executable("paplay") == 1 then
      local theme = "/usr/share/sounds/freedesktop/stereo/" .. (name or "bell") .. ".oga"
      if vim.fn.filereadable(theme) == 1 then vim.fn.jobstart({ "paplay", theme }, { detach = true }) end
    end
  end
end

local function sound_for(ft, event)
  local table = is_mac() and MAC_SOUNDS or LINUX_SOUNDS
  if event then return table[event] or table.default end
  return table[ft] or table.default
end

function M.play_for_filetype(ft) play(sound_for(ft)) end
function M.play_event(name)      play(sound_for(nil, name)) end

function M.enable()
  if enabled then return end
  enabled = true
  local grp = vim.api.nvim_create_augroup("user_synth", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = grp,
    callback = function(args)
      local diags = vim.diagnostic.get(args.buf, { severity = vim.diagnostic.severity.ERROR })
      if #diags > 0 then play(sound_for(nil, "__error"))
      else play(sound_for(vim.bo[args.buf].filetype)) end
    end,
  })
  vim.notify("synth enabled — chord on save")
end

function M.disable()
  enabled = false
  pcall(vim.api.nvim_del_augroup_by_name, "user_synth")
  vim.notify("synth disabled")
end

function M.toggle() if enabled then M.disable() else M.enable() end end

function M.setup()
  vim.api.nvim_create_user_command("Synth",     M.toggle, { desc = "Toggle save-chord audio" })
  vim.api.nvim_create_user_command("SynthDemo", function()
    for _, ft in ipairs({ "lua", "python", "javascript", "rust", "go", "bash" }) do
      M.play_for_filetype(ft); vim.cmd("sleep 600m")
    end
  end, { desc = "Demo the per-filetype sounds" })
end

return M
