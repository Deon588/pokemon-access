-- Collects everything upstream speaks during one emulated frame into a single
-- utterance. Upstream calls tolk.output() once per line (up to 18 lines for a
-- screen of text) and tolk.silence() before every hotkey command; VoiceOver's
-- `output` command offers no queue control, so one utterance per frame keeps
-- each command's text whole whether or not consecutive outputs interrupt.
local Speech = {}
Speech.__index = Speech

-- send(interrupt, text) is called at most once per flush.
function Speech.new(send)
  return setmetatable({ send = send, lines = {}, interrupt = false }, Speech)
end

function Speech:output(text)
  if text == nil then
    return
  end
  text = tostring(text)
  if text == "" then
    return
  end
  self.lines[#self.lines + 1] = text
end

function Speech:silence()
  self.lines = {}
  self.interrupt = true
end

function Speech:flush()
  if #self.lines > 0 then
    self.send(self.interrupt, table.concat(self.lines, "\n"))
  elseif self.interrupt then
    self.send(true, "")
  end
  self.lines = {}
  self.interrupt = false
end

return Speech
