-- Right-click context menu. mousemodel=popup_setpos (set in core/options.lua)
-- positions the cursor at the click and pops up the menu named "PopUp".
-- This module owns the contents of that menu and rebuilds it per-buffer so
-- LSP / filetype / cursor-context items only appear when relevant.
local M = {}

-- Always-available menu items. Anything LSP/filetype-specific is added by
-- _refresh() below, keyed by buffer state.
local function _base_items()
  vim.cmd([[
    aunmenu PopUp
    silent! anoremenu PopUp.&Cut            "+x
    silent! anoremenu PopUp.&Copy           "+y
    silent! anoremenu PopUp.&Paste          "+p
    silent! anoremenu PopUp.Select\ &All    ggVG
    anoremenu PopUp.-sep1-                  <Nop>
  ]])
end

-- Rebuilds the PopUp for the current buffer. Cheap; called on BufEnter +
-- LspAttach + filetype change. We always start from a clean slate so stale
-- entries from a previous buffer never leak in.
function M.refresh()
  _base_items()

  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype == "prompt" then return end

  -- ── LSP-aware items: only when at least one client is attached ──
  local clients = vim.lsp.get_clients({ bufnr = buf })
  if #clients > 0 then
    vim.cmd([[
      anoremenu PopUp.Goto\ &definition   <cmd>lua vim.lsp.buf.definition()<CR>
      anoremenu PopUp.Find\ &references   <cmd>lua vim.lsp.buf.references()<CR>
      anoremenu PopUp.&Hover              <cmd>lua vim.lsp.buf.hover()<CR>
      anoremenu PopUp.Code\ &action       <cmd>lua vim.lsp.buf.code_action()<CR>
      anoremenu PopUp.&Rename             <cmd>lua vim.lsp.buf.rename()<CR>
    ]])
    -- formatting only if any attached client advertises it
    for _, c in ipairs(clients) do
      if c.server_capabilities and c.server_capabilities.documentFormattingProvider then
        vim.cmd([[anoremenu PopUp.&Format            <cmd>lua vim.lsp.buf.format({async=true})<CR>]])
        break
      end
    end
    vim.cmd([[anoremenu PopUp.-sep_lsp-          <Nop>]])
  end

  -- ── filetype-specific items ──
  local ft = vim.bo[buf].filetype
  if ft == "markdown" then
    vim.cmd([[
      silent! anoremenu PopUp.Markdown\ &preview  <cmd>MarkdownPreviewToggle<CR>
      silent! anoremenu PopUp.&Present            <cmd>lua require("user.present").start()<CR>
      anoremenu PopUp.-sep_md-                    <Nop>
    ]])
  end

  -- ── cursor-context items: JIRA-NNN under cursor → open it ──
  local line = vim.api.nvim_get_current_line() or ""
  local col  = vim.api.nvim_win_get_cursor(0)[2] + 1
  local s = 1
  while s <= #line do
    local ms, me, m = line:find("([A-Z][A-Z0-9]+%-%d+)", s)
    if not ms then break end
    if col >= ms and col <= me then
      vim.cmd(("anoremenu PopUp.&Jira:\\ open\\ %s  <cmd>lua require('user.jira').show_issue('%s')<CR>")
        :format(m, m))
      vim.cmd("anoremenu PopUp.-sep_jira-  <Nop>")
      break
    end
    s = me + 1
  end

  -- ── always-tail items ──
  vim.cmd([[
    silent! anoremenu PopUp.&Spotlight           <cmd>lua require("user.spotlight").open()<CR>
    silent! anoremenu PopUp.&What\ should\ I\ do?  <cmd>lua require("user.suggest").show()<CR>
  ]])
end

function M.setup()
  local grp = vim.api.nvim_create_augroup("user_contextmenu", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "LspAttach", "FileType" }, {
    group = grp,
    callback = function() pcall(M.refresh) end,
  })
  -- prime once at startup so the menu exists before the first BufEnter fires
  vim.schedule(function() pcall(M.refresh) end)
end

return M
