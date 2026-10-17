-- A stand-in for platform/mgba.lua: records every call and lets tests supply
-- memory contents, held keys and prompt replies.
local fake = {}

function fake.new(opts)
  opts = opts or {}
  local f = {
    calls = {},
    logs = {},
    replies = {},
    held = opts.held or {},
    mem = opts.mem or {},
    rom = opts.rom or "",
    id = opts.platform_id or 1,
    breakpoints = opts.breakpoints or false,
    last_prompt_id = 0,
    last_sound_id = 0,
  }

  local function record(...)
    f.calls[#f.calls + 1] = table.pack(...)
    f.calls[#f.calls].n = nil
  end

  local function byte(addr)
    return f.mem[addr] or 0
  end

  function f.read8(addr) return byte(addr) end
  function f.read16(addr) return byte(addr) | (byte(addr + 1) << 8) end
  function f.read32(addr)
    return byte(addr) | (byte(addr + 1) << 8) | (byte(addr + 2) << 16) | (byte(addr + 3) << 24)
  end
  function f.read_range(addr, n)
    local bytes = {}
    for i = 0, n - 1 do
      bytes[i + 1] = byte(addr + i)
    end
    return bytes
  end
  function f.rom_read8(offset) return f.rom:byte(offset + 1) or 0 end
  function f.rom_read16(offset) return f.rom_read8(offset) | (f.rom_read8(offset + 1) << 8) end
  function f.platform_id() return f.id end
  function f.speak(text) record("speak", text) end
  function f.silence() record("silence") end
  function f.play_sound(path, loop, pan, vol)
    record("play_sound", path, loop, pan, vol)
    f.last_sound_id = f.last_sound_id + 1
    return f.last_sound_id
  end
  function f.stop_sound(id) record("stop_sound", id) end
  function f.set_pitch(id, value) record("set_pitch", id, value) end
  function f.held_keys()
    local copy = {}
    for k, v in pairs(f.held) do copy[k] = v end
    return copy
  end
  function f.prompt_text(title, caption, default)
    f.last_prompt_id = f.last_prompt_id + 1
    record("prompt_text", title, caption, default)
    return f.last_prompt_id
  end
  function f.prompt_choice(title, caption, items, multi, default)
    f.last_prompt_id = f.last_prompt_id + 1
    record("prompt_choice", title, caption, items, multi, default)
    return f.last_prompt_id
  end
  function f.take_reply(id)
    local reply = f.replies[id]
    f.replies[id] = nil
    return reply
  end
  function f.set_breakpoint(addr, fn)
    record("set_breakpoint", addr)
    return f.breakpoints
  end
  function f.log(text) f.logs[#f.logs + 1] = text end

  return f
end

return fake
