# Porting Pokémon Access to macOS (mGBA + VoiceOver)

Phase 1 report: what the upstream scripts touch, what mGBA's Lua runtime offers on
macOS, what was verified by running code, and the architecture proposed for Phase 2.

Scope of the first port: Pokémon Red and Blue, English, on Apple Silicon, with
VoiceOver. Everything described here was checked on this machine (macOS 27.0.1,
arm64) unless a line says otherwise.

## 1. Summary

- The upstream scripts are LuaJIT (Lua 5.1 + `ffi`) programs for a Windows build of
  VBA-ReRecording. Speech (`tolk.lua`), dialogs (`win-controls.lua`), text encoding
  (`encoding.lua`) and CRC (`crc32.lua`) call Windows DLLs through `ffi`; sound uses a
  native Lua module `audio.dll`. None of that can run in mGBA, which embeds plain
  Lua 5.4.7 without FFI. Those five pieces must be replaced; the game logic can stay.
- mGBA 0.10.5 (the current stable, installed here with `brew install --cask mgba-app`)
  gives Lua: memory reads with Game Boy bus addresses, linear ROM reads across banks,
  a per-frame callback, TCP sockets (client and server), `io`, `os.execute` and
  `os.getenv`. It does not give: keyboard events, a `--script` option, breakpoints,
  `io.popen`, or any audio API.
- mGBA 0.11 (development builds, signed universal app, not yet released) adds
  `--script FILE`, raw keyboard events with modifiers, autorun scripts, and
  breakpoints. Verified by running the probe on build `0.11-9155-143adf5aa`.
- The biggest unknown is settled: on 0.10.5 a script cannot see keyboard keys, only
  emulated Game Boy buttons. On 0.11 it can. The port therefore needs the Swift helper
  to capture hotkeys on 0.10.5, exactly as anticipated in the plan, and can take keys
  from mGBA directly on 0.11.
- Loading the script without a mouse works on 0.10.5 through the Accessibility API:
  open Tools > Scripting, set the prompt text field's value to
  `dofile("/path/entry.lua")` and press Run. Scripts keep running after the Scripting
  window is closed. On 0.11 the launcher passes `--script` instead.
- Speech: a Swift command-line process using AVSpeechSynthesizer starts audio in about
  19 ms and interrupts cleanly (verified). VoiceOver also accepts
  `tell application "VoiceOver" to output "..."` on this Mac (AppleScript control is
  already enabled). The `say` command needs a fresh process per utterance and cannot
  be interrupted except by killing it, so it stays the fallback.
- Proposed architecture: a VBA-API compatibility shim on top of a small platform
  layer, so `pokemon.lua`, `gb.lua`, `game/**`, `a-star.lua` and `message/**` remain
  byte-identical to upstream; a Swift helper that owns speech, sound cues, dialogs,
  hotkeys and launching; a line-based protocol over a localhost TCP socket between
  the two. Details in section 6.

## 2. Method and evidence

Repository: cloned `https://github.com/nuive/pokemon-access` (26 commits, version
3.1.0) into this directory, remote renamed to `upstream`, work on branch
`macos-port`.

Probe tooling added under `tools/mgba-probe/`:

| File | Purpose |
|------|---------|
| `make_test_rom.py` | Generates a 64 KiB Game Boy ROM (no game content) that writes known bytes to WRAM and HRAM, runs a counter, and places `PROBE1..3` markers in ROM banks 1 to 3. Lets memory reads be checked without a commercial ROM. |
| `probe.lua` | Runs inside mGBA. Records runtime globals, `emu` methods, memory domains, callback behaviour, socket client and server, `os`/`io` availability, and key events. Writes `results.txt`. |
| `load_script.applescript` | Loads a script into a running mGBA 0.10.x through the Scripting window using the Accessibility API. |
| `run_probe.sh` | End-to-end runner: builds the ROM, starts a TCP listener, launches mGBA, loads the probe (menu or `--script`), sends keystrokes, pings the Lua-side server, closes the Scripting window, prints results. |

Re-run with:

```
tools/mgba-probe/run_probe.sh /tmp/probe-out                      # mGBA 0.10.5 from /Applications
tools/mgba-probe/run_probe.sh /tmp/probe-dev /path/to/mGBA-dev.app cli   # 0.11 build, --script
```

The runner needs Accessibility permission for the terminal that runs it. Both runs
isolate mGBA's settings with `XDG_CONFIG_HOME`, which this build honours.

