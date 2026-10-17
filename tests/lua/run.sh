#!/bin/zsh
# Runs every tests/lua/test_*.lua with Lua 5.4 (the version mGBA embeds).
# Override the interpreter with LUA=/path/to/lua5.4.
set -euo pipefail
cd "$(dirname "$0")/../.."
LUA=${LUA:-/opt/homebrew/opt/lua@5.4/bin/lua5.4}
export LUA_PATH="./?.lua;./tests/lua/?.lua;;"
for test in tests/lua/test_*.lua; do
  printf '%s: ' "$test"
  "$LUA" "$test"
done
