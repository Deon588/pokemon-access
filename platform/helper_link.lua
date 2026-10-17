-- TCP client side of the line protocol, on top of mGBA's `socket` table:
-- socket.connect(host, port), sock:send(data), sock:receive(max) (returns nil
-- plus socket.ERRORS.AGAIN when nothing is pending), sock:add("received" |
-- "error", fn), sock:close(). Incoming lines are dispatched by their first field.
local protocol = require("platform.protocol")

local Link = {}
Link.__index = Link

local RECEIVE_CHUNK = 4096

function Link.new(socket_lib, host, port)
  return setmetatable({
    socket_lib = socket_lib,
    host = host,
    port = port,
    sock = nil,
    connected = false,
    handlers = {},
    on_unknown = nil,
    last_error = nil,
    buffer = protocol.LineBuffer.new(),
  }, Link)
end

function Link:connect()
  local sock, err = self.socket_lib.connect(self.host, self.port)
  if sock == nil then
    self.connected = false
    self.last_error = err
    return false, err
  end
  self.sock = sock
  self.connected = true
  self.buffer = protocol.LineBuffer.new()
  sock:add("received", function() self:poll() end)
  sock:add("error", function(reason) self:disconnect(reason) end)
  return true
end

function Link:disconnect(reason)
  self.connected = false
  self.last_error = reason
end

-- fields: array for protocol.encode. Returns false when there is no connection.
function Link:send(fields)
  if not self.connected or self.sock == nil then
    return false
  end
  local sent, err = self.sock:send(protocol.encode(fields))
  if sent == nil then
    self:disconnect(err)
    return false
  end
  return true
end

function Link:on(message_type, fn)
  self.handlers[message_type] = fn
end

function Link:dispatch(line)
  local fields = protocol.decode(line)
  local handler = self.handlers[fields[1]]
  if handler ~= nil then
    handler(fields)
  elseif self.on_unknown ~= nil then
    self.on_unknown(fields)
  end
end

-- Reads everything pending and dispatches complete lines.
function Link:poll()
  if not self.connected or self.sock == nil then
    return
  end
  while true do
    local data, err = self.sock:receive(RECEIVE_CHUNK)
    if data == nil then
      if err ~= self.socket_lib.ERRORS.AGAIN then
        self:disconnect(err)
      end
      return
    end
    if data == "" then
      -- an empty read is the peer closing the connection
      self:disconnect("closed by the helper")
      return
    end
    for _, line in ipairs(self.buffer:feed(data)) do
      self:dispatch(line)
    end
  end
end

function Link:close()
  if self.sock ~= nil then
    self.sock:close()
  end
  self.sock = nil
  self.connected = false
end

return Link
