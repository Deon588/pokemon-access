-- Drives upstream pokemon.lua as a coroutine, one resume per emulated frame.
-- Upstream's `while true do emu.frameadvance() main_loop() end` keeps working
-- because compat maps emu.frameadvance to coroutine.yield. Errors in upstream
-- code are logged and spoken once; the emulator keeps running and a reset
-- (or a new ROM) starts the program again.
local Runner = {}
Runner.__index = Runner

local ERROR_MESSAGE = "Pokemon Access script error. See the log."

-- platform: the platform layer; api: the table compat.install returned;
-- chunk: a function that runs the upstream main program (for example a dofile).
function Runner.new(platform, api, chunk)
  return setmetatable({
    platform = platform,
    api = api,
    chunk = chunk,
    co = nil,
    alive = false,
    started = false,
    pending_reset = false,
    shut_down = false,
  }, Runner)
end

-- Resumes the program until it yields for the next frame. A yield that is a
-- platform request (an emulator call that must run on the main thread, see
-- platform/mgba.lua) is serviced here and the program continues at once.
function Runner:resume()
  if not self.alive then
    return
  end
  local ok, err = coroutine.resume(self.co)
  local platform = self.platform
  while ok and platform.is_request ~= nil and platform.is_request(err) do
    ok, err = coroutine.resume(self.co, platform.service(err))
  end
  if not ok then
    self.alive = false
    self.platform.log("script error: " .. tostring(err) .. "\n" .. debug.traceback(self.co))
    self.platform.speak(ERROR_MESSAGE)
  elseif coroutine.status(self.co) == "dead" then
    self.alive = false
    self.platform.log("script finished")
  end
end

-- Runs the program's top level (up to its first frameadvance).
function Runner:start()
  self.co = coroutine.create(self.chunk)
  self.alive = true
  self.started = true
  self:resume()
end

function Runner:frame()
  if self.shut_down then
    return
  end
  self.platform.poll()
  if self.pending_reset then
    self.pending_reset = false
    if self.alive then
      if self.api.reset_handler ~= nil then
        local ok, err = pcall(self.api.reset_handler)
        if not ok then
          self.platform.log("reset handler failed: " .. tostring(err))
        end
      end
    else
      self.started = false
    end
  end
  if not self.started then
    self:start()
  end
  self.api.poll_exec()
  self:resume()
  self.platform.end_frame()
end

-- Called from the emulator's reset and start callbacks.
function Runner:reset()
  self.pending_reset = true
end

function Runner:shutdown()
  self.shut_down = true
end

return Runner
