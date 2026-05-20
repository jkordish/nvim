-- Peek: preview LSP definition / references / type / impl in a brand-styled
-- floating window without leaving your spot. Closer to JetBrains' "quick
-- definition" panel than vim's default `gd` jump.
--
-- Keys (set in user-modules.lua):
--   gp   peek definition
--   gP   peek references (list in scratch, <CR> on row jumps)
--   gT   peek type definition
--   gI   peek implementation
--
-- Inside the peek window: q / Esc close · <CR> jump to the location for real.
local M = {}

local brand = require("user.brand")

local function _open_at(file, line, col, opts)
  opts = opts or {}
  if not file or not vim.uv.fs_stat(file) then
    brand.notify("file vanished: " .. tostring(file), vim.log.levels.WARN, { title = "peek" })
    return
  end
  -- Load (or reuse) buffer with the file
  local buf = vim.fn.bufnr(file, false)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = ""
    local ok, lines = pcall(vim.fn.readfile, file)
    if not ok then
      brand.notify("read failed: " .. tostring(lines), vim.log.levels.ERROR, { title = "peek" })
      return
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    pcall(vim.api.nvim_buf_set_name, buf, file)
    -- Set filetype so syntax highlighting kicks in (treesitter / regex)
    local ft = vim.filetype.match({ filename = file, buf = buf })
    if ft then vim.bo[buf].filetype = ft end
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
    vim.bo[buf].bufhidden = "wipe"
  end

  local short = vim.fn.fnamemodify(file, ":t")
  local r = brand.win({
    title = ("peek · %s:%d"):format(short, line + 1),
    width = math.max(80, math.floor(vim.o.columns * 0.7)),
    height = math.max(15, math.floor(vim.o.lines * 0.5)),
    anchor = "center",
    buf = buf,
  })
  pcall(vim.api.nvim_win_set_cursor, r.win, { line + 1, col or 0 })
  -- Center the target line in the peek window
  pcall(vim.api.nvim_win_call, r.win, function() vim.cmd("normal! zz") end)
  vim.wo[r.win].number          = true
  vim.wo[r.win].cursorline      = true
  vim.wo[r.win].signcolumn      = "no"

  local opts2 = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", "<CR>", function()
    r.close()
    vim.cmd("edit +" .. (line + 1) .. " " .. vim.fn.fnameescape(file))
    pcall(vim.api.nvim_win_set_cursor, 0, { line + 1, col or 0 })
  end, opts2)
end

local function _lsp_request(method, handler)
  if #vim.lsp.get_clients({ bufnr = 0 }) == 0 then
    brand.notify("no LSP attached", vim.log.levels.WARN, { title = "peek" })
    return
  end
  local params = vim.lsp.util.make_position_params(0, "utf-8")
  vim.lsp.buf_request(0, method, params, function(err, result, ctx)
    if err then
      brand.notify("error · " .. tostring(err.message or err), vim.log.levels.ERROR, { title = "peek" })
      return
    end
    if not result or (type(result) == "table" and vim.tbl_isempty(result)) then
      brand.notify("no result", nil, { title = "peek" })
      return
    end
    handler(result, ctx)
  end)
end

local function _first_loc(result)
  if result.uri then return result end          -- single location
  if result[1] then return result[1] end        -- list
end

function M.definition()
  _lsp_request("textDocument/definition", function(result, ctx)
    local loc = _first_loc(result); if not loc then return end
    local file = vim.uri_to_fname(loc.uri or loc.targetUri)
    local rng  = loc.range or loc.targetRange or loc.targetSelectionRange
    _open_at(file, rng.start.line, rng.start.character)
  end)
end

function M.type_definition()
  _lsp_request("textDocument/typeDefinition", function(result)
    local loc = _first_loc(result); if not loc then return end
    local file = vim.uri_to_fname(loc.uri or loc.targetUri)
    local rng  = loc.range or loc.targetRange
    _open_at(file, rng.start.line, rng.start.character)
  end)
end

function M.implementation()
  _lsp_request("textDocument/implementation", function(result)
    local loc = _first_loc(result); if not loc then return end
    local file = vim.uri_to_fname(loc.uri or loc.targetUri)
    local rng  = loc.range or loc.targetRange
    _open_at(file, rng.start.line, rng.start.character)
  end)
end

-- References get rendered as a list (KEY  file:line  preview), <CR> jumps
function M.references()
  _lsp_request("textDocument/references", function(result)
    local rows, locs = {}, {}
    for _, loc in ipairs(result) do
      local file = vim.uri_to_fname(loc.uri)
      local rng  = loc.range
      local short = vim.fn.fnamemodify(file, ":~:.")
      table.insert(locs, { file = file, line = rng.start.line, col = rng.start.character })
      table.insert(rows, ("  %-50s  %4d:%-3d"):format(short:sub(-50), rng.start.line + 1, rng.start.character))
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"; vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
    vim.bo[buf].modifiable = false
    local r = brand.win({
      title = ("peek · references · %d"):format(#locs),
      width = math.max(80, math.floor(vim.o.columns * 0.7)),
      height = math.max(10, math.min(#rows + 2, math.floor(vim.o.lines * 0.5))),
      anchor = "center",
      buf = buf,
    })
    vim.wo[r.win].cursorline = true
    vim.keymap.set("n", "<CR>", function()
      local row = vim.api.nvim_win_get_cursor(r.win)[1]
      local l = locs[row]
      if not l then return end
      r.close()
      vim.cmd("edit +" .. (l.line + 1) .. " " .. vim.fn.fnameescape(l.file))
      pcall(vim.api.nvim_win_set_cursor, 0, { l.line + 1, l.col })
    end, { buffer = buf, silent = true, nowait = true })
  end)
end

return M
