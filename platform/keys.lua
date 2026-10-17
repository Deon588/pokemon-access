-- Tracks which hotkey names are held, in the spelling upstream's `commands`
-- table uses: uppercase letters and digits, lowercase "shift". Fed either by
-- chords from the helper app ("shift+H") or by raw mGBA 0.11 key events.
--
-- Upstream reads the keys once per frame. A press and release that both
-- arrive between two reads would otherwise be invisible, so names pressed
-- since the last held() call are reported once even if already released.
local Keys = {}
Keys.__index = Keys

-- Values recorded from mGBA 0.11's key events in the Phase 1 probe.
local SHIFT_KEY = 8388658
local SHIFT_MODIFIERS = 3 -- left shift (1) or right shift (2)
local SHIFTED_DIGITS = {
  [41] = "0", [33] = "1", [64] = "2", [35] = "3", [36] = "4",
  [37] = "5", [94] = "6", [38] = "7", [42] = "8", [40] = "9",
}
local STATE_UP, STATE_DOWN = 0, 1

function Keys.new()
  return setmetatable({ down = {}, recent = {} }, Keys)
end

local function chord_names(chord)
  local names = {}
  for name in chord:gmatch("[^+]+") do
    names[#names + 1] = name
  end
  return names
end

function Keys:press(chord)
  for _, name in ipairs(chord_names(chord)) do
    self.down[name] = true
    self.recent[name] = true
  end
end

function Keys:release(chord)
  for _, name in ipairs(chord_names(chord)) do
    self.down[name] = nil
  end
end

local function raw_name(key)
  if key == SHIFT_KEY then
    return "shift"
  elseif key >= 65 and key <= 90 then
    return string.char(key)
  elseif key >= 97 and key <= 122 then
    return string.char(key - 32)
  elseif key >= 48 and key <= 57 then
    return string.char(key)
  end
  return SHIFTED_DIGITS[key]
end

-- key, state, modifiers: the fields of an mGBA 0.11 "key" callback event.
function Keys:raw(key, state, modifiers)
  local name = raw_name(key)
  if name == nil then
    return
  end
  if state == STATE_DOWN then
    self.down[name] = true
    self.recent[name] = true
    if modifiers ~= nil and modifiers & SHIFT_MODIFIERS ~= 0 then
      self.down.shift = true
      self.recent.shift = true
    end
  elseif state == STATE_UP then
    self.down[name] = nil
  end
end

-- Names held now plus names pressed since the previous call.
function Keys:held()
  local snapshot = {}
  for name in pairs(self.down) do
    snapshot[name] = true
  end
  for name in pairs(self.recent) do
    snapshot[name] = true
  end
  self.recent = {}
  return snapshot
end

function Keys:clear()
  self.down = {}
  self.recent = {}
end

return Keys
