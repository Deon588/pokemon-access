local check = require("check")
local fake_platform = require("fake_platform")
local compat = require("compat.vba_api")
local Runner = require("platform.runner")

local fake = fake_platform.new{}
local api = compat.install(fake)

local function count_speak(text)
  local n = 0
  for _, call in ipairs(fake.calls) do
    if call[1] == "speak" and call[2] == text then n = n + 1 end
  end
  return n
end

local function last_log()
  return fake.logs[#fake.logs] or ""
end

local runner = Runner.new(fake, api, function()
  local tolk = require("tolk") -- as upstream pokemon.lua does
  memory.registerexec(0x100, function() tolk.output("Ready") end)
  frames = 0
  while true do
    emu.frameadvance()
    frames = frames + 1
    if frames == 3 then
      error("boom")
    end
  end
end)

check.eq(runner.alive, false, "not alive before the first frame")
runner:frame()
runner:frame()
check.eq(frames, 2, "the first frame starts the program and runs one loop iteration")
check.eq(runner.alive, true, "alive while the program runs")
check.eq(type(api.reset_handler), "function", "the program registered its reset handler")

runner:frame()
check.eq(runner.alive, false, "an error stops the program")
check.eq(count_speak("Pokemon Access script error. See the log."), 1, "the error is spoken once")
check.truthy(last_log():find("boom", 1, true), "the error is logged")
check.truthy(last_log():find("script error:", 1, true), "with the script error prefix")

runner:frame()
runner:frame()
check.eq(count_speak("Pokemon Access script error. See the log."), 1, "later frames stay quiet")

runner:reset()
runner:frame()
check.eq(runner.alive, true, "a reset restarts a dead program")
check.eq(frames, 1, "the restarted program ran its first loop iteration")

runner:reset()
runner:frame()
check.eq(count_speak("Ready"), 1, "a reset while alive calls the registered reset handler")
check.eq(frames, 2, "and the program keeps running")

runner:shutdown()
runner:frame()
check.eq(frames, 2, "a shut down runner does nothing")

-- requests yielded by platform calls are serviced on the main thread
local REQUEST = {}
fake.is_request = function(value) return type(value) == "table" and value[REQUEST] == true end
fake.service = function(request) return table.pack(pcall(request.fn, table.unpack(request.args, 1, request.args.n))) end
local serviced_on_main = 0
local function read_on_main(addr)
  local _, is_main = coroutine.running()
  if is_main then serviced_on_main = serviced_on_main + 1 end
  return addr + 1
end
local answer
local requester = Runner.new(fake, api, function()
  local results = coroutine.yield({ [REQUEST] = true, fn = read_on_main, args = table.pack(41) })
  answer = results[2]
  while true do emu.frameadvance() end
end)
requester:frame()
check.eq(answer, 42, "the request's result is passed back to the program")
check.eq(serviced_on_main, 1, "and the request ran on the main thread")
check.truthy(requester.alive, "servicing a request keeps the program alive")

-- a program that returns is finished, not an error
local finished = Runner.new(fake, api, function() end)
local before = #fake.calls
finished:frame()
check.eq(finished.alive, false, "a program that returns is no longer alive")
check.eq(count_speak("Pokemon Access script error. See the log."), 1, "and that is not an error")
check.done()
