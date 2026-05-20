-- Webhook receiver: a real HTTP server, inside nvim, via vim.uv TCP.
-- Examples:
--   curl -X POST http://localhost:7777/open -d '{"path":"/tmp/foo","line":42}'
--   curl -X POST http://localhost:7777/eval -d '{"cmd":"echo \"hi\""}'
--   curl -X POST http://localhost:7777/notify -d '{"msg":"build done","level":"info"}'
-- Auth: optional X-Token header matched against vim.g.webhook_token.
local M = {}

M._server = nil
M._port = nil
M._log = {}

local function log(line)
  table.insert(M._log, 1, ("%s  %s"):format(os.date("%H:%M:%S"), line))
  while #M._log > 100 do table.remove(M._log) end
end

local function reply(client, status, body)
  body = body or ""
  local payload = string.format(
    "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
    status, #body, body)
  client:write(payload, function()
    client:shutdown(); client:close()
  end)
end

local handlers = {
  ["GET /"] = function(_, client)
    reply(client, "200 OK", vim.json.encode({
      service = "nvim-webhook",
      endpoints = { "POST /open {path,line?}", "POST /eval {cmd}", "POST /notify {msg,level?}", "GET /status" },
    }))
  end,
  ["GET /status"] = function(_, client)
    reply(client, "200 OK", vim.json.encode({
      port = M._port, log_size = #M._log, requests = M._req_count or 0,
    }))
  end,
  ["POST /open"] = function(req, client)
    local ok, data = pcall(vim.json.decode, req.body or "")
    if not ok or not data.path then reply(client, "400 Bad Request", '{"error":"path required"}'); return end
    vim.schedule(function()
      vim.cmd("edit " .. vim.fn.fnameescape(data.path))
      if data.line then pcall(vim.api.nvim_win_set_cursor, 0, { data.line, data.col or 0 }) end
      log("opened " .. data.path .. (data.line and (":" .. data.line) or ""))
    end)
    reply(client, "200 OK", '{"ok":true}')
  end,
  ["POST /eval"] = function(req, client)
    local ok, data = pcall(vim.json.decode, req.body or "")
    if not ok or not data.cmd then reply(client, "400 Bad Request", '{"error":"cmd required"}'); return end
    vim.schedule(function()
      pcall(vim.cmd, data.cmd)
      log("evaled: " .. data.cmd)
    end)
    reply(client, "200 OK", '{"ok":true}')
  end,
  ["POST /notify"] = function(req, client)
    local ok, data = pcall(vim.json.decode, req.body or "")
    if not ok or not data.msg then reply(client, "400 Bad Request", '{"error":"msg required"}'); return end
    local level = ({ info = vim.log.levels.INFO, warn = vim.log.levels.WARN, error = vim.log.levels.ERROR })[data.level or "info"]
    vim.schedule(function() vim.notify(data.msg, level); log("notify: " .. data.msg) end)
    reply(client, "200 OK", '{"ok":true}')
  end,
}

local function parse_request(raw)
  local method, path = raw:match("^(%S+) (%S+) HTTP")
  if not method then return nil end
  local _, header_end = raw:find("\r\n\r\n", 1, true)
  local body = header_end and raw:sub(header_end + 1) or ""
  local headers = {}
  for h in raw:gmatch("([^\r\n]+)") do
    local k, v = h:match("^(%S+):%s*(.*)$")
    if k then headers[k:lower()] = v end
  end
  return { method = method, path = path, headers = headers, body = body }
end

local function check_token(req)
  local required = vim.g.webhook_token
  if not required or required == "" then return true end
  return req.headers["x-token"] == required
end

local function dispatch(client, raw)
  M._req_count = (M._req_count or 0) + 1
  local req = parse_request(raw)
  if not req then reply(client, "400 Bad Request", '{"error":"malformed request"}'); return end
  if not check_token(req) then reply(client, "401 Unauthorized", '{"error":"bad x-token"}'); return end
  local key = req.method .. " " .. req.path
  local h = handlers[key]
  if h then h(req, client)
  else reply(client, "404 Not Found", '{"error":"no route ' .. key .. '"}') end
end

function M.start(port)
  port = tonumber(port) or 7777
  if M._server then vim.notify("Webhook: already running on :" .. M._port); return end
  M._server = vim.uv.new_tcp()
  local ok, err = pcall(function() M._server:bind("127.0.0.1", port) end)
  if not ok then vim.notify("Webhook bind failed: " .. (err or "?"), vim.log.levels.ERROR); M._server = nil; return end
  M._port = port
  M._req_count = 0
  M._server:listen(64, function(listen_err)
    if listen_err then return end
    local client = vim.uv.new_tcp()
    M._server:accept(client)
    local buf = ""
    client:read_start(function(read_err, data)
      if read_err or not data then if client and not client:is_closing() then client:close() end; return end
      buf = buf .. data
      -- Assume request is complete when we see \r\n\r\n (no chunked support)
      if buf:find("\r\n\r\n", 1, true) then
        local snapshot = buf; buf = ""
        client:read_stop()
        dispatch(client, snapshot)
      end
    end)
  end)
  vim.notify(string.format("Webhook listening on http://127.0.0.1:%d", port))
end

function M.stop()
  if M._server then M._server:close(); M._server = nil; M._port = nil; vim.notify("Webhook stopped") end
end

function M.log()
  if #M._log == 0 then vim.notify("Webhook log empty"); return end
  vim.notify(table.concat(M._log, "\n"))
end

function M.setup()
  vim.api.nvim_create_user_command("WebhookStart", function(args) M.start(args.args) end, { nargs = "?", desc = "Start webhook server" })
  vim.api.nvim_create_user_command("WebhookStop", M.stop, { desc = "Stop webhook server" })
  vim.api.nvim_create_user_command("WebhookLog", M.log, { desc = "Show webhook request log" })
end

return M
