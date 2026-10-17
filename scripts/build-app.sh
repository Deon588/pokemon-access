#!/bin/zsh
# Builds Pokemon Access.app from the Swift helper and the Lua scripts.
#
#   scripts/build-app.sh            builds build/Pokemon Access.app
#   scripts/build-app.sh --install  also replaces ~/Applications/Pokemon Access.app
#
# The bundle is signed ad hoc with a designated requirement that names only
# the bundle identifier, so the Accessibility grant survives rebuilds.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/Pokemon Access.app"
IDENTIFIER="com.abstractsingleton.pokemon-access"
VERSION=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo "0.0-dev")
BUILD=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c release --package-path "$ROOT/helper"
BINARY="$ROOT/helper/.build/release/PokemonAccess"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/lua"
cp "$BINARY" "$APP/Contents/MacOS/PokemonAccess"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" "$ROOT/helper/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The Lua payload: the entry point, the unchanged upstream scripts, the port's
# compat and platform layers, the game data, messages and sound cues.
for item in pokemon-access.lua pokemon.lua gb.lua gba.lua a-star.lua serpent.lua message.lua compat platform game message sounds; do
  rsync -a --delete --exclude .DS_Store "$ROOT/$item" "$APP/Contents/Resources/lua/"
done

codesign --force --sign - --identifier "$IDENTIFIER" \
  --requirements "=designated => identifier \"$IDENTIFIER\"" "$APP"
echo "built $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
  TARGET="$HOME/Applications/Pokemon Access.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$TARGET"
  ditto "$APP" "$TARGET"
  echo "installed $TARGET"
fi
