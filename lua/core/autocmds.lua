local function aug(name)
  return vim.api.nvim_create_augroup("user_" .. name, { clear = true })
end

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  group = aug("yank_highlight"),
  callback = function() vim.hl.on_yank({ timeout = 200 }) end,
})

-- Trim trailing whitespace on save
vim.api.nvim_create_autocmd("BufWritePre", {
  group = aug("trim_whitespace"),
  callback = function()
    local view = vim.fn.winsaveview()
    vim.cmd([[silent! keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})

-- Auto-resize splits when window is resized
vim.api.nvim_create_autocmd("VimResized", {
  group = aug("resize_splits"),
  callback = function()
    local current_tab = vim.fn.tabpagenr()
    vim.cmd("tabdo wincmd =")
    vim.cmd("tabnext " .. current_tab)
  end,
})

-- Restore cursor to last position when reopening a file
vim.api.nvim_create_autocmd("BufReadPost", {
  group = aug("last_loc"),
  callback = function(args)
    local exclude = { "gitcommit", "gitrebase" }
    local buf = args.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].user_last_loc then
      return
    end
    vim.b[buf].user_last_loc = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Close certain filetypes with q
vim.api.nvim_create_autocmd("FileType", {
  group = aug("close_with_q"),
  pattern = {
    "help", "lspinfo", "man", "notify", "qf", "query", "checkhealth",
    "PlenaryTestPopup", "neotest-output", "neotest-summary", "startuptime",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = event.buf, silent = true })
  end,
})

-- Auto-create parent directories on save
vim.api.nvim_create_autocmd("BufWritePre", {
  group = aug("auto_mkdir"),
  callback = function(event)
    if event.match:match("^%w%w+:[\\/][\\/]") then return end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- Spellcheck + wrap for prose
vim.api.nvim_create_autocmd("FileType", {
  group = aug("prose"),
  pattern = { "markdown", "gitcommit", "text" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})
