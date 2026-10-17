-- Drives upstream pokemon.lua as a coroutine, one resume per emulated frame.
-- Upstream's `while true do emu.frameadvance() main_loop() end` keeps working
-- because compat maps emu.frameadvance to coroutine.yield. An error in upstream
-- code is logged and spoken; the emulator keeps running and the program is
-- started again a few seconds later (see Runner.new for the limits), and an
-- emulator reset or a new ROM always starts it again.
local Runner = {}
Runner.__index = Runner

local ERROR_MESSAGE = "Pokemon Access script error. See the log."
local STOPPED_MESSAGE = "Pokemon Access stopped after repeated script errors. Reset the game to try again."

-- platform: the platform layer; api: the table compat.install returned;
-- chunk: a function that runs the upstream main program (for example a dofile).
--
-- After an error the program is started again restart_delay_frames later (the
-- game keeps running meanwhile), up to max_restarts times in a row; a program
-- that stays alive for recovery_frames earns its restarts back. An emulator
-- reset always starts it again.
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
    errored = false,
    stopped = false,
    restarts = 0,
    max_restarts = 3,
    restart_delay_frames = 180,
    recovery_frames = 3600,
    frames_since_error = 0,
    alive_frames = 0,
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
    self.errored = true
    self.frames_since_error = 0
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
  self.errored = false
  self.alive_frames = 0
  self:resume()
end

-- Schedules a restart some frames after an error, within the limit.
function Runner:consider_restart()
  if self.alive or not self.errored or self.stopped then
    return
  end
  self.frames_since_error = self.frames_since_error + 1
  if self.frames_since_error < self.restart_delay_frames then
    return
  end
  if self.restarts < self.max_restarts then
    self.restarts = self.restarts + 1
    self.platform.log(string.format("restarting the program after an error (%d of %d)", self.restarts, self.max_restarts))
    self.started = false
  else
    self.stopped = true
    self.platform.log("not restarting the program again; waiting for a reset")
    self.platform.speak(STOPPED_MESSAGE)
  end
end

function Runner:frame()
  if self.shut_down then
    return
  end
  self.platform.poll()
  if self.pending_reset then
    self.pending_reset = false
    self.restarts = 0
    self.stopped = false
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
  else
    self:consider_restart()
  end
  if not self.started then
    self:start()
  end
  self.api.poll_exec()
  self:resume()
  if self.alive then
    self.alive_frames = self.alive_frames + 1
    if self.alive_frames >= self.recovery_frames then
      self.restarts = 0
    end
  end
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
