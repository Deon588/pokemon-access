-- Pokémon Access mGBA API probe.
-- Loaded inside mGBA. Records what the scripting runtime offers and writes the
-- findings to <out_dir>/results.txt so they can be inspected from a terminal.
-- Configuration comes from probe_config.lua next to this file (written by run_probe.sh).

local source = debug.getinfo(1, "S").source
local script_path = source:sub(2)
local script_dir = script_path:match("(.*[/\\])") or "./"

local cfg = dofile(script_dir .. "probe_config.lua")
local out_dir = cfg.out_dir

local lines = {}
local function rec(fmt, ...)
	local ok, text = pcall(string.format, fmt, ...)
	if not ok then text = fmt .. " <format error: " .. tostring(text) .. ">" end
	lines[#lines + 1] = text
	console:log(text)
end
local function try(label, fn)
	local ok, result = pcall(fn)
	if ok then
		rec("%s = %s", label, tostring(result))
	else
		rec("%s -> ERROR %s", label, tostring(result))
	end
	return ok, result
end
local function flush(name)
	local fh = io.open(out_dir .. "/" .. name, "w")
	if fh then
		fh:write(table.concat(lines, "\n"), "\n")
		fh:close()
	end
end
local function hex_bytes(s)
	local t = {}
	for i = 1, #s do t[#t + 1] = string.format("%02x", s:byte(i)) end
	return table.concat(t, " ")
end

rec("== runtime ==")
rec("_VERSION = %s", _VERSION)
rec("script source = %s", source)
rec("script_dir = %s", script_dir)
rec("package.path = %s", tostring(package.path))
for _, name in ipairs({ "io", "os", "package", "debug", "require", "dofile", "loadfile",
	"socket", "input", "storage", "script", "image", "canvas", "util", "callbacks", "console", "emu", "C", "bit", "unpack", "module", "setfenv" }) do
	rec("global %s: %s", name, type(_G[name]))
end
try("os.getenv('HOME')", function() return os.getenv("HOME") end)
try("os.getenv('POKEMON_ACCESS_PROBE_OUT')", function() return os.getenv("POKEMON_ACCESS_PROBE_OUT") end)
try("os.execute touch", function() return os.execute("touch '" .. out_dir .. "/os_execute_ok'") end)
try("io.popen echo", function()
	local p = io.popen("echo popen_ok")
	local s = p:read("*a")
	p:close()
	return s
end)
try("math.pow", function() return math.pow(2, 3) end)
try("string.format %%d with float", function() return string.format("%d", 3 / 2) end)
try("table.unpack", function() return table.unpack({ 1, 2 }) end)

rec("== emu ==")
try("emu:platform()", function() return emu:platform() end)
try("C.PLATFORM.GB", function() return C.PLATFORM.GB end)
try("C.PLATFORM.GBA", function() return C.PLATFORM.GBA end)
try("emu:getGameTitle()", function() return emu:getGameTitle() end)
try("emu:getGameCode()", function() return emu:getGameCode() end)
try("emu:romSize()", function() return emu:romSize() end)
try("emu:checksum(C.CHECKSUM.CRC32)", function() return hex_bytes(emu:checksum(C.CHECKSUM.CRC32)) end)
try("emu:currentFrame()", function() return emu:currentFrame() end)
for _, name in ipairs({ "setBreakpoint", "setWatchpoint", "setRangeWatchpoint", "clearBreakpoint", "readRegister", "read8", "readRange", "getKeys", "addKey", "screenshot" }) do
	rec("emu.%s: %s", name, type(emu[name]))
end
rec("== memory domains ==")
for name, domain in pairs(emu.memory) do
	rec("domain %s base=0x%x bound=0x%x size=0x%x", name, domain:base(), domain:bound(), domain:size())
end

rec("== callbacks ==")
local counts = { frame = 0, keysRead = 0, start = 0, reset = 0, key = 0, crashed = 0, stop = 0 }
local key_events = {}
for _, name in ipairs({ "frame", "keysRead", "start", "reset", "crashed", "stop" }) do
	try("callbacks:add(" .. name .. ")", function()
		return callbacks:add(name, function() counts[name] = counts[name] + 1 end)
	end)
end
try("callbacks:add(key) [0.11 only]", function()
	return callbacks:add("key", function(ev)
		counts.key = counts.key + 1
		key_events[#key_events + 1] = string.format("key=%s state=%s mods=%s", tostring(ev.key), tostring(ev.state), tostring(ev.modifiers))
	end)
end)

rec("== sockets ==")
local client
try("socket.connect client", function()
	local sock, err = socket.connect("127.0.0.1", cfg.client_port)
	if not sock then error(tostring(err)) end
	client = sock
	return sock:send("hello from mgba lua\n")
end)
local server, server_received = nil, {}
try("socket.bind server", function()
	local sock, err = socket.bind("127.0.0.1", cfg.server_port)
	if not sock then error(tostring(err)) end
	local ok, lerr = sock:listen()
	if lerr then error(tostring(lerr)) end
	server = sock
	sock:add("received", function()
		local conn, aerr = server:accept()
		if not conn then return end
		conn:add("received", function()
			while true do
				local data, rerr = conn:receive(1024)
				if data then
					server_received[#server_received + 1] = data
				else
					if rerr ~= socket.ERRORS.AGAIN then conn:close() end
					return
				end
			end
		end)
	end)
	return "listening on " .. cfg.server_port
end)

flush("results.txt")

local function memory_checks()
	rec("== memory reads (frame %d) ==", emu:currentFrame())
	try("emu:read8(0xC000) expect 0x42", function() return string.format("0x%02x", emu:read8(0xC000)) end)
	try("emu:read8(0xD000) expect 0x37", function() return string.format("0x%02x", emu:read8(0xD000)) end)
	try("emu:read8(0xFF80) expect 0x99", function() return string.format("0x%02x", emu:read8(0xFF80)) end)
	try("emu:read16(0xC010) expect 0x1234", function() return string.format("0x%04x", emu:read16(0xC010)) end)
	try("emu:read8(0xC001) counter", function() return emu:read8(0xC001) end)
	try("emu:readRange(0xC000, 4)", function() return hex_bytes(emu:readRange(0xC000, 4)) end)
	try("emu:read8(0x134) rom title byte expect 0x50 'P'", function() return string.format("0x%02x", emu:read8(0x134)) end)
	try("emu.memory.wram:read8(0) expect 0x42 if offset-based", function() return string.format("0x%02x", emu.memory.wram:read8(0)) end)
	try("emu.memory.wram:read8(0xC000) bus-based?", function() return string.format("0x%02x", emu.memory.wram:read8(0xC000)) end)
	try("emu.memory.hram:read8(0) expect 0x99 if offset-based", function() return string.format("0x%02x", emu.memory.hram:read8(0)) end)
	try("emu.memory.cart0:readRange(0x134, 5) expect PROBE", function() return emu.memory.cart0:readRange(0x134, 5) end)
	try("emu.memory.cart0:readRange(0x4100, 6) expect PROBE1", function() return emu.memory.cart0:readRange(0x4100, 6) end)
	try("emu.memory.cart0:readRange(0x8100, 6) expect PROBE2 (linear bank 2)", function() return emu.memory.cart0:readRange(0x8100, 6) end)
	try("emu.memory.cart0:readRange(0xC100, 6) expect PROBE3 (linear bank 3)", function() return emu.memory.cart0:readRange(0xC100, 6) end)
	try("emu.memory.cart0:read8(0x8100) expect 0x50", function() return string.format("0x%02x", emu.memory.cart0:read8(0x8100)) end)
	try("emu:read8(0x8100) bus read of VRAM (not ROM)", function() return string.format("0x%02x", emu:read8(0x8100)) end)
	try("timing: 360x read8 + readRange(360)", function()
		local t0 = os.clock()
		for _ = 1, 360 do emu:read8(0xC3A0) end
		local t1 = os.clock()
		emu:readRange(0xC3A0, 360)
		local t2 = os.clock()
		return string.format("read8 loop %.3f ms, readRange %.3f ms", (t1 - t0) * 1000, (t2 - t1) * 1000)
	end)
end

local last_mask, mask_changes = nil, {}
callbacks:add("keysRead", function()
	local mask = emu:getKeys()
	if mask ~= last_mask then
		last_mask = mask
		mask_changes[#mask_changes + 1] = string.format("f%d:%d", emu:currentFrame(), mask)
	end
end)

callbacks:add("frame", function()
	local mask = emu:getKeys()
	if mask ~= last_mask then
		last_mask = mask
		mask_changes[#mask_changes + 1] = string.format("f%d:%d", emu:currentFrame(), mask)
	end
end)

local first_frame = emu:currentFrame()
local reported = {}
callbacks:add("frame", function()
	local elapsed = emu:currentFrame() - first_frame
	if elapsed == 60 and not reported[60] then
		reported[60] = true
		memory_checks()
		rec("counts after 60 frames: frame=%d keysRead=%d start=%d reset=%d key=%d", counts.frame, counts.keysRead, counts.start, counts.reset, counts.key)
		flush("results.txt")
	elseif elapsed == 600 and not reported[600] then
		reported[600] = true
		rec("== after 600 frames ==")
		rec("counts: frame=%d keysRead=%d start=%d reset=%d key=%d", counts.frame, counts.keysRead, counts.start, counts.reset, counts.key)
		rec("GB button mask changes (polled each frame; via keysRead too): %s", table.concat(mask_changes, " "))
		rec("key events seen: %d", #key_events)
		for _, e in ipairs(key_events) do rec("  %s", e) end
		rec("server received %d chunk(s): %s", #server_received, table.concat(server_received, "|"))
		if client then pcall(function() client:close() end) end
		flush("results.txt")
		local done = io.open(out_dir .. "/done", "w")
		if done then done:close() end
	end
end)
