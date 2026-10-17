#!/bin/zsh
# Runs pokemon-access.lua inside the installed mGBA 0.10.5 against the fake
# helper, for development without the Swift app. Needs an unlocked screen:
# the script is loaded through the Accessibility API.
#
# Usage: tools/dev/run_in_mgba.sh ROM [--duration SECONDS] [fake_helper.py args...]
# Example:
#   tools/dev/run_in_mgba.sh probe.gb --send 'KEY\tDOWN\tT' --send 'KEY\tUP\tT' --after 6
# Output goes to ${POKEMON_ACCESS_SCRATCH:-$TMPDIR/pokemon-access-dev}/run-<timestamp>/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ROM=${1:?usage: run_in_mgba.sh ROM [--duration SECONDS] [fake_helper args...]}
shift
DURATION=15
if [[ "${1:-}" == "--duration" ]]; then
  DURATION=$2
  shift 2
fi
MGBA=${MGBA:-/Applications/mGBA.app/Contents/MacOS/mGBA}
PORT=${POKEMON_ACCESS_PORT:-48890}
SCRATCH=${POKEMON_ACCESS_SCRATCH:-${TMPDIR:-/tmp}/pokemon-access-dev}
OUT="$SCRATCH/run-$(date +%Y%m%d-%H%M%S)"
LOG="$OUT/helper.log"
mkdir -p "$OUT/xdg" "$OUT/data"

if pgrep -x mGBA >/dev/null || pgrep -x mGBA-dev >/dev/null; then
  echo "mGBA is already running; quit it first" >&2
  exit 1
fi

python3 "$ROOT/tools/dev/fake_helper.py" --port "$PORT" --log "$LOG" "$@" > "$OUT/fake_helper.out" 2>&1 &
HELPER_PID=$!
sleep 0.5

# mGBA 0.11 takes --script on the command line; 0.10.5 needs the Scripting window.
SCRIPT_ARGS=()
if "$MGBA" --help 2>&1 | grep -q -- '--script'; then
  SCRIPT_ARGS=(--script "$ROOT/pokemon-access.lua")
  echo "using --script (this mGBA supports it)"
fi

# Working directory is where upstream writes names_*.lua and hacks.lua.
(cd "$OUT/data" && XDG_CONFIG_HOME="$OUT/xdg" POKEMON_ACCESS_PORT="$PORT" \
  nohup "$MGBA" "${SCRIPT_ARGS[@]}" "$ROM" > "$OUT/mgba.log" 2>&1 &)
sleep 3

cleanup() {
  osascript -e 'tell application "mGBA" to quit' 2>/dev/null || true
  sleep 1
  pgrep -x mGBA >/dev/null && pkill -x mGBA || true
  pgrep -x mGBA-dev >/dev/null && pkill -x mGBA-dev || true
  kill "$HELPER_PID" 2>/dev/null || true
}
trap cleanup EXIT

if [[ ${#SCRIPT_ARGS[@]} -eq 0 ]]; then
  if ! osascript "$ROOT/tools/mgba-probe/load_script.applescript" "dofile([==[$ROOT/pokemon-access.lua]==])" 2> "$OUT/applescript.log"; then
    echo "loading the script through the Scripting window failed (is the screen unlocked?):" >&2
    cat "$OUT/applescript.log" >&2
  fi
fi

for _ in {1..60}; do
  grep -q $'recv HELLO\t' "$LOG" 2>/dev/null && break
  sleep 0.5
done
if ! grep -q $'recv HELLO\t' "$LOG"; then
  echo "no HELLO from the script within 30 s" >&2
fi

sleep "$DURATION"
echo "--- helper log: $LOG"
cat "$LOG"
echo "--- mGBA output (last lines): $OUT/mgba.log"
tail -n 20 "$OUT/mgba.log"
