local check = require("check")
local protocol = require("platform.protocol")

check.eq(protocol.encode({"SPEAK", 1, "a\tb\nc\\d"}), "SPEAK\t1\ta\\tb\\nc\\\\d\n", "encode escapes tabs, newlines and backslashes")
check.eq(protocol.decode("KEY\tDOWN\tshift+H"), {"KEY", "DOWN", "shift+H"}, "decode splits on tabs")
check.eq(protocol.decode(protocol.encode({"X", "Pokémon", true, false, 3.0, 1.5})),
  {"X", "Pokémon", "1", "0", "3", "1.5"}, "round trip keeps UTF-8, booleans and numbers")
check.eq(protocol.decode("A\tb\\tc\\nd\\\\e\r"), {"A", "b\tc\nd\\e"}, "decode unescapes and drops a trailing CR")
check.eq(protocol.unescape("\\q"), "q", "unknown escapes keep the character")
check.eq(protocol.escape("plain"), "plain", "escape leaves plain text alone")

local buffer = protocol.LineBuffer.new()
check.eq(buffer:feed("HEL"), {}, "partial line is held back")
check.eq(buffer:feed("LO\t1\nKEY\tDOWN\tT\nPAR"), {"HELLO\t1", "KEY\tDOWN\tT"}, "complete lines come out in order")
check.eq(buffer:feed("T\r\n"), {"PART"}, "CRLF lines are stripped")
check.eq(buffer:feed(""), {}, "empty chunk yields nothing")
check.done()
