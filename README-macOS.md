# Pokémon Access on macOS

Pokémon Access reads a Pokémon game aloud: on-screen text, the map name, your
position, the objects around you, a path to any of them, and battle HP. This
port runs the unchanged upstream scripts inside the mGBA emulator on Apple
Silicon Macs and speaks through VoiceOver. It is a proof of concept for one
Mac, built from source, for Pokémon Red and Blue in English.

The upstream project and its Windows instructions are in `readme.md`. How the
port works, and why, is in `PORTING.md`.

## Requirements

- An Apple Silicon Mac running macOS 14 or later.
- Xcode or the Xcode command line tools (`xcode-select --install`), for the
  Swift compiler.
- Homebrew, and mGBA from it: `brew install --cask mgba-app`.
- VoiceOver, with "Allow VoiceOver to be controlled with AppleScript" turned on
  in VoiceOver Utility, under General. Without VoiceOver the app uses the system
  voice instead.
- Your own, legally owned Pokémon Red or Blue ROM (a `.gb` file). Nothing here
  downloads a ROM.

## Install

```
git clone <this repository> pokemon-access
cd pokemon-access
scripts/build-app.sh --install
```

This builds `Pokemon Access.app` and puts it in `~/Applications`. It is signed
for this Mac only; see "Signing" below.

## First launch

1. Open Pokemon Access from `~/Applications` (Spotlight finds it too). A small
   window named Pokemon Access shows the current status; VoiceOver reads it.
2. The app creates `~/Library/Application Support/Pokemon Access/ROMs`. Either
   copy your ROM there before the first launch, or choose it in the open dialog
   the app shows when the folder is empty. The choice is remembered. You can
   also open a ROM file with the app from the Finder.
3. On mGBA 0.10.5 (the current Homebrew release) the app loads its script
   through mGBA's Scripting window, which needs the Accessibility permission.
   The app says so, opens System Settings at Privacy and Security, Accessibility,
   and waits. Turn on Pokemon Access there and come back; the app continues by
   itself. mGBA 0.11 will not need this step.
4. The first time it speaks through VoiceOver, macOS asks whether Pokemon Access
   may control VoiceOver. Allow it. If you deny, the app falls back to the
   system voice and says so.
5. mGBA starts with your ROM. When the script is ready it says "Ready". Switch
   to mGBA (Command Tab) and play.

Quitting Pokemon Access quits mGBA too, politely, so your in-game save is
written. Quitting mGBA quits Pokemon Access.

## Playing

Game Boy buttons in mGBA: arrows for the D-pad, X is A, Z is B, Return is
Start, Backspace is Select, A and S are L and R.

Pokémon Access keys, taken while mGBA is the frontmost window:

- t: read the text on screen
- m: read the current map name; shift m: rename the map
- y: read your position; shift y: read the camera position
- j, k, l: previous, current and next object; shift j and shift l: previous and
  next object filter; shift k: rename the current object
- p: find a path from you to the selected object and speak it; shift p: cycle
  which HMs the path may use (none, the ones your badges allow, all)
- h: enemy HP in battle; shift h: your Pokémon's HP in battle
- d, g, r, v: move the camera left, right, up, down, stopping at walls; with
  shift, through walls
- f: move the camera back to you; shift f: find a path to the camera position
- c: toggle whether the camera follows you
- e: read the surrounding tiles (debugging)
- shift 0: hack ROM setup (not supported in this version)

VoiceOver notes: turn Quick Nav off while playing (press the left and right
arrows together), or single letters go to VoiceOver instead of the game. Press
Control to stop speech at any time. Command Tab to Pokemon Access reads the
status window.

## Settings

Settings are stored with `defaults`. Quit the app before changing them.

```
defaults write com.abstractsingleton.pokemon-access speechEngine voiceover
```

- `speechEngine`: `auto` (default: VoiceOver when it runs, else the system
  voice), `voiceover`, `avspeech` or `say`.
- `voiceIdentifier` and `speechRate`: voice and rate for the `avspeech` engine
  (`say -v ?` lists voice names; `speechRate` is 0 to 1, 0.5 is the default).
- `soundGain`: multiplier for the sound cues, default 1.
- `mgbaVolume`: mGBA's game volume, 0 to 256, written to the private mGBA
  configuration on first launch (default 128).
- `romPath`: the remembered ROM. `defaults delete
  com.abstractsingleton.pokemon-access romPath` makes the app ask again.
- `luaRoot`: a checkout of this repository to run the scripts from instead of
  the copy inside the app (development).

mGBA's own settings for this app live in `~/Library/Application Support/Pokemon
Access/config/mgba/config.ini`, separate from any other mGBA configuration.
Saves (`.sav`) sit next to the ROM.

## Troubleshooting

- The log is `~/Library/Logs/Pokemon Access/pokemon-access.log`; the previous
  run is kept as `pokemon-access.previous.log`. It records every spoken line.
- "mGBA is not installed": run `brew install --cask mgba-app`.
- "Pokemon Access needs the Accessibility permission" again after rebuilding:
  macOS ties the grant to the signature. Remove Pokemon Access from the
  Accessibility list and add it again, or sign with a certificate (below).
- "The script did not start inside mGBA": read the end of the log. mGBA's
  Scripting window must be reachable; make sure the screen is not locked and
  no other mGBA was already running.
- No speech through VoiceOver: check VoiceOver Utility, General, "Allow
  VoiceOver to be controlled with AppleScript", and System Settings, Privacy
  and Security, Automation, Pokemon Access, VoiceOver.
- A ROM the game logic does not recognise is announced as "Game not
  supported." Red and Blue in English are recognised by their header checksums;
  other dumps and hacks need the hack ROM setup, which is not in this version.

## Signing

`scripts/build-app.sh` signs the bundle ad hoc with a requirement that names
only the bundle identifier, so the Accessibility grant survives rebuilds on
this Mac. The trade-off is that another ad hoc binary claiming the same
identifier would match that grant. With a code signing certificate in your
keychain you can pin the signature instead:

```
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh --install
```

## Development

- Lua tests: `tests/lua/run.sh` (Homebrew `lua@5.4`, the version mGBA embeds).
- Swift tests: `swift test --package-path helper`.
- End to end with a generated test ROM: `scripts/smoke-test.sh` (add the path
  to another mGBA.app to test the 0.11 `--script` mode).
- The Lua side alone, inside mGBA with a Python stand-in for the app:
  `tools/dev/run_in_mgba.sh ROM --send 'KEY\tDOWN\tT' --send 'KEY\tUP\tT'`.
- The app without mGBA: `helper/.build/debug/PokemonAccess --no-launch --port
  48891`, then talk to it with `nc` using the protocol in `PORTING.md` 6.2.

Layout: `pokemon-access.lua` is the entry point mGBA loads; `platform/` talks
to mGBA and the app; `compat/` recreates the VBA-ReRecording Lua API the
upstream scripts expect; `helper/` is the Swift application; upstream files are
unchanged except for the patch listed in `PORTING.md` 6.4.
