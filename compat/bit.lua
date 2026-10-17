-- LuaJIT's `bit` library on Lua 5.4 operators.
-- Upstream Pokemon Access was written for LuaJIT (Lua 5.1 + bit), which mGBA's
-- Lua 5.4 does not ship. Semantics follow LuaJIT: every operation works on
-- 32 bits and returns a signed 32-bit integer; shift counts are masked to 0..31.
local bit = {}

local function toint(value)
  local n = math.tointeger(value)
  if n == nil then
    if type(value) ~= "number" then
      error("bad argument to bit operation (number expected, got " .. type(value) .. ")", 3)
    end
    n = math.floor(value)
  end
  return n & 0xffffffff
end

local function tobit(value)
  local n = toint(value)
  if n >= 0x80000000 then
    n = n - 0x100000000
  end
  return n
end
bit.tobit = tobit

local function fold(op, first, ...)
  local result = toint(first)
  for i = 1, select("#", ...) do
    result = op(result, toint((select(i, ...))))
  end
  return tobit(result)
end

function bit.band(...)
  return fold(function(a, b) return a & b end, ...)
end

function bit.bor(...)
  return fold(function(a, b) return a | b end, ...)
end

function bit.bxor(...)
  return fold(function(a, b) return a ~ b end, ...)
end

function bit.bnot(value)
  return tobit(~toint(value))
end

function bit.lshift(value, count)
  return tobit(toint(value) << (toint(count) & 31))
end

function bit.rshift(value, count)
  return tobit(toint(value) >> (toint(count) & 31))
end

function bit.arshift(value, count)
  return tobit(value) // (1 << (toint(count) & 31))
end

function bit.tohex(value, digits)
  digits = digits or 8
  local pattern = digits < 0 and "%08X" or "%08x"
  local text = string.format(pattern, toint(value))
  return text:sub(-math.abs(digits))
end

return bit
