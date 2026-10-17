-- The platform layer on mGBA (0.10.5 and 0.11): memory reads, frame and
-- reset callbacks, hotkeys, and speech, sounds, prompts and logging routed to
-- the helper app over the line protocol. Falls back to `say` and `afplay`
-- when no helper is connected.
--
-- setup() captures mGBA's globals (emu, callbacks, console, socket, input)
-- because compat.install() afterwards replaces `emu` and `input` with the
-- tables upstream expects.
--
-- mGBA 0.10.5 binds its API to the main Lua thread: emu, console and socket
-- methods called from a coroutine fail with "Function called from invalid
-- context" (0.11 accepts them). Upstream runs inside the runner's coroutine,
-- so every such call goes through M.call, which yields a request that the
-- runner services on the main thread (platform/runner.lua).
local Link = require("platform.helper_link")
local Speech = require("platform.speech")
local Keys = require("platform.keys")

local M = {}
M.name = "mgba"
M.PROTOCOL_VERSION = 1

local HOST = "127.0.0.1"
local RECONNECT_FRAMES = 300

local function shell_quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function run_in_background(command)
  os.execute("(" .. command .. ") >/dev/null 2>&1 &")
end

function M.connected()
  return M.link ~= nil and M.link.connected
end

-- Main-thread trampoline ----------------------------------------------------

local REQUEST = {}

-- Calls fn(...) on the main Lua thread: directly when already there, otherwise
-- by yielding a request for the runner to service.
function M.call(fn, ...)
  local _, on_main = coroutine.running()
  if on_main then
    return fn(...)
  end
  local results = coroutine.yield({ [REQUEST] = true, fn = fn, args = table.pack(...) })
  if not results[1] then
    error(results[2], 0)
  end
  return table.unpack(results, 2, results.n)
end

function M.is_request(value)
  return type(value) == "table" and value[REQUEST] == true
end

-- Runs a yielded request; the packed results go back into the coroutine.
function M.service(request)
  return table.pack(pcall(request.fn, table.unpack(request.args, 1, request.args.n)))
end

local function raw_send(fields)
  if M.link ~= nil and M.link.connected then
    return M.link:send(fields)
  end
  return false
end

local function raw_log(text)
  if M.runtime ~= nil and M.runtime.console ~= nil then
    M.runtime.console:log(text)
  end
  raw_send({ "LOG", "info", text })
end

function M.log(text)
  M.call(raw_log, tostring(text))
end

-- Memory ----------------------------------------------------------------

local function raw_read8(addr) return M.runtime.emu:read8(addr) end
local function raw_read16(addr) return M.runtime.emu:read16(addr) end
local function raw_read32(addr) return M.runtime.emu:read32(addr) end
local function raw_read_range(addr, count) return M.runtime.emu:readRange(addr, count) end
-- Linear ROM offsets, independent of the mapped bank (verified in Phase 1).
local function raw_rom_read8(offset) return M.runtime.emu.memory.cart0:read8(offset) end
local function raw_rom_read16(offset) return M.runtime.emu.memory.cart0:read16(offset) end
local function raw_platform_id() return M.runtime.emu:platform() end

function M.read8(addr) return M.call(raw_read8, addr) end
function M.read16(addr) return M.call(raw_read16, addr) end
function M.read32(addr) return M.call(raw_read32, addr) end

function M.read_range(addr, count)
  local bytes = M.call(raw_read_range, addr, count)
  return { bytes:byte(1, -1) }
end

function M.rom_read8(offset) return M.call(raw_rom_read8, offset) end
function M.rom_read16(offset) return M.call(raw_rom_read16, offset) end
function M.platform_id() return M.call(raw_platform_id) end

-- 0.11 only; returns false on 0.10.5 so the caller can poll instead.
local function raw_set_breakpoint(addr, fn)
  local emu = M.runtime.emu
  if emu.setBreakpoint == nil then
    return false
  end
  local ok = pcall(function() emu:setBreakpoint(fn, addr) end)
  return ok
