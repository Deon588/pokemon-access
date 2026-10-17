-- Lua 5.1 / LuaJIT globals that upstream Pokemon Access relies on and that
-- Lua 5.4 removed: unpack, math.pow, loadstring, module and package.seeall.
local lua51 = {}

-- Lua 5.1's package.seeall: let the module read globals through its metatable.
local function seeall(mod)
  setmetatable(mod, { __index = _G })
end

-- Lua 5.1's module(): create or reuse the global table `name`, register it in
-- package.loaded, apply the option functions, then make the calling chunk run
-- inside that table by swapping its _ENV upvalue (the 5.4 equivalent of
-- setfenv on the caller).
local function module(name, ...)
  local mod = package.loaded[name]
  if type(mod) ~= "table" then
    mod = rawget(_G, name)
    if type(mod) ~= "table" then
      mod = {}
      _G[name] = mod
    end
    package.loaded[name] = mod
  end
  if mod._NAME == nil then
    mod._NAME = name
    mod._M = mod
    mod._PACKAGE = (name:gsub("[^.]*$", ""))
  end
  for i = 1, select("#", ...) do
    local option = select(i, ...)
    if type(option) ~= "function" then
      error("bad option to module(): function expected, got " .. type(option), 2)
    end
    option(mod)
  end
  local caller = debug.getinfo(2, "f").func
  local index = 1
  while true do
    local upvalue = debug.getupvalue(caller, index)
    if upvalue == nil then
      error("module(): the calling chunk has no _ENV upvalue", 2)
    end
    if upvalue == "_ENV" then
      debug.setupvalue(caller, index, mod)
      return
    end
    index = index + 1
  end
end

function lua51.install()
  _G.unpack = _G.unpack or table.unpack
  math.pow = math.pow or function(a, b) return a ^ b end
  _G.loadstring = _G.loadstring or load
  package.seeall = package.seeall or seeall
  _G.module = _G.module or module
end

return lua51