Other evidence: mGBA source for 0.10.5 and master (Lua engine, Qt scripting
controller, command line, autorun model), the official scripting docs (written for
0.10.2), a Lua 5.4.9 parse of every upstream file (`luac -p`: all 166 files parse),
and a throwaway Swift speech spike compiled with `swiftc`. A fresh reviewer read a
draft of this document against the repository; its corrections are folded in.

nuive's own GitHub forks of mgba and visualboyadvance-m contain nothing related to
these scripts (the mGBA fork is zero commits ahead of upstream, the VBA-M fork has
one unrelated commit), so there is no upstream mGBA port to build on or coordinate
with.

## 3. Upstream touchpoint inventory

Files on the Red/Blue path: `pokemon.lua` (entry), `gb.lua` (Game Boy engine),
`game/common/rby.lua` (Red/Blue/Yellow logic), `game/red_blue/main.lua`,
`game/red_blue/en/{chars,fonts,maps,memory,sprites}.lua` (data), `message.lua` and
`message/en.lua` (strings), `a-star.lua`, `serpent.lua`. Windows-only glue:
`tolk.lua`, `win-controls.lua`, `encoding.lua`, `crc32.lua`. GBA-only: `gba.lua`,
`game/common/{rse,frlg}.lua` (later phase).

### 3.1 Emulator API (VBA-ReRecording)

| Call | What it does | Where it is used | mGBA replacement |
|------|--------------|------------------|------------------|
| `memory.readbyte(addr)`, `memory.readbyteunsigned(addr)` | 8-bit read at a Game Boy bus address: RAM, VRAM, and ROM bank 0 for the cartridge header (`pokemon.lua:995` reads 0x13F) | `pokemon.lua:176,758,762,995`; `gb.lua:254,267,540-542,558,628-629,640`; `rby.lua` 35 sites (map header, objects, flags, keyboard cursor); `game/red_blue/main.lua:5` | `emu:read8(addr)`; verified bus semantics, including `0x134` in ROM bank 0 |
| `memory.readword(addr)` | 16-bit little-endian read at a bus address | `gb.lua:321-330`; `rby.lua:90,196,231,370,405,604` | `emu:read16(addr)`; verified |
| `memory.readbyterange(addr, n)` | Returns a 1-based table of `n` bytes | `gb.lua:47` (the 20x18 tile map at 0xC3A0, every frame); `pokemon.lua:917` (ROM title) | `emu:readRange(addr, n)` returns a string; wrap as `{s:byte(1, -1)}` |
| `memory.gbromreadbyte(off)`, `memory.gbromreadword(off)` | Read from the ROM image by linear offset, independent of the mapped bank (offsets up to 0x707a9 are used) | `gb.lua:187-195,653`; `rby.lua:91-92,129-158,199-244,377-380,411-414` | `emu.memory.cart0:read8(off)` / `:read16(off)`; verified linear across banks (`PROBE2` at 0x8100, `PROBE3` at 0xC100) |
| `memory.registerexec(addr, fn)` | Run `fn` when the CPU executes `addr`; `fn = nil` unregisters | `pokemon.lua:1057-1058` (0x100 and 0x8000000, re-init on reset); `pokemon.lua:819` (unregister); `rby.lua:659` (0x603 footstep routine, plays tile sounds) | 0.10.5 has no breakpoints: use the `reset` and `start` callbacks for re-init, and detect footsteps by polling player x/y per frame. 0.11: `emu:setBreakpoint(fn, addr)` exists (verified present) |
| `emu.frameadvance()` | Yield until the next frame | `pokemon.lua:1060-1063` (main loop), `pokemon.lua:632` (keeps the emulator responsive during long A* searches) | No equivalent; run upstream code in a coroutine and resume it from `callbacks:add("frame")` with `emu.frameadvance = coroutine.yield` |
| `emu.platform()` | 0 = GBA, 1 = GB | `pokemon.lua:898` | `emu:platform()` uses the same values (`C.PLATFORM.GBA = 0`, `C.PLATFORM.GB = 1`), verified |
| `input.read()` | Table of currently held keyboard keys, names like `"T"`, `"shift"`, `"0"`, plus mouse fields | `pokemon.lua:465` (`handle_user_actions`, compared against the `commands` table at `pokemon.lua:824-853`) | Not available in 0.10.5 Lua. Build the table from key events delivered by the Swift helper (0.10.5) or from `callbacks:add("key")` (0.11) |
| GBA-only: `memory.readdword`, `memory.readbytesigned`, `memory.getregister`, `memory.registerwrite` | 32-bit reads, CPU registers, write hooks | `gba.lua`, `game/common/rse.lua`, `game/common/frlg.lua` | `emu:read32`, `emu:readRegister("r0")`, `emu:setWatchpoint` (0.11 only). Later phase |

### 3.2 Operating system and process

