#!/bin/zsh
# Presses Game Boy buttons in the frontmost mGBA through System Events, holding
# each key long enough for the emulator to sample it (a plain keystroke is
# too short). Names: a b x z (A, B, A, B), start, select, up, down, left, right,
# plus any single character. Usage: gb_press.sh NAME [NAME ...]
set -e
for name in "$@"; do
  case "$name" in
    start) key=return ;;
    select) key='(ASCII character 8)' ;;
    up) key=126 ;; down) key=125 ;; left) key=123 ;; right) key=124 ;;
    a) key='"x"' ;; b) key='"z"' ;;
    *) key="\"$name\"" ;;
  esac
  osascript -e "tell application \"System Events\" to key down $key" -e 'delay 0.25' -e "tell application \"System Events\" to key up $key"
  sleep 0.15
done
