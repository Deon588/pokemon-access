local check = require("check")
local fake_mgba = require("fake_mgba")
local fake_socket = require("fake_socket")

-- mGBA 0.10.5 with a helper listening
local lib = fake_socket.new()
local fake = fake_mgba.install{
  bus = { [0xC000] = 0x42, [0xC001] = 0x10 },
  rom = string.rep("\0", 0x134) .. "PROBE",
  env = { POKEMON_ACCESS_PORT = "48890" },
  socket = lib,
}
local M = require("platform.mgba")
M.setup{}
check.eq(M.has_key_events, false, "0.10.5 exposes no input object")
check.eq(M.key_source, "helper", "so keys come from the helper")
check.truthy(M.connected(), "connects to the port from the environment")
check.eq(lib.sock.port, 48890, "to the right port")

M.send_hello("Lua 5.4")
check.eq(lib.sent[#lib.sent], "HELLO\t1\thelper\tLua 5.4\t\n", "HELLO carries protocol version, key source, info and an empty token")

M.speak("a")
M.speak("b")
M.end_frame()
check.eq(lib.sent[#lib.sent], "SPEAK\t0\ta\\nb\n", "speech is batched per frame")
M.silence()
M.end_frame()
check.eq(lib.sent[#lib.sent], "SILENCE\n", "a bare silence becomes SILENCE")
M.silence()
M.speak("x")
M.end_frame()
check.eq(lib.sent[#lib.sent], "SPEAK\t1\tx\n", "silence followed by speech is an interrupting SPEAK")

check.eq(M.play_sound("/p.wav", false, -100, 30), 1, "sound ids start at 1")
check.eq(lib.sent[#lib.sent], "SOUND\t1\t/p.wav\t0\t-100\t30\n", "SOUND message")
M.stop_sound(1)
check.eq(lib.sent[#lib.sent], "SOUND_STOP\t1\n", "SOUND_STOP message")
M.set_pitch(1, 1.5)
check.eq(lib.sent[#lib.sent], "SOUND_PITCH\t1\t1.5\n", "SOUND_PITCH message")

check.eq(M.prompt_text("t", "c", "d"), 1, "prompt ids start at 1")
check.eq(lib.sent[#lib.sent], "PROMPT_TEXT\t1\tt\tc\td\n", "PROMPT_TEXT message")
check.eq(M.prompt_choice("t", "c", { "a", "b" }, true, { 1, 2 }), 2, "prompt ids increase")
check.eq(lib.sent[#lib.sent], "PROMPT_CHOICE\t2\tt\tc\t1\t1,2\ta\tb\n", "multi choice with default indices")
M.prompt_choice("t", "c", { "a" }, false, 1)
check.eq(lib.sent[#lib.sent], "PROMPT_CHOICE\t3\tt\tc\t0\t1\ta\n", "single choice with a default index")

lib:push("KEY\tDOWN\tshift+H\n")
M.poll()
check.eq(M.held_keys(), { H = true, shift = true }, "KEY DOWN presses the chord")
lib:push("KEY\tUP\tshift+H\n")
M.poll()
check.eq(M.held_keys(), {}, "KEY UP releases it")
lib:push("REPLY\t1\tOK\tBlue\n")
M.poll()
check.eq(M.take_reply(1), { ok = true, values = { "Blue" } }, "REPLY OK stores the values")
check.eq(M.take_reply(1), nil, "a reply is taken once")
lib:push("REPLY\t2\tCANCEL\n")
M.poll()
check.eq(M.take_reply(2), { ok = false, values = {} }, "REPLY CANCEL")

check.eq(M.read8(0xC000), 0x42, "read8 uses the bus")
check.eq(M.read16(0xC000), 0x1042, "read16")
check.eq(M.read_range(0xC000, 2), { 0x42, 0x10 }, "read_range is a 1-based table")
check.eq(M.rom_read8(0x134), string.byte("P"), "rom_read8 uses cart0")
check.eq(M.rom_read16(0x134), string.byte("P") | (string.byte("R") << 8), "rom_read16")
check.eq(M.platform_id(), 1, "platform_id")

M.log("note")
check.eq(lib.sent[#lib.sent], "LOG\tinfo\tnote\n", "log goes to the helper")
check.eq(fake.logs[#fake.logs], "note", "and to the console")

local frames = 0
M.on_frame(function() frames = frames + 1 end)
fake:fire("frame")
check.eq(frames, 1, "on_frame registers a frame callback")
local resets = 0
M.on_reset(function() resets = resets + 1 end)
fake:fire("reset")
fake:fire("start")
check.eq(resets, 2, "on_reset covers reset and start")
check.eq(M.set_breakpoint(0x603, function() end), false, "0.10.5 has no breakpoints")

M.shutdown()
fake:fire("frame")
check.eq(frames, 1, "shutdown removes the callbacks")
check.eq(M.connected(), false, "shutdown closes the link")
fake.remove()

-- mGBA 0.11: key events in Lua, breakpoints available
local lib2 = fake_socket.new()
local fake2 = fake_mgba.install{ key_events = true, breakpoints = true, env = { POKEMON_ACCESS_PORT = "48890", POKEMON_ACCESS_TOKEN = "secret" }, socket = lib2 }
M.setup{}
check.eq(M.has_key_events, true, "0.11 exposes the input object")
check.eq(M.key_source, "lua", "so keys come from Lua events")
fake2:fire("key", { key = 72, state = 1, modifiers = 3 })
check.eq(M.held_keys(), { H = true, shift = true }, "raw key events feed the tracker")
check.eq(M.set_breakpoint(0x603, function() end), true, "breakpoints are armed when available")
check.eq(fake2.breakpoints_set, { 0x603 }, "at the requested address")
M.send_hello("Lua 5.4")
check.eq(lib2.sent[#lib2.sent], "HELLO\t1\tlua\tLua 5.4\tsecret\n", "HELLO reports the lua key source and the token from the environment")
M.shutdown()
fake2.remove()

-- No helper: fallbacks and reconnection
local lib3 = fake_socket.new()
lib3.refuse = true
local fake3 = fake_mgba.install{ env = { POKEMON_ACCESS_PORT = "48890" }, socket = lib3 }
M.setup{}
check.eq(M.connected(), false, "refused connection")
M.speak("x")
M.end_frame()
check.truthy(fake3.executed[#fake3.executed]:find("/usr/bin/say -- 'x'", 1, true), "speech falls back to say")
M.silence()
M.end_frame()
check.truthy(fake3.executed[#fake3.executed]:find("killall say", 1, true), "silence kills say")
M.play_sound("/p.wav", false, 0, 50)
check.truthy(fake3.executed[#fake3.executed]:find("afplay", 1, true), "sounds fall back to afplay")
local id = M.prompt_text("t", "c", "d")
check.eq(M.take_reply(id), { ok = false, values = {} }, "prompts are cancelled without a helper")
M.send_hello("Lua 5.4")
lib3.refuse = false
for _ = 1, 299 do M.poll() end
check.eq(M.connected(), false, "no reconnect before 300 frames")
M.poll()
check.eq(M.connected(), true, "reconnects after 300 frames")
check.eq(lib3.sent[#lib3.sent], "HELLO\t1\thelper\tLua 5.4\t\n", "and repeats HELLO")
lib3.sock.callbacks.error("gone")
check.eq(M.connected(), false, "a socket error disconnects")
M.shutdown()
fake3.remove()
check.done()