| Call | What it does | Where it is used | macOS replacement |
|------|--------------|------------------|-------------------|
| `require "ffi"`, `ffi.load("tolk")`, `Tolk_Output`, `Tolk_Silence` | Speech through Tolk to NVDA/JAWS; `output(s)` queues, never interrupts; `silence()` stops | `tolk.lua`; `tolk.output` is called 34 times in `pokemon.lua`, 11 in `gb.lua`, 3 in `rby.lua` (plus GBA files); `tolk.silence` at `pokemon.lua:491` before every hotkey command | Helper speech engine over the socket (`SPEAK`, `SILENCE`); `say` fallback |
| `ffi.load("win-controls")`, `InputBox`, `ComboBox` | Modal Windows dialogs: text entry and single or multi select list | `win-controls.lua`; `controls.inputbox` at `pokemon.lua:713,737` (rename object, rename map); `controls.combobox` at `pokemon.lua:965,1011,1019,1030,1037` (hack ROM setup) | Helper shows an NSAlert with a text field or a list; Lua side yields frames until the reply arrives |
| `ffi.load("kernel32")`, `MultiByteToWideChar`, `WideCharToMultiByte` | UTF-8 to UTF-16 for the Windows APIs | `encoding.lua` | Not needed; macOS APIs take UTF-8 |
| `ffi.load("crc32")` | CRC32 of ROM data to tell FireRed revisions apart | `crc32.lua`, used by `gba.lua` only | `emu:checksum(C.CHECKSUM.CRC32)` returns the 4 CRC bytes (verified). Later phase |
| `package.loadlib("audio.dll", "luaopen_audio")` | Loads the native `audio` module | `pokemon.lua:1053` (asserts, so the script dies if the DLL is missing) | Shim `package.loadlib` to hand back the platform sound module for this name, or patch the line (see 6.5) |
| `audio.play(path, loop, pan, vol)` returns a handle; `audio.stop(handle)`, `audio.pitch(value, handle)` | Plays a WAV with pan -100..100 and volume 0..100; the GBA code keeps handles to stop or re-pitch looping cues | `gb.lua:230,240,242,249,516`; `rby.lua:548-583` (tile and ledge sounds); `rse.lua:165-193` (GBA, later) | Helper plays the file with AVAudioPlayer (`pan`, `volume`, `rate`) and returns an id; `afplay` fallback without pan |
| `io.popen("dir /b ...")`, `io.popen("dir /b /ad ...")` | List files and directories (hack ROM setup) | `pokemon.lua:34,57,79` | `io.popen` is compiled out of mGBA's Lua (`'popen' not supported`, verified). Ask the helper (`LIST_DIR`) or ship a manifest |
| `os.rename(path, path)` | Existence check | `pokemon.lua:21` | Works on macOS once paths use `/` |
| `io.open` / `io.close` | Read and write `names_<game>_<lang>.lua` and `hacks.lua` with serpent; read expansion headers | `pokemon.lua:81,187-191,727-729,971-973,1046-1048` | Works; relative filenames resolve against the process working directory, so the launcher must set it to a per-user data directory |
| `loadfile(path)` with `\\` separators | Loads `gb.lua`/`gba.lua`, `game/<game>/<lang>/*.lua`, `game/common/<core>.lua`, `game/<game>/main.lua`, expansions, `message/<lang>.lua` | `pokemon.lua:100,110,122,129,149,163,823`; `message.lua:4` | Translate `\` to `/` in a `loadfile`/`io.open` wrapper, or patch the strings (forward slashes also work on Windows) |
| `debug.getinfo(1, "S").source` | Script directory discovery | `pokemon.lua:5` | Works in mGBA: source is `@/absolute/path.lua` (verified, also when loaded via `dofile` from the prompt) |
| `require "a-star"`, `"serpent"`, `"message"`, `"win-controls"`, `"tolk"` | Module loading from the script directory | `pokemon.lua:1-4,1052` | mGBA's `require` adds the loaded script's directory; the entry script should also set `package.path` explicitly because `dofile` from the prompt does not go through mGBA's loader |

### 3.3 Lua 5.1 / LuaJIT features that do not exist in Lua 5.4

| Feature | Where | Status in mGBA (verified) | Fix |
|---------|-------|---------------------------|-----|
| `bit.band/bor/rshift/lshift/bnot` | `pokemon.lua:244`; `gb.lua:255,364,610`; `rby.lua` 14 sites; GBA files heavily | `bit` is nil | Provide a `bit` table implemented with 5.4 operators |
| `unpack` | `pokemon.lua:492`, `rby.lua:321`, `gsc.lua`, `gba.lua` | nil | `unpack = table.unpack` |
| `module("astar", package.seeall)` | `a-star.lua:26` | nil | Provide `module` (sets the caller chunk's `_ENV` upvalue to a new global table with `__index = _G`) or patch the first line |
| `math.pow` | `a-star.lua:41` | nil | `math.pow = function(a, b) return a ^ b end` |
| `string.format("%d", x)` with a non-integral float | `gb.lua:151-170` and others pass integers today; division results such as `(i-1)/20` at `gb.lua:62` are floats used only as table keys and in arithmetic | Raises "number has no integer representation" | Audit while testing; use `//` where an integer is required |
| `loadstring`, `setfenv` | `serpent.lua` | nil, but serpent already falls back to `load` and guards `setfenv` | None |
| Locale | `string.format("%0.2f%%")` at `gb.lua:543` | mGBA's process runs with the user's locale: `%.3f` printed `0,322` | Call `os.setlocale("C", "numeric")` at start, or format health without `%f` |

