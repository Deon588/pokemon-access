local check = require("check")
local fake_platform = require("fake_platform")
local compat = require("compat.vba_api")

local fake = fake_platform.new{
  mem = { [0xC000] = 0x42, [0xC002] = 0x37, [0xC010] = 0x34, [0xC011] = 0x12, [0xC020] = 0xFF },
  rom = string.rep("\0", 0x14e) .. "\x91\xe6",
  held = { T = true },
}
local api = compat.install(fake)

-- memory
check.eq(memory.readbyte(0xC000), 0x42, "readbyte")
check.eq(memory.readbyteunsigned(0xC020), 0xFF, "readbyteunsigned")
check.eq(memory.readbytesigned(0xC020), -1, "readbytesigned")
check.eq(memory.readword(0xC010), 0x1234, "readword is little-endian")
check.eq(memory.readbyterange(0xC000, 3), { 0x42, 0, 0x37 }, "readbyterange is a 1-based table")
check.eq(memory.gbromreadbyte(0x14e), 0x91, "gbromreadbyte")
check.eq(memory.gbromreadword(0x14e), 0xe691, "gbromreadword is little-endian")

-- emu and input
check.eq(emu.platform(), 1, "emu.platform")
local co = coroutine.wrap(function() emu.frameadvance(); return "after" end)
check.eq(co(), nil, "frameadvance yields")
check.eq(co(), "after", "and resumes")
check.eq(input.read(), { T = true }, "input.read mirrors the held keys")
local keys = input.read()
keys.Z = true
check.eq(input.read(), { T = true }, "input.read returns a copy")

-- Lua 5.1 polyfills
check.eq(bit.band(3, 1), 1, "bit is installed")
check.truthy(unpack, "unpack is installed")

-- paths
check.eq(compat.fix_path("/a/b/\\message\\en.lua"), "/a/b/message/en.lua", "backslashes become slashes")
check.eq(compat.fix_path("C:\\x\\y"), "C:/x/y", "Windows style paths")
check.eq(type(loadfile("tests\\lua\\check.lua")), "function", "loadfile translates backslashes")
local fp = io.open("tests\\lua\\check.lua", "rb")
check.truthy(fp, "io.open translates backslashes")
if fp then fp:close() end
check.truthy(os.rename("tests\\lua\\check.lua", "tests\\lua\\check.lua"), "os.rename translates backslashes")

