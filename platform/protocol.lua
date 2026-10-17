-- The line protocol between the Lua side and the helper app (PORTING.md 6.2).
-- One message per line, fields separated by tabs. Inside a field a backslash,
-- a tab and a newline are written as \\, \t and \n.
local protocol = {}

local ESCAPES = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n" }
local UNESCAPES = { ["\\"] = "\\", t = "\t", n = "\n" }

function protocol.escape(text)
  return (text:gsub("[\\\t\n]", ESCAPES))
end

function protocol.unescape(text)
  return (text:gsub("\\(.)", function(char)
    return UNESCAPES[char] or char
  end))
end

local function field_text(value)
  local kind = type(value)
  if kind == "string" then
    return protocol.escape(value)
  elseif kind == "boolean" then
    return value and "1" or "0"
  elseif kind == "number" then
    local integer = math.tointeger(value)
    if integer then
      return string.format("%d", integer)
    end
    return tostring(value)
  end
  return protocol.escape(tostring(value))
end

-- fields: array of strings, numbers or booleans. Returns the line with its newline.
function protocol.encode(fields)
  local parts = {}
  for i = 1, #fields do
    parts[i] = field_text(fields[i])
  end
  return table.concat(parts, "\t") .. "\n"
end

-- line: one line; a trailing newline and carriage return are dropped if present.
function protocol.decode(line)
  if line:sub(-1) == "\n" then
    line = line:sub(1, -2)
  end
  if line:sub(-1) == "\r" then
    line = line:sub(1, -2)
  end
  local fields = {}
  for part in (line .. "\t"):gmatch("(.-)\t") do
    fields[#fields + 1] = protocol.unescape(part)
  end
  return fields
end

-- Accumulates socket chunks and hands back complete lines.
local LineBuffer = {}
LineBuffer.__index = LineBuffer

function LineBuffer.new()
  return setmetatable({ pending = "" }, LineBuffer)
end

function LineBuffer:feed(chunk)
  local data = self.pending .. chunk
  local lines = {}
  local start = 1
  while true do
    local newline = data:find("\n", start, true)
    if newline == nil then
      break
    end
    local line = data:sub(start, newline - 1)
    if line:sub(-1) == "\r" then
      line = line:sub(1, -2)
    end
    lines[#lines + 1] = line
    start = newline + 1
  end
  self.pending = data:sub(start)
  return lines
end

protocol.LineBuffer = LineBuffer

return protocol
