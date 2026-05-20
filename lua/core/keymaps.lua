local map = vim.keymap.set

-- General
map("n", "<Esc>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Write" })
map("n", "<leader>W", "<cmd>wa<CR>", { desc = "Write all" })
map("n", "<leader>q", "<cmd>confirm q<CR>", { desc = "Quit" })
map("n", "<leader>Q", "<cmd>qa!<CR>", { desc = "Force quit all" })

-- Better up/down on wrapped lines
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

-- Window nav
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })

-- Window resize
map("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Resize up" })
map("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Resize down" })
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Resize left" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Resize right" })

-- Buffer nav
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })
map("n", "<leader>bD", "<cmd>%bd|e#<CR>", { desc = "Delete all other buffers" })

-- Stay centered
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Move lines (visual)
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })
map("v", "<", "<gv", { desc = "Outdent and reselect" })
map("v", ">", ">gv", { desc = "Indent and reselect" })

-- Paste over selection without clobbering register
map("x", "<leader>p", [["_dP]], { desc = "Paste without yank" })
map({ "n", "v" }, "<leader>d", [["_d]], { desc = "Delete without yank" })

-- Diagnostic nav
map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = "Next diagnostic" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = "Prev diagnostic" })
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- Tabs
map("n", "<leader><tab>n", "<cmd>tabnew<CR>", { desc = "New tab" })
map("n", "<leader><tab>c", "<cmd>tabclose<CR>", { desc = "Close tab" })
map("n", "<leader><tab>]", "<cmd>tabnext<CR>", { desc = "Next tab" })
map("n", "<leader><tab>[", "<cmd>tabprevious<CR>", { desc = "Prev tab" })

-- Quickfix
map("n", "]q", "<cmd>cnext<CR>", { desc = "Next quickfix" })
map("n", "[q", "<cmd>cprev<CR>", { desc = "Prev quickfix" })
map("n", "<leader>xq", "<cmd>copen<CR>", { desc = "Open quickfix" })

-- Terminal
map("t", "<C-/>", "<cmd>close<CR>", { desc = "Hide terminal" })
map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Terminal normal mode" })
