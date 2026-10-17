-- A stand-in for mGBA's `socket` table (client side only).
local fake = {}

function fake.new()
  local lib = { ERRORS = { AGAIN = "again" }, refuse = false, sent = {}, incoming = {}, sock = nil }

  function lib.connect(host, port)
    if lib.refuse then
      return nil, "connection refused"
    end
    local sock = { callbacks = {}, closed = false, host = host, port = port }
    function sock:send(data)
      local _, is_main = coroutine.running()
      if not is_main then
        lib.coroutine_sends = (lib.coroutine_sends or 0) + 1
      end
      lib.sent[#lib.sent + 1] = data
      return #data
    end
    function sock:receive(max)
      if #lib.incoming == 0 then
        return nil, lib.ERRORS.AGAIN
      end
      local data = table.concat(lib.incoming)
      lib.incoming = {}
      if #data > max then
        lib.incoming[1] = data:sub(max + 1)
        data = data:sub(1, max)
      end
      return data
    end
    function sock:add(name, fn)
      self.callbacks[name] = fn
    end
    function sock:close()
      self.closed = true
    end
    lib.sock = sock
    return sock
  end

  -- Queue data the "helper" sends; delivered by the next receive().
  function lib:push(data)
    self.incoming[#self.incoming + 1] = data
  end

  return lib
end

return fake
