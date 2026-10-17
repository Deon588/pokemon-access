local check = require("check")
local fake_socket = require("fake_socket")
local Link = require("platform.helper_link")

local lib = fake_socket.new()
local link = Link.new(lib, "127.0.0.1", 48890)
check.eq(link.connected, false, "not connected before connect()")
check.truthy(link:connect(), "connect succeeds")
check.eq(link.connected, true, "connected flag")
check.eq(lib.sock.port, 48890, "connects to the given port")

check.truthy(link:send({ "HELLO", 1, "helper", "Lua 5.4" }), "send returns true when connected")
check.eq(lib.sent, { "HELLO\t1\thelper\tLua 5.4\n" }, "send encodes one protocol line")

local received = {}
link:on("WELCOME", function(fields) received[#received + 1] = fields end)
link:on("KEY", function(fields) received[#received + 1] = fields end)
local unknown = {}
link.on_unknown = function(fields) unknown[#unknown + 1] = fields end

lib:push("WELCOME\t0.1\thelper\nKEY\tDOWN\tT\nKE")
link:poll()
check.eq(received, { { "WELCOME", "0.1", "helper" }, { "KEY", "DOWN", "T" } }, "complete lines are dispatched by type")
lib:push("Y\tUP\tT\nBOGUS\tx\n")
link:poll()
check.eq(received[3], { "KEY", "UP", "T" }, "a line split across chunks is reassembled")
check.eq(unknown, { { "BOGUS", "x" } }, "unknown types go to on_unknown")

check.truthy(lib.sock.callbacks.received, "a received callback is registered with the socket")
check.truthy(lib.sock.callbacks.error, "an error callback is registered with the socket")
lib.sock.callbacks.error("reset by peer")
check.eq(link.connected, false, "a socket error disconnects the link")
check.eq(link:send({ "SILENCE" }), false, "send fails when disconnected")

link:close()
check.truthy(lib.sock.closed, "close closes the socket")

local closing = fake_socket.new()
local closed_link = Link.new(closing, "127.0.0.1", 1)
closed_link:connect()
closing.eof = true
closed_link:poll()
check.eq(closed_link.connected, false, "an empty read means the helper closed the connection")

local refusing = fake_socket.new()
refusing.refuse = true
local refused = Link.new(refusing, "127.0.0.1", 1)
local ok, err = refused:connect()
check.eq(ok, false, "connect reports failure")
check.eq(err, "connection refused", "with the socket error")
check.eq(refused.connected, false, "and stays disconnected")
check.eq(refused:send({ "SPEAK", 0, "x" }), false, "send fails without a connection")
check.done()