Everything parses under Lua 5.4.9 (`luac -p` on all 166 files reported no errors), so
the differences are runtime only.

### 3.4 Keyboard commands expected by upstream

From `pokemon.lua:824-853` (names as `input.read()` reports them): `Y`, `J`, `K`,
`L`, `P`, `T`, `M`, `E`, `D`, `G`, `R`, `V`, `F`, `C`, `H`, each alone or with
`shift`, plus `shift+0`. Game Boy buttons are left to the emulator. mGBA 0.10.5's
default keyboard bindings are X = A, Z = B, A = L, S = R, Return = Start,
Backspace = Select, arrows = D-pad (from the generated `config.ini`), identical to
what the upstream readme describes for VBA. mGBA's other default shortcuts use
modifiers or Tab, backtick, tilde, Escape and function keys, so no upstream hotkey
collides with an mGBA default. The helper will swallow the hotkeys it consumes so
nothing reaches mGBA anyway.

## 4. mGBA findings

### 4.1 Versions available

| | 0.10.5 stable | 0.11 development |
|---|---|---|
| Install | `brew install --cask mgba-app` (done here) or the dmg from mgba.io; universal binary, runs natively on arm64 | `https://s3.amazonaws.com/mgba/mGBA-build-latest-macos.dmg`; universal; signed with a Developer ID (`TeamIdentifier=VY3RGA6GFN`, hardened runtime); version string `0.11-9155-143adf5aa` at the time of testing |
| Lua | 5.4.7, `luaL_openlibs` (all standard libraries) | same |
| Keyboard to scripts | No. `callbacks:add("key")` is accepted but never fires (verified with synthetic key presses) | Yes. `callbacks:add("key", fn)` fires with `ev.key`, `ev.state`, `ev.modifiers` (section 4.4) |
| Load script at startup | No command-line option. Menu only | `--script FILE`, repeatable; also an autorun list stored in the config (`autorunSettings`) |
| Breakpoints | None (`emu.setBreakpoint` is nil) | `emu:setBreakpoint`, `setWatchpoint`, `setRangeWatchpoint`, `clearBreakpoint` present |
| Extra APIs | `util` | `input`, `storage`, `image`, `canvas` |

Homebrew's source formula `mgba` (0.10.5) is deprecated because it needs Qt 5; the
cask is the right install path.

### 4.2 Memory access (verified with the generated ROM)

- `emu:read8(0xC000)`, `emu:read8(0xD000)`, `emu:read8(0xFF80)` returned the bytes the
  ROM wrote; `emu:read16(0xC010)` returned `0x1234` (little-endian). Bus addresses, as
  the upstream `memory.readbyte` expects.
- `emu:readRange(addr, n)` returns a binary string; `emu:readRange(0xC000, 4)` gave
  `42 9a 00 00`.
- Memory domains for GB: `cart0` (base 0, bound 0x8000, size = ROM size), `vram`,
  `sram`, `wram`, `oam`, `io`, `hram`. Domain reads take an offset from the domain
  base, split into bank segments: `emu.memory.cart0:readRange(0x8100, 6)` returned
  `PROBE2` and `0xC100` returned `PROBE3`, so cart0 offsets are linear ROM offsets.
  This is exactly `memory.gbromreadbyte`.
- `emu:read8(0x8100)` read VRAM, confirming that bus reads and ROM-offset reads are
  different things and must not be mixed.
- Cost: 360 `emu:read8` calls took 0.13 to 0.56 ms; one `readRange` of 360 bytes took
  0.003 to 0.054 ms. The per-frame screen read is cheap either way.

### 4.3 Callbacks and runtime behaviour

