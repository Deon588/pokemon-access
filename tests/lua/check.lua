-- Minimal assertion helpers for the Lua test files in this directory.
-- Usage: local check = require("check") ... check.done()
local check = {}
local failures = {}
local count = 0

-- Renders a value for failure messages; nested tables stop at depth 3 and
-- cycles are shown as "<cycle>".
local function describe(value, depth, seen)
  depth = depth or 0
  seen = seen or {}
  if type(value) == "table" then
    if seen[value] then
      return "<cycle>"
    end
    if depth >= 3 then
      return "{...}"
    end
    seen[value] = true
    local keys = {}
    for k in pairs(value) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = tostring(k) .. " = " .. describe(value[k], depth + 1, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  if type(value) == "string" then
    return string.format("%q", value)
  end
  return tostring(value)
end

-- Structural equality; identical tables (and cycles already being compared)
-- short-circuit, so self-referencing tables such as a module's _M field work.
local function deep_equal(a, b, seen)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  seen = seen or {}
  if seen[a] == b then
    return true
  end
  seen[a] = b
  for k, v in pairs(a) do
    if not deep_equal(v, b[k], seen) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

-- level 3 is the test file: record <- check.* <- test. `detail` is a function
-- so that failure text is only rendered when a check fails.
local function record(ok, label, detail)
  count = count + 1
  if not ok then
    local info = debug.getinfo(3, "Sl")
    failures[#failures + 1] = string.format("%s:%d: %s: %s",
      info.short_src, info.currentline, label or "check", detail())
  end
end

function check.eq(actual, expected, label)
  record(deep_equal(actual, expected), label, function()
    return "expected " .. describe(expected) .. ", got " .. describe(actual)
  end)
end

function check.truthy(value, label)
  record(value and true or false, label, function()
    return "expected a truthy value, got " .. describe(value)
  end)
end

function check.falsy(value, label)
  record(not value, label, function()
    return "expected a falsy value, got " .. describe(value)
  end)
end

function check.error(fn, pattern, label)
  local ok, err = pcall(fn)
  if ok then
    record(false, label, function()
      return "expected an error matching " .. describe(pattern) .. ", got none"
    end)
  else
    record(tostring(err):find(pattern) ~= nil, label, function()
      return "error " .. describe(tostring(err)) .. " does not match " .. describe(pattern)
    end)
  end
end

function check.done()
  if #failures > 0 then
    for _, failure in ipairs(failures) do
      io.stderr:write("FAIL " .. failure .. "\n")
    end
    io.stderr:write(string.format("%d of %d checks failed\n", #failures, count))
    os.exit(1)
  end
  print("ok " .. count)
end

return check
