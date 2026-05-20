-- Cipher: a persistent encrypted scratchpad. Encrypted at rest with AES-256
-- via openssl. Prompts for passphrase on open. Auto-encrypts on close.
-- File: ~/.local/state/nvim/cipher.enc
local M = {}

local PATH = vim.fn.stdpath("state") .. "/cipher.enc"
local state = { buf = nil, win = nil, passphrase = nil }

local function with_pass(prompt, callback)
  vim.ui.input({ prompt = prompt, default = "" }, function(input)
    if not input then return end
    callback(input)
  end)
end

local function decrypt(pass, cb)
  if vim.fn.filereadable(PATH) == 0 then cb("") return end
  vim.system({
    "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "100000",
    "-in", PATH, "-pass", "stdin",
  }, { stdin = pass, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify("cipher: decrypt failed — wrong passphrase?", vim.log.levels.ERROR)
        cb(nil)
      else
        cb(res.stdout or "")
      end
    end)
  end)
end

local function encrypt(plaintext, pass, cb)
  vim.fn.mkdir(vim.fn.fnamemodify(PATH, ":h"), "p")
  vim.system({
    "openssl", "enc", "-aes-256-cbc", "-salt", "-pbkdf2", "-iter", "100000",
    "-out", PATH, "-pass", "stdin",
  }, { stdin = pass .. "\n" .. plaintext, text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify("cipher: encrypt failed", vim.log.levels.ERROR); cb(false)
      else cb(true) end
    end)
  end)
end

-- openssl needs the passphrase on its own line. `-pass stdin` reads one line.
-- For encrypt we need to provide pass, then the plaintext on stdin... actually
-- `-pass stdin` consumes one line then expects -in to be a file. Let me rework:
-- we write plaintext to a temp file, encrypt that, then delete.
local function encrypt_via_tempfile(plaintext, pass, cb)
  vim.fn.mkdir(vim.fn.fnamemodify(PATH, ":h"), "p")
  local tmp = vim.fn.tempname()
  local f = io.open(tmp, "w"); if not f then cb(false); return end
  f:write(plaintext); f:close()
  vim.system({
    "openssl", "enc", "-aes-256-cbc", "-salt", "-pbkdf2", "-iter", "100000",
    "-in", tmp, "-out", PATH, "-pass", "stdin",
  }, { stdin = pass, text = true }, function(res)
    os.remove(tmp)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.notify("cipher: encrypt failed — " .. (res.stderr or ""), vim.log.levels.ERROR); cb(false)
      else cb(true) end
    end)
  end)
end

local function open_buffer(initial_text)
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "markdown"
  -- These keep the plaintext out of any persistent state
  vim.bo[state.buf].undofile = false
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, vim.split(initial_text or "", "\n", { plain = true }))

  local w = math.floor(vim.o.columns * 0.7)
  local h = math.floor(vim.o.lines * 0.7)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor", border = "double", style = "minimal",
    title = " 🔐  cipher  ·  ESC saves & closes ", title_pos = "center",
    width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2),
    col = math.floor((vim.o.columns - w) / 2),
  })
  vim.api.nvim_set_hl(0, "CipherFrame", { fg = "#cba6f7", bold = true })
  vim.wo[state.win].winhighlight = "FloatBorder:CipherFrame,FloatTitle:CipherFrame"
  vim.keymap.set({ "n", "i" }, "<Esc>", function() M.close() end, { buffer = state.buf })
end

function M.open()
  with_pass("cipher passphrase: ", function(pass)
    if not pass or pass == "" then vim.notify("cipher: cancelled"); return end
    state.passphrase = pass
    decrypt(pass, function(plain)
      if plain == nil then return end
      open_buffer(plain)
    end)
  end)
end

function M.close()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  if not state.passphrase then vim.notify("cipher: no session, just closing"); pcall(vim.api.nvim_win_close, state.win, true); return end
  local plain = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
  encrypt_via_tempfile(plain, state.passphrase, function(ok)
    if ok then vim.notify("cipher: sealed (" .. #plain .. " bytes)") end
    if state.win and vim.api.nvim_win_is_valid(state.win) then vim.api.nvim_win_close(state.win, true) end
    state.buf, state.win, state.passphrase = nil, nil, nil
  end)
end

function M.setup()
  if vim.fn.executable("openssl") == 0 then return end  -- gracefully no-op
  vim.api.nvim_create_user_command("Cipher",      M.open,  { desc = "Open encrypted scratchpad" })
  vim.api.nvim_create_user_command("CipherClose", M.close, { desc = "Seal + close cipher pad" })
end

return M