- `frame` fires once per frame (601 calls after 600 frames). `keysRead` fires only when
  the game reads the joypad register, which the test ROM never does.
- `emu:getKeys()` reflects keyboard-bound buttons: holding X produced mask 1 (A) for
  25 frames on both versions.
- `start` did not fire for a script loaded after the ROM, nor for `--script` on 0.11
  (the script ran at frame 0, so the event had already passed). Detect "ROM present"
  by `emu ~= nil` and register `start` and `reset` for later changes.
- Scripts keep running after the Scripting window is closed (0.10.5: the window was
  closed six seconds after load, the 600-frame report was still written).
- `os.execute` works (`touch` created a file), `os.getenv` works and inherits the
  launcher's environment, `io.open` works, `io.popen` raises `'popen' not supported`.
- `XDG_CONFIG_HOME` moves mGBA's `config.ini` and `qt.ini` (default location on this
  build is `~/.config/mgba`). The launcher can give the game its own mGBA settings
  without touching the user's.
- `package.path` is the stock Lua path; mGBA's `require` adds the loaded script's
  directory at call time. `debug.getinfo(1, "S").source` is `@/absolute/path`.
- `console:log` output is only visible in the Scripting window; the probe wrote files
  and used sockets to get data out.

### 4.4 Keyboard events on 0.11

Pressing t, shift+h, j and x in the game window produced, in order:

```
key=84 state=1 mods=0      t down  (84 = "T": letters arrive as uppercase ASCII)
key=84 state=0 mods=0      t up
key=8388658 state=1 mods=3 shift down (special key constant; mods 3 = C.KMOD.SHIFT)
key=72 state=1 mods=3      h down with shift
key=72 state=0 mods=3
key=8388658 state=0 mods=0
key=74 state=1 mods=0      j
key=74 state=0 mods=0
key=88 state=1 mods=0      x (also set the A button, mask 1)
key=88 state=0 mods=0
```

`state` is `C.INPUT_STATE.DOWN` (1) / `UP` (0) / `HELD` (2 for autorepeat). Events
arrive only while an mGBA window has keyboard focus, which is also what the upstream
scripts assume. Mapping to upstream names is direct: `string.char(key)` for letters
and digits, `"shift"` from the modifier mask.

Not yet verified: how the shift+0 chord (hack ROM setup) arrives. Qt reports the key
of the produced character for printable keys, so shift+0 is expected to arrive as
`)` (41) with the shift modifier rather than as `0` (48). The retest is prepared
(`run_probe.sh` now also sends `5` and shift+0) but the screen locked before it
could run; it needs an unlocked session. Mitigation either way: in Mode B map shifted
symbol codes back to their digits with a layout table; Mode A sees hardware key codes
and is unaffected.

### 4.5 Sockets

`socket.connect("127.0.0.1", port)` plus `sock:send` delivered a line to a terminal
listener; `socket.bind` + `listen` + `accept` with `received` callbacks received a
line sent from the terminal, on both versions. Callback delivery is driven from
mGBA's own loop, and `sock:receive` returns `nil, socket.ERRORS.AGAIN` when nothing
is pending, so polling once per frame is also fine.

### 4.6 Loading a script with no mouse on 0.10.5

Verified sequence through the Accessibility API (`load_script.applescript`):

1. Activate mGBA, click menu item `Scripting...` in menu `Tools` of the menu bar.
2. In window `Scripting`, find the first `text field` (the Lua prompt) and the button
   named `Run`. Assign `entire contents` to a variable before iterating; iterating it
   inline returns nothing.
3. Set the text field's value to `dofile("/absolute/path/to/entry.lua")` and click
   Run. Typing with `keystroke` does not reach Qt's line edit; setting the AX value
   does.
4. Optionally close the Scripting window. Scripts keep running.

The native file dialog (`File > Load script...`) was not reliable to drive and is not
needed. A Swift launcher can do the same steps with `AXUIElement` calls; it requires
the Accessibility permission that the hotkey capture needs anyway.

## 5. macOS findings for speech, sound, dialogs and input

