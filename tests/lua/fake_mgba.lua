-- Installs stand-ins for mGBA's Lua globals (emu, callbacks, console, socket,
-- and the 0.11-only input object) plus os.getenv/os.execute overrides, so
-- platform/mgba.lua can be exercised outside the emulator.
local fake = {}

function fake.install(opts)
  opts = opts or {}
  local f = {
    bus = opts.bus or {},
    rom = opts.rom or "",
    id = opts.platform_id or 1,
    env = opts.env or {},
    logs = {},
    executed = {},
    registered = {},
    breakpoints_set = {},
    next_callback_id = 0,
  }
  local saved = {
    emu = rawget(_G, "emu"), callbacks = rawget(_G, "callbacks"), console = rawget(_G, "console"),
    socket = rawget(_G, "socket"), input = rawget(_G, "input"),
    getenv = os.getenv, execute = os.execute,
  }

  local function byte(addr) return f.bus[addr] or 0 end

  -- With main_thread_only, count API calls made from inside a coroutine, which
  -- mGBA 0.10.5 rejects.
  f.main_thread_violations = 0
  local function check_thread()
    local _, is_main = coroutine.running()
    if opts.main_thread_only and not is_main then
      f.main_thread_violations = f.main_thread_violations + 1
    end
  end

  local emu = {}
  function emu:read8(addr) check_thread(); return byte(addr) end
  function emu:read16(addr) check_thread(); return byte(addr) | (byte(addr + 1) << 8) end
  function emu:read32(addr)
    check_thread()
    return byte(addr) | (byte(addr + 1) << 8) | (byte(addr + 2) << 16) | (byte(addr + 3) << 24)
  end
  function emu:readRange(addr, n)
    check_thread()
    local chars = {}
    for i = 0, n - 1 do chars[#chars + 1] = string.char(byte(addr + i)) end
    return table.concat(chars)
  end
  function emu:platform() check_thread(); return f.id end
  emu.memory = { cart0 = {} }
  function emu.memory.cart0:read8(offset) check_thread(); return f.rom:byte(offset + 1) or 0 end
  function emu.memory.cart0:read16(offset)
    return emu.memory.cart0:read8(offset) | (emu.memory.cart0:read8(offset + 1) << 8)
  end
  function emu.memory.cart0:readRange(offset, n) check_thread(); return f.rom:sub(offset + 1, offset + n) end
  f.breakpoints_cleared = {}
  if opts.breakpoints then
    function emu:setBreakpoint(fn, addr)
      check_thread()
      f.breakpoints_set[#f.breakpoints_set + 1] = addr
      return #f.breakpoints_set
    end
    function emu:clearBreakpoint(id)
      f.breakpoints_cleared[#f.breakpoints_cleared + 1] = id
    end
  end

  local callbacks = {}
  function callbacks:add(name, fn)
    f.next_callback_id = f.next_callback_id + 1
    f.registered[f.next_callback_id] = { name = name, fn = fn }
    return f.next_callback_id
  end
  function callbacks:remove(id)
    f.registered[id] = nil
  end

  -- Invoke every callback registered under `name`.
  function f:fire(name, ...)
    for _, entry in pairs(f.registered) do
      if entry.name == name then entry.fn(...) end
    end
  end

  local console = {}
  function console:log(text) check_thread(); f.logs[#f.logs + 1] = text end

  _G.pokemon_access_mgba_runtime = nil
  _G.emu = emu
  _G.callbacks = callbacks
  _G.console = console
  _G.socket = opts.socket
  _G.input = opts.key_events and {} or nil
  os.getenv = function(name) return f.env[name] end
  os.execute = function(command)
    f.executed[#f.executed + 1] = command
    return true
  end

  function f.remove()
    _G.pokemon_access_mgba_runtime = nil
    _G.emu, _G.callbacks, _G.console, _G.socket, _G.input =
      saved.emu, saved.callbacks, saved.console, saved.socket, saved.input
    os.getenv, os.execute = saved.getenv, saved.execute
  end

  return f
end

return fake
