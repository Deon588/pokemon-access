-- Tracks which hotkey names are held, in the spelling upstream's `commands`
-- table uses: uppercase letters and digits, lowercase "shift". Fed either by
-- chords from the helper app ("shift+H") or by raw mGBA 0.11 key events.
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
  return setmetatable({ down = {} }, Keys)
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
    if modifiers ~= nil and modifiers & SHIFT_MODIFIERS ~= 0 then
      self.down.shift = true
    end
  elseif state == STATE_UP then
    self.down[name] = nil
  end
end

function Keys:held()
  local copy = {}
  for name in pairs(self.down) do
    copy[name] = true
  end
  return copy
end

function Keys:clear()
  self.down = {}
end

return Keys
