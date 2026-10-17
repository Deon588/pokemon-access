-- Recreates the VBA-ReRecording Lua surface that upstream pokemon.lua expects,
-- on top of a platform table (platform/mgba.lua or platform/vba.lua). After
-- compat.install(platform) the upstream scripts run unmodified: `memory`,
-- `emu`, `input`, `bit`, `unpack`, `module`, the `tolk`, `win-controls` and
-- `audio` modules, and path functions that accept Windows backslashes.
local lua51 = require("compat.lua51")
local bit = require("compat.bit")

local compat = {}

-- Executing these addresses meant "the ROM (re)started" on VBA; they map to
-- the platform's reset notification instead of a breakpoint.
local RESET_ADDRESSES = { [0x100] = true, [0x8000000] = true }

local original = {
  loadfile = loadfile,
  dofile = dofile,
  io_open = io.open,
  io_popen = io.popen,
  os_rename = os.rename,
  loadlib = package.loadlib,
}

function compat.fix_path(path)
  path = path:gsub("\\", "/")
  path = path:gsub("//+", "/")
  return path
end
local fix_path = compat.fix_path

local function fixed(value)
  if type(value) == "string" then
    return fix_path(value)
  end
  return value
end

local function install_paths()
  loadfile = function(path, ...) return original.loadfile(fixed(path), ...) end
  dofile = function(path) return original.dofile(fixed(path)) end
  io.open = function(path, mode) return original.io_open(fixed(path), mode) end
  os.rename = function(from, to) return original.os_rename(fixed(from), fixed(to)) end
end

local function install_memory(platform, api)
  memory = {
    readbyte = function(addr) return platform.read8(addr) end,
    readbyteunsigned = function(addr) return platform.read8(addr) end,
    readbytesigned = function(addr)
      local value = platform.read8(addr)
      return value >= 0x80 and value - 0x100 or value
    end,
    readword = function(addr) return platform.read16(addr) end,
    readwordunsigned = function(addr) return platform.read16(addr) end,
    readwordsigned = function(addr)
      local value = platform.read16(addr)
      return value >= 0x8000 and value - 0x10000 or value
    end,
    readdword = function(addr) return platform.read32(addr) end,
    readdwordunsigned = function(addr) return platform.read32(addr) end,
    readbyterange = function(addr, count) return platform.read_range(addr, count) end,
    gbromreadbyte = function(offset) return platform.rom_read8(offset) end,
    gbromreadword = function(offset) return platform.rom_read16(offset) end,
    registerexec = function(addr, fn) api.register_exec(addr, fn) end,
    -- GBA-only upstream code registers write hooks; nothing on the Game Boy
    -- path needs them, so they are accepted and logged.
    registerwrite = function(addr)
      platform.log(string.format("memory.registerwrite(0x%x) is not supported here", addr))
    end,
  }
end

local function install_emu(platform)
  emu = {
    frameadvance = coroutine.yield,
    platform = function() return platform.platform_id() end,
  }
  input = {
    read = function() return platform.held_keys() end,
  }
end

local function wait_reply(platform, id)
  while true do
    local reply = platform.take_reply(id)
    if reply ~= nil then
      return reply
    end
    coroutine.yield()
  end
end

local function install_modules(platform)
  package.loaded["tolk"] = nil
  package.preload["tolk"] = function()
    return {
      output = function(text) platform.speak(text) end,
      silence = function() platform.silence() end,
    }
  end

  package.loaded["win-controls"] = nil
  package.preload["win-controls"] = function()
    local controls = {}
    function controls.inputbox(title, caption, default)
      local id = platform.prompt_text(title or "", caption or "", default or "")
      local reply = wait_reply(platform, id)
      if reply.ok then
        return reply.values[1] or ""
      end
      return nil
    end
    function controls.combobox(title, caption, list, data)
      list = list or {}
      data = data or 1
      local multi = type(data) == "table"
      local id = platform.prompt_choice(title or "", caption or "", list, multi, data)
      local reply = wait_reply(platform, id)
      if not reply.ok then
        return nil
      end
      if multi then
        local indices = {}
        for _, value in ipairs(reply.values) do
          indices[#indices + 1] = tonumber(value)
        end
        return indices
      end
      return tonumber(reply.values[1])
    end
    return controls
  end

  -- Upstream runs assert(package.loadlib("audio.dll", "luaopen_audio"))() and
  -- relies on the opener defining the global `audio`, as the DLL did.
  local audio = {
    play = function(path, loop, pan, vol)
      local looping = loop == true or (type(loop) == "number" and loop ~= 0)
      return platform.play_sound(fix_path(path), looping, pan or 0, vol or 100)
    end,
    stop = function(id) platform.stop_sound(id) end,
    pitch = function(value, id) platform.set_pitch(id, value) end,
  }
  package.loadlib = function(libname, funcname)
    if type(libname) == "string" and libname:lower():match("audio%.dll$") then
      return function()
        _G.audio = audio
        return audio
      end
    end
    return original.loadlib(libname, funcname)
  end

  -- mGBA's Lua has no io.popen; upstream only uses it for hack ROM setup.
  io.popen = function(command)
    platform.log("io.popen is not available here: " .. tostring(command))
    return {
      lines = function() return function() return nil end end,
      read = function() return nil end,
      close = function() return true end,
    }
  end
end

local function exec_state(platform)
  local map, x, y = _G.RAM_MAP_NUMBER, _G.RAM_PLAYER_X, _G.RAM_PLAYER_Y
  if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
    return nil
  end
  return platform.read8(map) .. "," .. platform.read8(x) .. "," .. platform.read8(y)
end

-- Returns the api table the runner drives (reset_handler, exec_handlers, poll_exec).
function compat.install(platform)
  local api = {
    platform = platform,
    reset_handler = nil,
    exec_handlers = {},
    breakpoints = {},
    last_exec_state = nil,
  }

  function api.register_exec(addr, fn)
    if RESET_ADDRESSES[addr] then
      api.reset_handler = fn
      return
    end
    if fn == nil then
      api.exec_handlers[addr] = nil
      api.breakpoints[addr] = nil
      return
    end
    local armed = platform.set_breakpoint(addr, function()
      if api.breakpoints[addr] == fn then
        fn()
      end
    end)
    if armed then
      api.breakpoints[addr] = fn
    else
      api.exec_handlers[addr] = fn
    end
  end

  -- Without breakpoints, "the footstep routine ran" is approximated by "the
  -- player's map or position changed" (upstream's own handler re-checks on_map()).
  function api.poll_exec()
    if next(api.exec_handlers) == nil then
      api.last_exec_state = nil
      return
    end
    local state = exec_state(platform)
    if state == nil then
      return
    end
    local previous = api.last_exec_state
    api.last_exec_state = state
    if previous == nil or previous == state then
      return
    end
    for addr, handler in pairs(api.exec_handlers) do
      local ok, err = pcall(handler)
      if not ok then
        platform.log(string.format("exec handler at 0x%x failed: %s", addr, tostring(err)))
      end
    end
  end

  lua51.install()
  _G.bit = bit
  install_paths()
  install_memory(platform, api)
  install_emu(platform)
  install_modules(platform)
  return api
end

return compat
