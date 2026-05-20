-- Coverage gutter: parse coverage.xml (cobertura) or lcov.info, render
-- gutter signs for covered (✓) / uncovered (✗) / partial (◐) lines.
-- :CoverageShow / :CoverageHide / :CoverageRefresh
local M = {}

local NS = vim.api.nvim_create_namespace("user_coverage")
local sign_group = "user_coverage"

local function find_report(cwd)
  local candidates = {
    cwd .. "/coverage.xml",
    cwd .. "/coverage/coverage.xml",
    cwd .. "/coverage/lcov.info",
    cwd .. "/lcov.info",
    cwd .. "/coverage.lcov",
    cwd .. "/.coverage/coverage.xml",
    cwd .. "/build/coverage.xml",
    cwd .. "/target/coverage/coverage.xml",
  }
  for _, p in ipairs(candidates) do
    if vim.fn.filereadable(p) == 1 then return p end
  end
  return nil
end

local function parse_lcov(path)
  local files = {}
  local current
  for line in io.lines(path) do
    local f = line:match("^SF:(.+)")
    if f then current = { file = f, lines = {} }; files[f] = current
    elseif current then
      local n, hits = line:match("^DA:(%d+),(%d+)")
      if n then current.lines[tonumber(n)] = tonumber(hits) > 0 and "hit" or "miss" end
      if line == "end_of_record" then current = nil end
    end
  end
  return files
end

local function parse_cobertura(path)
  -- minimal cobertura parser without xml dep: pulls <line number="N" hits="M"/>
  -- and <class filename="..."> blocks. Good enough for pytest-cov / coverage.py.
  local files = {}
  local current
  for line in io.lines(path) do
    local fname = line:match("filename=\"([^\"]+)\"")
    if fname then current = { file = fname, lines = {} }; files[fname] = current end
    local n, hits = line:match("<line number=\"(%d+)\" hits=\"(%d+)\"")
    if n and current then
      current.lines[tonumber(n)] = tonumber(hits) > 0 and "hit" or "miss"
    end
  end
  return files
end

local function load()
  local cwd = vim.fn.getcwd()
  local report = find_report(cwd)
  if not report then return nil, "no coverage report found in " .. cwd end
  if report:match("%.xml$") then return parse_cobertura(report)
  else return parse_lcov(report) end
end

local SIGNS = {
  hit  = { text = "▎", texthl = "DiagnosticOk"   },
  miss = { text = "▎", texthl = "DiagnosticError"},
}

local function define_signs()
  vim.fn.sign_define("CoverageHit",  { text = SIGNS.hit.text,  texthl = SIGNS.hit.texthl  })
  vim.fn.sign_define("CoverageMiss", { text = SIGNS.miss.text, texthl = SIGNS.miss.texthl })
end

local function apply(files)
  define_signs()
  local applied = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local bname = vim.api.nvim_buf_get_name(bufnr)
      if bname ~= "" then
        for fname, info in pairs(files) do
          if bname:sub(-#fname) == fname or fname:sub(-#bname) == bname then
            vim.fn.sign_unplace(sign_group, { buffer = bufnr })
            for lnum, status in pairs(info.lines) do
              vim.fn.sign_place(0, sign_group, "Coverage" .. status:sub(1,1):upper() .. status:sub(2), bufnr, { lnum = lnum })
              applied = applied + 1
            end
            break
          end
        end
      end
    end
  end
  return applied
end

function M.show()
  local files, err = load()
  if not files then vim.notify("Coverage: " .. err, vim.log.levels.WARN); return end
  local n = apply(files)
  vim.notify(string.format("Coverage: %d signs across %d files", n, vim.tbl_count(files)))
end

function M.hide()
  vim.fn.sign_unplace(sign_group)
  vim.notify("Coverage signs cleared")
end

function M.setup()
  vim.api.nvim_create_user_command("CoverageShow", M.show, { desc = "Show coverage gutter signs" })
  vim.api.nvim_create_user_command("CoverageHide", M.hide, { desc = "Hide coverage gutter signs" })
  vim.api.nvim_create_user_command("CoverageRefresh", M.show, { desc = "Re-read coverage report and re-apply" })
end

return M
