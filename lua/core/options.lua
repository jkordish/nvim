local opt = vim.opt

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false
opt.linebreak = true

opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.smartindent = true

opt.ignorecase = true
opt.smartcase = true
opt.incsearch = true
opt.hlsearch = true

opt.splitright = true
opt.splitbelow = true
opt.splitkeep = "screen"

opt.termguicolors = true
opt.background = "dark"
opt.pumheight = 12
opt.pumblend = 10
opt.winblend = 0
opt.showmode = false
opt.cmdheight = 1
opt.laststatus = 3
opt.shortmess:append("WcCsI")
opt.fillchars = { eob = " ", fold = " ", foldopen = "v", foldsep = " ", foldclose = ">" }

opt.swapfile = false
opt.backup = false
opt.undofile = true
opt.undodir = vim.fn.stdpath("state") .. "/undo"
opt.updatetime = 200
opt.timeoutlen = 400

opt.clipboard = "unnamedplus"
opt.mouse = "a"
opt.confirm = true
opt.completeopt = "menu,menuone,noselect"

opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldlevel = 99
opt.foldlevelstart = 99

opt.list = true
opt.listchars = { tab = "→ ", trail = "·", nbsp = "␣" }

opt.spelllang = { "en" }
opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }

-- Faster startup: skip some default providers we don't use.
vim.g.loaded_python_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Silence deprecation warnings from upstream plugins (git-conflict, hydra,
-- rustaceanvim) using removed nvim 0.12 APIs. They'll fix it; meanwhile we
-- don't need the noise.
do
  local orig = vim.deprecate
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.deprecate = function(name, alternative, version, plugin, backtrace)
    local muted = {
      ["vim.highlight"] = true,
      ["vim.validate"] = true,
      ["vim.lsp.buf_get_clients()"] = true,
      ["vim.lsp.get_buffers_by_client_id()"] = true,
    }
    if muted[name] then return end
    return orig(name, alternative, version, plugin, backtrace)
  end
end

-- Cap LSP log size so it can't grow to a gigabyte again.
vim.lsp.log.set_level("WARN")
