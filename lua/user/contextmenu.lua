-- Right-click context menu. mousemodel=popup_setpos (set in core/options.lua)
-- positions the cursor at the click and pops up the menu named "PopUp".
--
-- We do NOT wipe the PopUp menu — Neovim's built-in defaults populate it
-- with LSP items ("Go to definition", "Open in split", "Inspect", etc.) and
-- a MenuPopup autocmd enables/disables them based on context. If we
-- `aunmenu PopUp` those entries disappear, then on right-click the default
-- autocmd tries to `amenu disable PopUp.Go\ to\ definition` and fails with
-- E329. So this module only ADDS supplementary items (with our own paths)
-- alongside what Neovim already provides.
local M = {}

-- Items we install once and leave alone. Names start with a unique tag
-- (Brand·…) so they don't collide with built-ins of similar wording.
local function _install_base()
  vim.cmd([[
    silent! anoremenu PopUp.Brand·-sep-     <Nop>
    silent! anoremenu PopUp.Brand·&Spotlight             <cmd>lua require("user.spotlight").open()<CR>
    silent! anoremenu PopUp.Brand·&What\ should\ I\ do?  <cmd>lua require("user.suggest").show()<CR>
  ]])
end

-- The dynamic item: "Brand·Jira: open KEY-N" appears only when the cursor
-- is sitting on a key. It's removed and re-added per refresh so the key is
-- always current. silent! around remove so it's a no-op when absent.
local function _dynamic_jira_item()
  vim.cmd("silent! aunmenu PopUp.Brand·&Jira·open")
  local line = vim.api.nvim_get_current_line() or ""
  local col  = vim.api.nvim_win_get_cursor(0)[2] + 1
  local s = 1
  while s <= #line do
    local ms, me, m = line:find("([A-Z][A-Z0-9]+%-%d+)", s)
    if not ms then break end
    if col >= ms and col <= me then
      -- Menu path uses '\ ' to embed a space; we want to render "Jira·open KEY-N"
      vim.cmd(("anoremenu PopUp.Brand·&Jira·open\\ %s <cmd>lua require('user.jira').show_issue('%s')<CR>")
        :format(m, m))
      return
    end
    s = me + 1
  end
end

-- Filetype add-ons. Use a distinct name per ft so toggling between buffers
-- doesn't leave stale items.
local function _ft_items(ft)
  vim.cmd("silent! aunmenu PopUp.Brand·Markdown·preview")
  vim.cmd("silent! aunmenu PopUp.Brand·&Present")
  if ft == "markdown" then
    vim.cmd([[
      silent! anoremenu PopUp.Brand·Markdown·preview <cmd>MarkdownPreviewToggle<CR>
      silent! anoremenu PopUp.Brand·&Present         <cmd>lua require("user.present").start()<CR>
    ]])
  end
end

function M.refresh()
  _install_base()
  _ft_items(vim.bo.filetype)
  _dynamic_jira_item()
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("user_contextmenu", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "LspAttach", "FileType", "CursorMoved" }, {
    group = grp,
    callback = function() pcall(M.refresh) end,
  })
  vim.schedule(function() pcall(M.refresh) end)
end

return M