end

function M.set_breakpoint(addr, fn)
  return M.call(raw_set_breakpoint, addr, fn)
end

-- Callbacks ---------------------------------------------------------------

local function add_callback(name, fn)
  local id = M.runtime.callbacks:add(name, fn)
  M.callback_ids[#M.callback_ids + 1] = id
  return id
end

function M.on_frame(fn)
  add_callback("frame", fn)
end

function M.on_reset(fn)
  add_callback("reset", fn)
  add_callback("start", fn)
end

-- Keys ----------------------------------------------------------------------

function M.held_keys()
  local held = M.keys:held()
  if M.debug_keys and next(held) ~= nil then
    local names = {}
    for name in pairs(held) do names[#names + 1] = name end
    table.sort(names)
    M.log("held keys: " .. table.concat(names, "+"))
  end
  return held
end

-- Speech --------------------------------------------------------------------

local function send_speech(interrupt, text)
  if M.connected() then
    if text == "" then
      M.call(raw_send, { "SILENCE" })
    else
      M.call(raw_send, { "SPEAK", interrupt and 1 or 0, text })
    end
    return
  end
  if text == "" then
    run_in_background("killall say")
  else
    run_in_background("killall say; /usr/bin/say -- " .. shell_quote(text))
  end
end

function M.speak(text) M.speech:output(text) end
function M.silence() M.speech:silence() end

-- Sounds ------------------------------------------------------------------

function M.play_sound(path, loop, pan, vol)
  M.next_sound_id = M.next_sound_id + 1
  local id = M.next_sound_id
  if M.connected() then
    M.call(raw_send, { "SOUND", id, path, loop and 1 or 0, pan, vol })
  else
    run_in_background(string.format("afplay -v %.2f %s", (tonumber(vol) or 100) / 100, shell_quote(path)))
  end
  return id
end

function M.stop_sound(id)
  if M.connected() then
    M.call(raw_send, { "SOUND_STOP", id })
  end
end

function M.set_pitch(id, value)
  if M.connected() then
    M.call(raw_send, { "SOUND_PITCH", id, value })
  end
end

-- Prompts -----------------------------------------------------------------

local function next_prompt_id()
  M.next_prompt_id = M.next_prompt_id + 1
  return M.next_prompt_id
end

local function cancel_locally(id, what)
  M.log(what .. " prompt cancelled: no helper connected")
  M.replies[id] = { ok = false, values = {} }
end

function M.prompt_text(title, caption, default)
  local id = next_prompt_id()
  if M.connected() then
    M.call(raw_send, { "PROMPT_TEXT", id, title, caption, default })
  else
    cancel_locally(id, "text")
  end
  return id
end

function M.prompt_choice(title, caption, items, multi, default)
  local id = next_prompt_id()
  if M.connected() then
    local defaults
    if type(default) == "table" then
      local parts = {}
      for i, index in ipairs(default) do parts[i] = tostring(index) end
      defaults = table.concat(parts, ",")
    else
      defaults = tostring(default or 1)
    end
    local fields = { "PROMPT_CHOICE", id, title, caption, multi and 1 or 0, defaults }
    for _, item in ipairs(items) do
      fields[#fields + 1] = item
    end
    M.call(raw_send, fields)
  else
    cancel_locally(id, "choice")
  end
  return id
end

function M.take_reply(id)
  local reply = M.replies[id]
  M.replies[id] = nil
  return reply
end

-- Helper link -------------------------------------------------------------

local function on_key(fields)
  local chord = fields[3] or ""
  if M.debug_keys then
    M.log("key message: " .. tostring(fields[2]) .. " " .. chord)
  end
  if fields[2] == "DOWN" then
    M.keys:press(chord)
  elseif fields[2] == "UP" then
    M.keys:release(chord)
  end
end

local function on_reply(fields)
  local id = tonumber(fields[2])
  if id == nil then
    return
  end
  local values = {}
  for i = 4, #fields do
    values[#values + 1] = fields[i]
  end
  M.replies[id] = { ok = fields[3] == "OK", values = values }
end

-- HELLO: protocol version, key source, runtime info, and the launch token the
-- helper handed us through POKEMON_ACCESS_TOKEN (empty when started by hand).
function M.send_hello(info)
  M.hello_info = info
  if M.connected() then
    M.link:send({ "HELLO", M.PROTOCOL_VERSION, M.key_source, info, M.token or "" })
  end
end

function M.connect()
  M.frames_since_attempt = 0
  if M.port == nil or M.runtime.socket == nil then
    return false
  end
  local link = Link.new(M.runtime.socket, HOST, M.port)
  link:on("KEY", on_key)
  link:on("REPLY", on_reply)
  link:on("WELCOME", function(fields)
    M.log("helper " .. tostring(fields[2]) .. " connected, key source " .. M.key_source)
  end)
  link.on_unknown = function(fields)
    M.log("unknown message from helper: " .. tostring(fields[1]))
  end
  local ok, err = link:connect()
  if not ok then
    M.link = nil
    if not M.connect_failure_logged then
      M.log("helper connection to port " .. tostring(M.port) .. " failed: " .. tostring(err))
      M.connect_failure_logged = true
    end
    return false
  end
  M.link = link
  M.connect_failure_logged = false
  if M.hello_info ~= nil then
    M.send_hello(M.hello_info)
  end
  return true
end

-- Called once per frame by the runner before upstream code runs.
function M.poll()
  if M.connected() then
    M.link:poll()
    return
  end
  if M.port == nil then
    return
  end
  M.frames_since_attempt = M.frames_since_attempt + 1
  if M.frames_since_attempt >= RECONNECT_FRAMES then
    M.connect()
  end
end

-- Called once per frame by the runner after upstream code ran.
function M.end_frame()
  M.speech:flush()
end

-- Lifecycle -------------------------------------------------------------

-- opts.port (default POKEMON_ACCESS_PORT), opts.token (default POKEMON_ACCESS_TOKEN),
-- opts.key_source ("auto" | "helper" | "lua").
function M.setup(opts)
  opts = opts or {}
  -- mGBA runs in the user's locale. Upstream was written for the C locale:
  -- it formats numbers with a decimal point and sorts held key names with
  -- table.sort before comparing them with its command table in ASCII order
  -- ("Y" before "shift"; alphabetical collation would put "shift" first and
  -- shift+Y or shift+V would never match).
  os.setlocale("C", "numeric")
  os.setlocale("C", "collate")
  M.runtime = {
    emu = emu,
    callbacks = callbacks,
    console = console,
    socket = socket,
    input = rawget(_G, "input"),
  }
  M.has_key_events = M.runtime.input ~= nil
  local source = opts.key_source or "auto"
  if source == "auto" then
    source = M.has_key_events and "lua" or "helper"
  end
  M.key_source = source
  M.port = tonumber(opts.port or os.getenv("POKEMON_ACCESS_PORT"))
  M.token = opts.token or os.getenv("POKEMON_ACCESS_TOKEN")
  M.debug_keys = os.getenv("POKEMON_ACCESS_DEBUG_KEYS") ~= nil
  M.keys = Keys.new()
  M.replies = {}
  M.next_prompt_id = 0
  M.next_sound_id = 0
  M.frames_since_attempt = 0
  M.hello_info = nil
  M.connect_failure_logged = false
  M.link = nil
  M.callback_ids = {}
  M.speech = Speech.new(send_speech)
  if M.key_source == "lua" then
    add_callback("key", function(event)
      M.keys:raw(event.key, event.state, event.modifiers)
    end)
  end
  M.connect()
end

function M.shutdown()
  for _, id in ipairs(M.callback_ids) do
    pcall(function() M.runtime.callbacks:remove(id) end)
  end
  M.callback_ids = {}
  if M.link ~= nil then
    M.link:close()
    M.link = nil
  end
end

return M