| Topic | Finding |
|-------|---------|
| AVSpeechSynthesizer from a CLI process | Works without an app bundle. 180 voices installed. First audio callback after 19 ms, `stopSpeaking(at: .immediate)` returns true and the synthesizer is reusable immediately. `swiftc -O` builds the spike in about 19 s. |
| VoiceOver speech passthrough | `osascript -e 'tell application "VoiceOver" to output "..."'` spoke the text in 0.12 s wall time including process start. Requires "Allow VoiceOver to be controlled with AppleScript" in VoiceOver Utility, which is already enabled on this Mac. Uses the user's own VoiceOver voice and rate with no configuration. The dictionary's `output` command takes text and an optional spelling type and exposes no queue or interrupt parameter, so whether consecutive outputs queue or cut each other off has to be checked by ear in Phase 2; it could not be judged from this unattended session. Upstream depends on queueing (`output_lines` speaks up to 18 lines, `speak_path` one utterance per segment, `read_menu_item` up to three), so this route batches one command's utterances into a single `output` call. |
| `say` | 2.06 s wall time for a one-word utterance including startup; one process per utterance; no interruption except killing the process. Fallback only. |
| VoiceOver voice settings | Not readable from `com.apple.VoiceOver4/default.plist` with `plutil` (no voice or rate keys found), so "use VoiceOver's voice" is best achieved by routing speech through VoiceOver itself (above) rather than copying its settings into AVSpeechSynthesizer. |
| Sound cues | mGBA's Lua has no audio API on either version. The helper can preload the 33 WAV files (1.7 MB, 17 of them used on the Red/Blue path) into `AVAudioPlayer` instances, which expose `pan` (-1..1) and `volume` (0..1), matching `audio.play`'s pan -100..100 and volume 0..100. `/usr/bin/afplay` exists for a fallback without pan. |
| Dialogs | `NSAlert` with an accessory text field or a pop-up list is standard Cocoa and reads correctly in VoiceOver. AppleScript `display dialog` and `choose from list` would also work but block the emulator thread if called from Lua. |
| Accessibility permission | This session's parent app already has it (`AXIsProcessTrusted` true), which is why the probe could drive mGBA. A standalone helper app needs its own grant: `AXIsProcessTrustedWithOptions` with the prompt option opens the right System Settings pane. The permission covers both the `CGEventTap` hotkey capture and the AX-driven script loading. |
| Native toolchain | Swift 6.4 (`swiftc` and SwiftPM) with Xcode installed; Python 3.14 and Homebrew available. No Rosetta involved anywhere. |

## 6. Proposed architecture

### 6.1 Components

```
+------------------------------+        TCP 127.0.0.1        +--------------------------------+
| mGBA (0.10.5 or 0.11)        | <-------------------------> | pokemon-access-helper (Swift)  |
|  entry: pokemon-access.lua   |  Lua is the client,         |  speech: AVSpeechSynthesizer   |
|   platform/mgba.lua          |  helper is the server       |          or VoiceOver output   |
|   compat/vba-api.lua         |                             |  sounds: AVAudioPlayer         |
|   upstream: pokemon.lua,     |  Lua -> helper: SPEAK,      |  dialogs: NSAlert              |
|     gb.lua, game/**, a-star  |    SILENCE, SOUND, PROMPT_* |  hotkeys: CGEventTap           |
|     (unchanged)              |  helper -> Lua: KEY, REPLY  |  launcher: starts mGBA, loads  |
+------------------------------+                             |    the script, speaks errors   |
                                                             +--------------------------------+
```

1. `pokemon-access.lua` (entry, loaded into mGBA). Sets `package.path` to its own
   directory, loads `platform/mgba.lua` and `compat/vba-api.lua`, connects to the
   helper, then runs upstream `pokemon.lua` inside a coroutine. A `frame` callback
   resumes the coroutine once per frame, polls the socket, and dispatches key
   events. Errors inside upstream code are caught with `pcall`, logged, and spoken.
2. `platform/mgba.lua`. The primitives the plan asks for: `read8`, `read16`,
   `read_range`, `rom_read8`, `rom_read16`, `on_frame`, `on_reset`, `platform`,
   `speak(text, interrupt)`, `silence`, `play_sound(name, pan, vol)`,
   `prompt_text`, `prompt_choice`, `list_dir`, `poll_keys`, `log`. Implements the
   socket protocol and the `say`/`afplay` fallbacks when no helper is connected.
   On 0.11 it also registers `callbacks:add("key")` as an alternative key source.
3. `platform/vba.lua`. The same primitives on VBA-ReRecording (wrapping `ffi`, Tolk
   and `audio.dll`). Low priority, but it keeps the abstraction honest and gives
   upstream a path to adopt the layer.
