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
opt.fillchars = {
  eob = " ",
  fold = " ",
  foldopen = "▾",
  foldsep = "│",
  foldclose = "▸",
  diff = "╱",
  msgsep = "─",
}

-- Universal rounded borders for every floating window the harness opens.
opt.winborder = "rounded"

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

-- Faster startup: skip default providers we don't use.
vim.g.loaded_python_provider = 0      -- python2 (unused)
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0

-- Point python3 provider at a real binary (not the asdf shim) so the
-- "appears to be a pyenv shim" healthcheck warning goes away. This is the
-- python that actually has pynvim installed.
do
  local candidates = {
    vim.fn.expand("~/.asdf/installs/python/3.12-dev/bin/python3"),
    "/opt/homebrew/bin/python3",
    "/usr/bin/python3",
  }
  for _, p in ipairs(candidates) do
    if vim.fn.executable(p) == 1 then
      local has_pynvim = vim.fn.system({ p, "-c", "import pynvim" })
      if vim.v.shell_error == 0 then
        vim.g.python3_host_prog = p
        break
      end
    end
  end
end

-- Silence deprecation warnings from upstream plugins (git-conflict, hydra,
-- rustaceanvim) using removed nvim 0.12 APIs. They'll fix it; meanwhile we
-- don't need the noise.
do
  local orig = vim.deprecate
  -- Match by prefix (deprecate names sometimes include "<table>" / "()" suffix).
  local muted_prefixes = {
    "vim.highlight",
    "vim.validate",
    "vim.lsp.buf_get_clients",
    "vim.lsp.get_buffers_by_client_id",
    "vim.lsp.set_log_level",
    "vim.lsp.codelens.refresh",  -- belt-and-suspenders for upstream plugins
    "vim.str_utfindex",          -- nvim-notify "wrapped-default" renderer
  }
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.deprecate = function(name, alternative, version, plugin, backtrace)
    for _, p in ipairs(muted_prefixes) do
      if type(name) == "string" and name:sub(1, #p) == p then return end
    end
    return orig(name, alternative, version, plugin, backtrace)
  end
end

-- Cap LSP log size so it can't grow to a gigabyte again.
vim.lsp.log.set_level("WARN")
