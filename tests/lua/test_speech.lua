local check = require("check")
local Speech = require("platform.speech")

local sent = {}
local speech = Speech.new(function(interrupt, text)
  sent[#sent + 1] = { interrupt, text }
end)

speech:output("a")
speech:output("b")
speech:output("c")
speech:flush()
check.eq(sent, { { false, "a\nb\nc" } }, "outputs within a frame become one utterance")

sent = {}
speech:flush()
check.eq(sent, {}, "flush with nothing pending sends nothing")

speech:output("dropped")
speech:silence()
speech:output("x")
speech:flush()
check.eq(sent, { { true, "x" } }, "silence drops earlier lines and marks the interrupt")

sent = {}
speech:silence()
speech:flush()
check.eq(sent, { { true, "" } }, "a bare silence is sent as an interrupt with no text")

sent = {}
speech:output("")
speech:output(nil)
speech:flush()
check.eq(sent, {}, "empty and nil outputs are ignored")

speech:output(42)
speech:flush()
check.eq(sent, { { false, "42" } }, "non-string values are converted with tostring")

sent = {}
speech:flush()
check.eq(sent, {}, "flush resets the interrupt flag and pending lines")
check.done()
