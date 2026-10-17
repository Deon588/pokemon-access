local check = require("check")
local Keys = require("platform.keys")

local tracker = Keys.new()
tracker:press("shift+H")
check.eq(tracker:held(), { H = true, shift = true }, "press marks every name of the chord")
tracker:release("shift+H")
check.eq(tracker:held(), {}, "release clears every name of the chord")

tracker:press("T")
local snapshot = tracker:held()
snapshot.Z = true
check.eq(tracker:held(), { T = true }, "held returns a copy")
tracker:release("T")

tracker:raw(84, 1, 0)
check.eq(tracker:held(), { T = true }, "raw letter down (mGBA 0.11 event)")
tracker:raw(84, 0, 0)
check.eq(tracker:held(), {}, "raw letter up")

tracker:raw(8388658, 1, 3)
tracker:raw(72, 1, 3)
check.eq(tracker:held(), { H = true, shift = true }, "raw shift key then letter")
tracker:raw(72, 2, 3)
check.eq(tracker:held(), { H = true, shift = true }, "held repeat events change nothing")
tracker:raw(72, 0, 3)
tracker:raw(8388658, 0, 0)
check.eq(tracker:held(), {}, "raw releases")

tracker:raw(41, 1, 3)
check.eq(tracker:held(), { ["0"] = true, shift = true }, "shifted digit character maps back to the digit")
tracker:clear()
check.eq(tracker:held(), {}, "clear empties the tracker")

tracker:raw(104, 1, 0)
check.eq(tracker:held(), { H = true }, "lowercase letter codes map to the uppercase name")
tracker:raw(999999, 1, 0)
check.eq(tracker:held(), { H = true }, "unknown keys are ignored")
check.done()