4. `compat/vba-api.lua`. Recreates the VBA-RR Lua surface that upstream uses on top
   of the platform layer: `memory.*` (section 3.1), `input.read`, `emu.frameadvance`
   (yield) and `emu.platform`, the `tolk`, `audio` and `controls` modules
   (pre-registered in `package.loaded` so upstream's `require` calls get them), the
   `bit` table, `unpack`, `module`, `math.pow`, and wrappers for `loadfile`,
   `io.open`, `os.rename` and `package.loadlib` that translate `\` to `/` and route
   `audio.dll` to the platform sound module. `memory.registerexec` maps 0x100 and
   0x8000000 to reset handling and 0x603 to footstep detection by position polling
   (or a real breakpoint on 0.11).
5. `helper/` (SwiftPM package `PokemonAccessHelper`, `swift build -c release`,
   arm64 native). One executable with subcommands or flags:
   - server: listens on 127.0.0.1 (default port 46000, configurable), one client.
   - speech engine: AVSpeechSynthesizer queue with configurable voice and rate and
     `interrupt` support (verified to queue and to stop on demand); `--speech
     voiceover` routes utterances to VoiceOver via `NSAppleScript` in-process,
     batching all utterances received within one frame into a single `output`
     call because that route has no queue control.
   - sound engine: preloads `sounds/**` relative to the repository, plays with pan
     and volume.
   - hotkeys: a `CGEventTap` active only while the frontmost app is
     `com.endrift.mgba-qt`; converts key codes to upstream names, swallows mapped
     hotkeys, sends `KEY DOWN|UP`.
   - dialogs: text and list prompts as `NSAlert` on the main thread; replies by id.
   - launcher: `pokemon-access <rom>`; checks mGBA is installed (speaks the brew
     command if not), writes a private mGBA config (FPS in title bar off, volume
     lowered, default buttons), starts the server, launches mGBA with the ROM and
     either `--script` (if `mGBA --help` lists it) or the AX loading sequence, waits
     for the Lua `HELLO`, and speaks a clear message for every failure (no mGBA, no
     Accessibility permission, ROM not recognised, script error).
6. `bin/pokemon-access`. Thin shell wrapper that finds the helper binary.

### 6.2 Protocol

One message per line, UTF-8, fields separated by tabs, tabs and newlines inside text
escaped as `\t` and `\n`.

Lua to helper: `HELLO <protocol-version>`, `SPEAK <0|1 interrupt> <text>`, `SILENCE`,
`SOUND <relative path> <pan> <vol>`, `PROMPT_TEXT <id> <title> <caption> <default>`,
`PROMPT_CHOICE <id> <title> <caption> <0|1 multi> <default index> <item>...`,
`LOG <text>`.

Helper to Lua: `WELCOME <helper-version> <0.10|0.11 mode>`, `KEY DOWN|UP <name>`
(name exactly as upstream's `commands` table spells it: uppercase letters and digits
such as `T` and `0`, but lowercase `shift`; the match at `pokemon.lua:474-487` is a
sorted string comparison), `REPLY <id> OK|CANCEL <value>...`.

Flow for a dialog: upstream calls `controls.inputbox` synchronously; the shim sends
`PROMPT_TEXT` and loops `coroutine.yield()` (one frame per iteration) until the
matching `REPLY` arrives, then returns the value. Upstream code sees a blocking call,
the emulator keeps running.

### 6.3 Two input modes, one code path

- Mode A, mGBA 0.10.5 (what Homebrew installs): keys come from the helper's event tap;
  script loading is done by the helper through the Accessibility API; the helper
  needs the Accessibility permission.
- Mode B, mGBA 0.11: keys come from `callbacks:add("key")` in Lua; the launcher passes
  `--script`; the helper needs no special permission at all.

`platform/mgba.lua` exposes the same `poll_keys` either way; the launcher picks the
mode by probing `mGBA --help` for `--script`. Building Mode A is required for users
on the stable release; Mode B is cheap to add and becomes the default once 0.11
ships.

### 6.4 Upstream tracking

The upstream files on the Red/Blue path need zero edits with the shim approach; the
only deliberate additions are new files (`pokemon-access.lua`, `platform/`, `compat/`,
`helper/`, `bin/`, `tools/`, this document). `git merge upstream/master` stays trivial.

Cleanups worth proposing upstream later, which would let the shim shrink: forward
slashes in the `loadfile` paths (they work on Windows too), guarding the
`package.loadlib("audio.dll")` line, replacing `module(...)` in `a-star.lua` with a
local table, and `unpack = unpack or table.unpack`.

### 6.5 Accessibility of every user-facing step

- Install: `brew install --cask mgba-app`, `git clone`, `swift build` in Terminal,
  which is fully usable with VoiceOver. A later `brew` formula or tap can collapse
  this to one command.
- Permission: the helper requests Accessibility with the system prompt and speaks
  what to do; it re-checks on every launch and never silently falls back.
- Launch: one command with the ROM path; everything else is automatic. mGBA's window
  gets focus; the Scripting window is closed again after loading so VoiceOver has
  one window to deal with.
- Errors: every failure is spoken through the helper's own speech, which does not
  depend on mGBA or Lua being alive, and logged to a file in the data directory.
- Settings that fight the screen reader: the private mGBA config turns off the FPS
  counter in the window title (the upstream readme had to do the same for VBA) and
  lowers game audio so speech stays audible.
- Data files: `names_*.lua` and `hacks.lua` go to
  `~/Library/Application Support/Pokemon Access/` by setting mGBA's working directory
  there at launch.

### 6.6 Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Driving mGBA's Qt UI through Accessibility breaks with an mGBA update | Only needed for Mode A; the sequence is three steps and already encapsulated; Mode B removes it |
| CGEventTap and Accessibility permission confuse first-time users | Spoken onboarding; permission state checked on every start |
| 0.11 is a moving target | Nothing in the design depends on 0.11; its features are detected at runtime |
| Lua 5.4 integer/float semantics expose latent upstream bugs | Run every hotkey against the real ROM in Phase 3; keep a list of any `//` or `math.floor` fixes to propose upstream |
| Locale decimal comma | Set the numeric locale to C in the entry script |
| Footstep detection by polling differs slightly from the exec hook | Fire on player x/y or map change while `on_map()`; use the breakpoint on 0.11 |
| VoiceOver single-key Quick Nav intercepts letters | Document that Quick Nav must be off while playing, as with any game |
| The volume and pan scale of the Windows `audio.dll` is unknown: its source is not published, and nuive's forks of mGBA and VBA-M carry no related change. Upstream passes volumes of 5 to 40 and pan steps of 5 per tile | Treat volume as linear percent and pan as linear, expose a global gain in the helper config, calibrate by ear against the Windows build before Phase 3 step 7 |
| macOS ties the Accessibility grant to the helper's code signature, so an unsigned rebuild loses it | Sign development builds with a stable identity (`codesign -s` with a Developer ID or a locally created certificate) and re-check the grant on every start |

## 7. Phase 3 steps, mapped to the pieces above

1. "Ready" spoken on load: entry script, compat shim core (memory, frameadvance
   coroutine, require preloading), helper speech server, launcher with Mode A loading
   (and Mode B when available).
2. `t` reads on-screen text: key path end to end (event tap or Lua key events),
   `input.read` emulation, `get_screen` on `emu:readRange`.
3. `m` and `y`: plain bus reads, already covered by step 1.
4. `j`, `k`, `l`: linear ROM reads through `cart0`, object and warp enumeration.
5. `p`: `module` and `math.pow` shims for `a-star.lua`; the coroutine must keep
   yielding during long searches (`advance_pathfinder_counter`).
6. `h` and shift+h: modifier handling in the key path.
7. Camera keys: sound engine with pan and volume.
8. Sound cues: footstep detection replacing `registerexec(0x603)`.
9. Proposed addition: shift+K and shift+M rename prompts through `PROMPT_TEXT` and
   the yield-until-reply shim. Hack ROM setup (shift+0, list prompts plus directory
   listing) stays out until a later phase; see decision 6.

## 8. Decisions needed before Phase 2

1. mGBA version strategy: build Mode A for the stable 0.10.5 with Mode B as a runtime
   extra (recommended), or target 0.11 development builds only (simpler, no
   Accessibility permission, but nightly builds until 0.11 is released).
2. Default speech engine: AVSpeechSynthesizer with a configurable voice and rate
   (recommended for latency and control), or VoiceOver passthrough so the player hears
   their own VoiceOver voice. Both will be available; the question is the default.
3. Keep upstream files byte-identical through shims (recommended), or allow the small
   upstream patches listed in 6.4 right away.
4. Launcher shape for the first release: a Terminal command `pokemon-access <rom>`
   (recommended for Phase 3), or an application bundle from the start.
5. The path to your Pokémon Red or Blue ROM for Phase 3 testing. Nothing in Phase 1
   needed it; the probe used a generated test ROM.
6. Dialog-driven commands in the first release. Shift+K and shift+M (rename) need the
   text prompt; shift+0 (hack ROM setup) needs four or five list prompts plus
   directory listing, which mGBA's Lua cannot do by itself. Recommendation: rename
   prompts as Phase 3 step 9, hack ROM setup deferred. English Red and Blue are
   recognised by header checksums 0x91e6 and 0x9d0a (`gb.lua:13,19`), so a standard
   dump needs no setup; any other dump would currently be reported as unsupported.
7. Who installs the first release. This Mac only, built from source (recommended for
   Phase 3), or other players, which adds a stable signing identity, notarization, a
   prebuilt download and a minimum macOS version to test. Everything so far ran on
   macOS 27.0.1 with Swift 6.4.
