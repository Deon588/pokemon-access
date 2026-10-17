-- Pokemon Access for mGBA: entry point.
--
-- Load this file in mGBA (Tools > Scripting, or --script on 0.11) with a
-- Pokemon ROM running. It runs the unchanged upstream pokemon.lua on top of
-- the platform layer (platform/mgba.lua) and the VBA API shim
-- (compat/vba_api.lua). Speech, sounds and prompts go to the helper app
-- listening on the port in POKEMON_ACCESS_PORT; see PORTING.md.
local source = debug.getinfo(1, "S").source
local script_dir = source:sub(2):match("(.*[/\\])") or "./"
package.path = script_dir .. "?.lua;" .. package.path

local platform = require("platform.mgba")
local compat = require("compat.vba_api")
local Runner = require("platform.runner")

-- Loading this file twice replaces the previous instance.
if _G.pokemon_access_runner ~= nil then
  _G.pokemon_access_runner:shutdown()
  platform.shutdown()
end

platform.setup{}
local api = compat.install(platform)
local runner = Runner.new(platform, api, function()
  dofile(script_dir .. "pokemon.lua")
end)
_G.pokemon_access_runner = runner

platform.on_frame(function() runner:frame() end)
platform.on_reset(function() runner:reset() end)
platform.send_hello(_VERSION)
platform.log("pokemon-access loaded, key source = " .. platform.key_source)
