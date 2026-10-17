-- Run one line of Lua inside a running mGBA 0.10.x without touching a file dialog:
-- set the Scripting window's prompt text through accessibility and click Run.
-- Typing into the prompt with "keystroke" does not work (Qt ignores the synthetic
-- focus), but setting the AXValue of the text field does. The widget tree is not
-- populated immediately after the window opens, so the lookup retries.
-- Usage: osascript load_script.applescript 'dofile("/absolute/path/script.lua")'
on run argv
	set luaCode to item 1 of argv
	tell application "System Events"
		if not (exists process "mGBA") then error "mGBA is not running"
		tell process "mGBA"
			set frontmost to true
			delay 0.8
			if not (exists window "Scripting") then
				click menu item "Scripting..." of menu "Tools" of menu bar 1
			end if
			set prompt to missing value
			set runButton to missing value
			repeat 15 times
				delay 1
				try
					perform action "AXRaise" of window "Scripting"
					-- Assign first: iterating "entire contents" inline as a reference yields no elements.
					set els to entire contents of window "Scripting"
					repeat with el in els
						try
							if (prompt is missing value) and (class of el is text field) then set prompt to el
							if (runButton is missing value) and (class of el is button) and (name of el is "Run") then set runButton to el
						end try
					end repeat
				end try
				if (prompt is not missing value) and (runButton is not missing value) then exit repeat
			end repeat
			if prompt is missing value or runButton is missing value then error "Scripting prompt or Run button not found"
			set value of prompt to luaCode
			delay 0.4
			click runButton
			delay 1
		end tell
	end tell
end run
