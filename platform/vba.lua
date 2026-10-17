-- The platform layer on VBA-ReRecording (Windows, LuaJIT), where upstream's
-- original dependencies (Tolk, win-controls, audio.dll) exist. It exists so
-- that the same compat/runner code could run there and upstream could adopt
-- the platform layer; it cannot be exercised on macOS and is only parsed here.
local V = {}
V.name = "vba"

local tolk, controls, audio
local replies = {}
local next_prompt_id = 0
local frame_hooks = {}

function V.setup()
  tolk = require("tolk")
  controls = require("win-controls")
  audio = assert(package.loadlib("audio.dll", "luaopen_audio"))()
end

function V.read8(addr) return memory.readbyteunsigned(addr) end
function V.read16(addr) return memory.readwordunsigned(addr) end
function V.read32(addr) return memory.readdwordunsigned(addr) end
function V.read_range(addr, count) return memory.readbyterange(addr, count) end
function V.rom_read8(offset) return memory.gbromreadbyte(offset) end
function V.rom_read16(offset) return memory.gbromreadword(offset) end
function V.platform_id() return emu.platform() end

function V.speak(text) tolk.output(text) end
function V.silence() tolk.silence() end

function V.play_sound(path, loop, pan, vol) return audio.play(path, loop and 1 or 0, pan, vol) end
function V.stop_sound(id) audio.stop(id) end
function V.set_pitch(id, value) audio.pitch(value, id) end

function V.held_keys()
  local keys = input.read()
  keys.xmouse = nil
  keys.ymouse = nil
  return keys
end

-- Dialogs are modal on VBA, so the reply is available immediately.
local function store(id, ok, values)
  replies[id] = { ok = ok, values = values }
  return id
end

function V.prompt_text(title, caption, default)
  next_prompt_id = next_prompt_id + 1
  local text = controls.inputbox(title, caption, default)
  return store(next_prompt_id, text ~= nil, { text })
end

function V.prompt_choice(title, caption, items, multi, default)
  next_prompt_id = next_prompt_id + 1
  local result = controls.combobox(title, caption, items, default)
  if result == nil then
    return store(next_prompt_id, false, {})
  end
  local values = {}
  if multi then
    for i, index in ipairs(result) do values[i] = tostring(index) end
  else
    values[1] = tostring(result)
  end
  return store(next_prompt_id, true, values)
end

function V.take_reply(id)
  local reply = replies[id]
  replies[id] = nil
  return reply
end

function V.set_breakpoint(addr, fn)
  memory.registerexec(addr, fn)
  return true
end

function V.log(text) print(text) end

-- VBA has no frame callback: the main loop calls V.frame() after emu.frameadvance().
function V.on_frame(fn) frame_hooks[#frame_hooks + 1] = fn end
function V.frame()
  for _, fn in ipairs(frame_hooks) do fn() end
end

function V.on_reset(fn)
  memory.registerexec(0x100, fn)
  memory.registerexec(0x8000000, fn)
end

function V.poll() end
function V.end_frame() end
function V.shutdown() end

return V