-- speech
local tolk = require("tolk")
tolk.output("hi")
tolk.silence()
check.eq(fake.calls[#fake.calls - 1], { "speak", "hi" }, "tolk.output speaks")
check.eq(fake.calls[#fake.calls], { "silence" }, "tolk.silence silences")

-- audio through package.loadlib
local opener = assert(package.loadlib("C:\\x\\audio.dll", "luaopen_audio"))
opener()
check.eq(type(audio), "table", "the opener installs the global audio table like the DLL did")
check.eq(audio.play("/x/sounds\\gb\\s_grass.wav", 0, -100, 30), 1, "audio.play returns the sound id")
check.eq(fake.calls[#fake.calls], { "play_sound", "/x/sounds/gb/s_grass.wav", false, -100, 30 }, "audio.play translates the path and the loop flag")
audio.play("/x/a.wav", 1, 0, 50)
check.eq(fake.calls[#fake.calls][3], true, "loop 1 means looping")
audio.play("/x/a.wav", 0, -88.888888888889, 30.5)
check.eq(fake.calls[#fake.calls], { "play_sound", "/x/a.wav", false, -88, 30 }, "float pan and volume are truncated to integers like the C API took")
audio.stop(1)
check.eq(fake.calls[#fake.calls], { "stop_sound", 1 }, "audio.stop")
audio.pitch(1.5, 1)
check.eq(fake.calls[#fake.calls], { "set_pitch", 1, 1.5 }, "audio.pitch(value, id)")
local other, msg = package.loadlib("other.so", "f")
check.eq(other, nil, "other libraries fall through to the real loadlib")
check.eq(type(msg), "string", "with its error message")

-- dialogs
local controls = require("win-controls")
local dialog = coroutine.create(function() return controls.inputbox("T", "C", "d") end)
coroutine.resume(dialog)
check.eq(coroutine.status(dialog), "suspended", "inputbox waits for the reply")
check.eq(fake.calls[#fake.calls], { "prompt_text", "T", "C", "d" }, "inputbox sends the prompt")
fake.replies[fake.last_prompt_id] = { ok = true, values = { "Blue" } }
local _, value = coroutine.resume(dialog)
check.eq(value, "Blue", "inputbox returns the typed text")

dialog = coroutine.create(function() return controls.inputbox("T", "C") end)
coroutine.resume(dialog)
fake.replies[fake.last_prompt_id] = { ok = false, values = {} }
_, value = coroutine.resume(dialog)
check.eq(value, nil, "cancelled inputbox returns nil")

dialog = coroutine.create(function() return controls.combobox("T", "C", { "a", "b", "c" }, 2) end)
coroutine.resume(dialog)
check.eq(fake.calls[#fake.calls], { "prompt_choice", "T", "C", { "a", "b", "c" }, false, 2 }, "single choice prompt")
fake.replies[fake.last_prompt_id] = { ok = true, values = { "2" } }
_, value = coroutine.resume(dialog)
check.eq(value, 2, "single choice returns the index")

dialog = coroutine.create(function() return controls.combobox("T", "C", { "a", "b", "c" }, { 1 }) end)
coroutine.resume(dialog)
check.eq(fake.calls[#fake.calls][5], true, "a table default means multi select")
fake.replies[fake.last_prompt_id] = { ok = true, values = { "1", "3" } }
_, value = coroutine.resume(dialog)
check.eq(value, { 1, 3 }, "multi choice returns the indices")

-- registerexec: reset addresses and the footstep hook emulation
local function on_reset() end
memory.registerexec(0x100, on_reset)
check.eq(api.reset_handler, on_reset, "0x100 registers the reset handler")
memory.registerexec(0x8000000, on_reset)
check.eq(api.reset_handler, on_reset, "0x8000000 too")

local fired = 0
memory.registerexec(0x603, function() fired = fired + 1 end)
check.eq(type(api.exec_handlers[0x603]), "function", "other addresses are emulated by polling")
RAM_MAP_NUMBER, RAM_PLAYER_Y, RAM_PLAYER_X = 0xD35E, 0xD361, 0xD362
fake.mem[0xD362] = 5
api.poll_exec()
check.eq(fired, 0, "the first poll only records the position")
api.poll_exec()
check.eq(fired, 0, "no change, no call")
fake.mem[0xD362] = 6
api.poll_exec()
check.eq(fired, 1, "a position change fires the handler once")
memory.registerexec(0x603, nil)
check.eq(api.exec_handlers[0x603], nil, "nil unregisters")

memory.registerexec(0x603, function() error("hook boom") end)
fake.mem[0xD362] = 7
api.poll_exec()
check.eq(api.exec_handlers[0x603], nil, "a failing hook is turned off")
check.eq(fake.calls[#fake.calls], { "speak", "A Pokemon Access handler failed and was turned off. See the log." }, "and the player hears about it once")
check.truthy(fake.logs[#fake.logs]:find("hook boom", 1, true), "with the error in the log")
local speaks_before = #fake.calls
fake.mem[0xD362] = 8
api.poll_exec()
check.eq(#fake.calls, speaks_before, "later position changes stay quiet")

local with_breakpoints = fake_platform.new{ breakpoints = true }
local api2 = compat.install(with_breakpoints)
memory.registerexec(0x603, function() end)
check.eq(with_breakpoints.calls[#with_breakpoints.calls], { "set_breakpoint", 0x603 }, "a real breakpoint is preferred")
check.eq(api2.exec_handlers[0x603], nil, "and then nothing is polled")

-- io.popen stub
local handle = io.popen("dir /b x")
local count = 0
for _ in handle:lines() do count = count + 1 end
check.eq(count, 0, "io.popen yields no lines")
check.truthy(handle:close(), "and closes")
check.truthy(with_breakpoints.logs[#with_breakpoints.logs]:find("popen"), "and logs the attempt")
check.done()
