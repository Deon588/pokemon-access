#!/bin/zsh
# End-to-end check with the generated test ROM: builds the app, launches mGBA
# through it, and expects the script to connect and speak (the test ROM is not
# a Pokemon game, so upstream reports it as not supported, which is the signal
# that memory reads, speech and the whole launch chain work).
#
#   scripts/smoke-test.sh                     uses /Applications/mGBA.app
#   scripts/smoke-test.sh /path/to/mGBA.app   uses another build (0.11 takes --script)
#
# Loading the script into mGBA 0.10.5 goes through the Accessibility API and
# needs an unlocked screen. Run from a terminal: the terminal's Accessibility
# grant then covers the app.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MGBA_APP=${1:-}
SCRATCH=${POKEMON_ACCESS_SCRATCH:-${TMPDIR:-/tmp}/pokemon-access-dev}
mkdir -p "$SCRATCH"
ROM="$SCRATCH/probe.gb"
LOG="$SCRATCH/smoke-$(date +%Y%m%d-%H%M%S).log"

if pgrep -x mGBA >/dev/null || pgrep -x mGBA-dev >/dev/null; then
  echo "mGBA is already running; quit it first" >&2
  exit 1
fi
[[ -f "$ROM" ]] || python3 "$ROOT/tools/mgba-probe/make_test_rom.py" "$ROM"

"$ROOT/scripts/build-app.sh" > "$SCRATCH/smoke-build.out" 2>&1 || { cat "$SCRATCH/smoke-build.out"; exit 1; }

ARGS=(--rom "$ROM" --quit-after 30 --lua-root "$ROOT")
[[ -n "$MGBA_APP" ]] && ARGS+=(--mgba "$MGBA_APP")
POKEMON_ACCESS_LOG="$LOG" "$ROOT/build/Pokemon Access.app/Contents/MacOS/PokemonAccess" "${ARGS[@]}" > "$SCRATCH/smoke.out" 2>/dev/null || true
sleep 2
pgrep -x mGBA >/dev/null && pkill -x mGBA || true
pgrep -x mGBA-dev >/dev/null && pkill -x mGBA-dev || true

failed=0
for pattern in "mGBA started" "hello from script" "speak via" "not supported" "status: Connected to the script"; do
  if ! grep -q -- "$pattern" "$LOG"; then
    echo "missing in log: $pattern"
    failed=1
  fi
done
if [[ $failed -eq 0 ]]; then
  echo "smoke test passed ($LOG)"
else
  echo "smoke test FAILED ($LOG):"
  cat "$LOG"
  exit 1
fi
