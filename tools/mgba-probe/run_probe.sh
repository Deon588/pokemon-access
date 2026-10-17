#!/bin/bash
# Run the mGBA API probe end to end on macOS.
# Usage: run_probe.sh OUT_DIR [path/to/mGBA.app] [menu|cli]
#   menu (default): load probe.lua through the Scripting window (works on 0.10.x)
#   cli:            pass --script probe.lua on the command line (0.11 development builds)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?usage: run_probe.sh OUT_DIR [mGBA.app] [menu|cli]}"
APP="${2:-/Applications/mGBA.app}"
MODE="${3:-menu}"
MGBA="$APP/Contents/MacOS/mGBA"
mkdir -p "$OUT"
rm -f "$OUT"/results.txt "$OUT"/done "$OUT"/os_execute_ok "$OUT"/client_received.txt
python3 -I "$HERE/make_test_rom.py" "$OUT/probe.gb"
cat > "$HERE/probe_config.lua" <<LUA
return { out_dir = "$OUT", client_port = 48879, server_port = 48880 }
LUA
pgrep -x mGBA >/dev/null && { echo "another mGBA is running; quit it first"; exit 1; }
# TCP listener the Lua client connects to.
nc -l 127.0.0.1 48879 > "$OUT/client_received.txt" &
NC_PID=$!
# XDG_CONFIG_HOME isolates this run's mGBA settings (this build keeps them in ~/.config/mgba).
if [ "$MODE" = "cli" ]; then
	XDG_CONFIG_HOME="$OUT/xdg" POKEMON_ACCESS_PROBE_OUT="$OUT" nohup "$MGBA" --script "$HERE/probe.lua" "$OUT/probe.gb" > "$OUT/mgba.log" 2>&1 &
else
	XDG_CONFIG_HOME="$OUT/xdg" POKEMON_ACCESS_PROBE_OUT="$OUT" nohup "$MGBA" "$OUT/probe.gb" > "$OUT/mgba.log" 2>&1 &
fi
MGBA_PID=$!
echo "mGBA pid $MGBA_PID ($MGBA, mode $MODE)"
sleep 4
if [ "$MODE" = "menu" ]; then
	osascript "$HERE/load_script.applescript" "dofile(\"$HERE/probe.lua\")" 2> "$OUT/applescript.log" || { echo "script load failed"; cat "$OUT/applescript.log"; }
fi
sleep 1
# Keystrokes to the emulator window: hotkey letters, a shifted letter, then held GB buttons (x = A, right arrow).
osascript <<'APPLESCRIPT' 2>> "$OUT/applescript.log"
tell application "System Events"
	tell process "mGBA"
		set frontmost to true
		set mainWindows to (every window whose name does not contain "Scripting")
		if (count of mainWindows) > 0 then perform action "AXRaise" of item 1 of mainWindows
	end tell
	delay 0.6
	keystroke "t"
	delay 0.2
	keystroke "h" using shift down
	delay 0.2
	keystroke "j"
	delay 0.2
	key down "x"
	delay 0.4
	key up "x"
	delay 0.3
	key down (key code 124)
	delay 0.4
	key up (key code 124)
end tell
APPLESCRIPT
# Talk to the Lua-side TCP server early, before the 600-frame report.
printf 'ping from terminal\n' | nc -w 2 127.0.0.1 48880
# Close the Scripting window if open; the 600-frame report proves whether scripts keep running without it.
osascript <<'APPLESCRIPT' 2>> "$OUT/applescript.log"
tell application "System Events"
	tell process "mGBA"
		if exists window "Scripting" then
			perform action "AXRaise" of window "Scripting"
			delay 0.4
			click (first button of window "Scripting" whose subrole is "AXCloseButton")
		end if
		delay 0.5
		log "windows after closing Scripting: " & (name of every window)
	end tell
end tell
APPLESCRIPT
for _ in $(seq 1 30); do [ -f "$OUT/done" ] && break; sleep 1; done
echo "--- applescript log"; cat "$OUT/applescript.log"
echo "--- results.txt"; cat "$OUT/results.txt" 2>/dev/null || echo "NO RESULTS FILE"
echo "--- os_execute_ok exists?"; ls "$OUT/os_execute_ok" 2>/dev/null || echo "no"
echo "--- client_received.txt"; cat "$OUT/client_received.txt" 2>/dev/null
echo "--- XDG config honoured?"; ls "$OUT/xdg/mgba" 2>/dev/null || echo "no $OUT/xdg/mgba"
echo "--- mgba.log (tail)"; tail -3 "$OUT/mgba.log"
kill $NC_PID 2>/dev/null
osascript -e 'tell application "mGBA" to quit' 2>/dev/null || kill $MGBA_PID 2>/dev/null
sleep 2
pgrep -x mGBA >/dev/null && kill $MGBA_PID 2>/dev/null
exit 0
