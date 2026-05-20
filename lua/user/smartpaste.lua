-- Smart paste: inspects the clipboard, detects the content type, and offers
-- transformations. URL → markdown link. JSON → pretty. base64 → decoded.
-- UUID → with hyphens. Hex → decimal. Unix timestamp → ISO. SQL → formatted.
local M = {}

local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

local DETECTORS = {
  url      = function(s) return s:match("^https?://%S+$") end,
  json     = function(s)
    if not (s:match("^%s*[{%[]") and s:match("[}%]]%s*$")) then return false end
    local ok = pcall(vim.json.decode, s); return ok
  end,
  base64   = function(s) return #s >= 8 and s:match("^[A-Za-z0-9+/=]+$") and (#s % 4 == 0) end,
  uuid     = function(s) return s:match("^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$") end,
  uuid_dash = function(s) return s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") end,
  hex      = function(s) return s:match("^0x%x+$") or s:match("^%x+$") and #s <= 16 and not s:match("^%d+$") end,
  timestamp = function(s)
    local n = tonumber(s); return n and n > 1000000000 and n < 9999999999
  end,
  ts_millis = function(s)
    local n = tonumber(s); return n and n > 1000000000000 and n < 9999999999999
  end,
}

local function detect(s)
  local found = {}
  for kind, fn in pairs(DETECTORS) do
    if fn(s) then table.insert(found, kind) end
  end
  return found
end

local TRANSFORMS = {
  url = function(s)
    return {
      { name = "Markdown link",         text = string.format("[%s](%s)", s:match("//([^/]+)") or "link", s) },
      { name = "HTML <a>",              text = string.format('<a href="%s">link</a>', s) },
      { name = "Curl GET",              text = string.format("curl -sS %s", vim.fn.shellescape(s)) },
    }
  end,
  json = function(s)
    local ok, parsed = pcall(vim.json.decode, s)
    if not ok then return {} end
    return {
      { name = "Pretty JSON",   text = vim.fn.system({ "jq", "." }, s) },
      { name = "Compact JSON",  text = vim.json.encode(parsed) },
      { name = "Lua table",     text = vim.inspect(parsed) },
    }
  end,
  base64 = function(s)
    local out = vim.fn.system({ "base64", "-d" }, s)
    return { { name = "Decoded", text = (out or ""):gsub("%s+$", "") } }
  end,
  uuid = function(s)
    return { { name = "With hyphens",
      text = s:sub(1,8) .. "-" .. s:sub(9,12) .. "-" .. s:sub(13,16) .. "-" .. s:sub(17,20) .. "-" .. s:sub(21) } }
  end,
  uuid_dash = function(s)
    return {
      { name = "Without hyphens", text = s:gsub("%-", "") },
      { name = "Uppercase",       text = s:upper() },
    }
  end,
  hex = function(s)
    local n = tonumber(s:gsub("^0x", ""), 16)
    if not n then return {} end
    return {
      { name = "Decimal", text = tostring(n) },
      { name = "Binary",  text = (function() local b="" local x=n; if x==0 then return "0" end while x>0 do b=(x%2)..b; x=math.floor(x/2) end; return b end)() },
    }
  end,
  timestamp = function(s)
    local n = tonumber(s)
    return {
      { name = "ISO 8601 (UTC)",   text = os.date("!%Y-%m-%dT%H:%M:%SZ", n) },
      { name = "Local readable",   text = os.date("%Y-%m-%d %H:%M:%S %Z", n) },
      { name = "Relative",         text = ("%d seconds since now"):format(n - os.time()) },
    }
  end,
  ts_millis = function(s)
    local n = math.floor(tonumber(s) / 1000)
    return {
      { name = "ISO 8601 (UTC)", text = os.date("!%Y-%m-%dT%H:%M:%SZ", n) },
      { name = "Seconds",        text = tostring(n) },
    }
  end,
}

function M.paste()
  local clip = trim(vim.fn.getreg("+"))
  if clip == "" then vim.notify("clipboard empty"); return end

  local kinds = detect(clip)
  if #kinds == 0 then
    vim.notify("smartpaste: no transforms found — pasting raw")
    vim.api.nvim_put({ clip }, "c", true, true)
    return
  end

  local options = { { name = "Paste raw (no transform)", text = clip } }
  for _, kind in ipairs(kinds) do
    for _, t in ipairs((TRANSFORMS[kind] or function() return {} end)(clip)) do
      table.insert(options, { name = kind .. " → " .. t.name, text = t.text })
    end
  end

  vim.ui.select(options, {
    prompt = "Smart paste (detected: " .. table.concat(kinds, ", ") .. ")",
    format_item = function(o)
      local preview = o.text:gsub("\n", " ⏎ "):sub(1, 80)
      return string.format("%-35s  %s", o.name, preview)
    end,
  }, function(choice)
    if not choice then return end
    vim.api.nvim_put(vim.split(choice.text, "\n"), "c", true, true)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("SmartPaste", M.paste, { desc = "Inspect clipboard and offer transforms" })
end

return M
