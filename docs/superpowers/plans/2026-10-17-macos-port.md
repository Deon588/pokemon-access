# Pokémon Access macOS Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the upstream Pokémon Access Lua scripts inside mGBA on Apple Silicon so a VoiceOver user can play Pokémon Red/Blue (English) with speech, sound cues and the upstream hotkeys, launched from an application bundle.

**Architecture:** A compatibility shim (`compat/`) recreates the VBA-ReRecording Lua API that the untouched upstream scripts expect, on top of a small platform layer (`platform/`) that talks to mGBA's Lua runtime and, over a local TCP line protocol, to a native Swift helper app. The helper app speaks (VoiceOver passthrough, AVSpeechSynthesizer, `say`), plays WAV cues, shows prompts, captures hotkeys with Carbon hot keys on mGBA 0.10.5, and launches mGBA with the ROM and the script. Upstream `pokemon.lua` runs inside a coroutine resumed once per emulated frame.

**Tech Stack:** Lua 5.4 (mGBA 0.10.5 embeds 5.4.7; tests run on Homebrew `lua@5.4`, 5.4.9), Swift 6.4 with SwiftPM in Swift 5 language mode, AppKit, AVFoundation, Network.framework, Carbon HIToolbox hot keys, ApplicationServices Accessibility API, zsh scripts, Python 3 for the development fake helper.

**Spec:** `PORTING.md` (sections 3, 6, 7 and the decisions in section 8).

## Global Constraints

- Never download or bundle a ROM. The app only opens ROM files the player supplies; the generated `tools/mgba-probe` test ROM is the only ROM used by automated checks.
- Apple Silicon native only: arm64 binaries from the installed Swift 6.4 toolchain, no Rosetta, no Windows VM.
- The runtime is mGBA's Lua 5.4.7 with no `io.popen`, no FFI, no audio API. Tests run with `LUA=/opt/homebrew/opt/lua@5.4/bin/lua5.4`.
- Upstream files on the Red/Blue path stay byte-identical unless a patch is recorded in `PORTING.md` section 6.4 (decision 3). New code lives in `pokemon-access.lua`, `compat/`, `platform/`, `helper/`, `scripts/`, `tools/`, `tests/`, `docs/`.
- Every user-facing step works with VoiceOver: no mouse-only UI, every failure is spoken and written to the log file.
- Speech default: VoiceOver passthrough when VoiceOver is running, AVSpeechSynthesizer otherwise, `/usr/bin/say` as the last resort (decision 2).
- Line protocol version `1`, TCP on `127.0.0.1` only, fields separated by tabs, text escapes `\\`, `\t`, `\n` (PORTING.md 6.2).
- Key names exactly as upstream spells them: uppercase letters and digits, lowercase `shift`, chord form `shift+H` (PORTING.md 6.2).
- Bundle identifier `com.abstractsingleton.pokemon-access`, app name `Pokemon Access`, executable `PokemonAccess`, minimum macOS 14.
- Commits are small logical steps with imperative messages and no attribution or co-author lines. Markdown is plain: no box-drawing characters, no em dash.

## Review Focus

1. Text with non-ASCII characters ("Pokémon", accented names) must reach the speech engine unchanged. Pinned by the protocol round-trip tests in Task 2 (Lua) and Task 9 (Swift).
2. A Lua error inside upstream code must neither stop the emulator nor repeat the error every frame. Pinned by the runner test with a throwing chunk in Task 8.
3. The helper absent at start or gone mid-game: the script keeps running, speaks through `say`, and reconnects when the helper is back. Pinned by the refused-connection and error-callback tests in Tasks 6 and 7.
4. Paths with spaces (the data directory `Pokemon Access` has one) inside the `dofile` snippet and the launch arguments. Pinned by the snippet test in Task 13b.
5. A ROM whose header title carries padding bytes or whose checksum is unknown must be reported, not crash the launcher. Pinned by the `RomHeader` tests in Task 9 and the warning copy in Task 13c.

---

### Task 1: Lua test harness and Lua 5.1 polyfills

**Files:**
- Create: `tests/lua/run.sh`, `tests/lua/check.lua`
- Create: `compat/bit.lua`, `compat/lua51.lua`
- Test: `tests/lua/test_bit.lua`, `tests/lua/test_lua51.lua`

**Interfaces:**
- Produces: `check.eq(actual, expected, label)`, `check.truthy(value, label)`, `check.falsy(value, label)`, `check.error(fn, pattern, label)`, `check.done()` (prints `ok <count>` or the failures and exits 1). `tests/lua/run.sh` runs every `tests/lua/test_*.lua` from the repository root with `LUA_PATH="./?.lua;./tests/lua/?.lua;;"` and `${LUA:-/opt/homebrew/opt/lua@5.4/bin/lua5.4}`, failing on the first failing file.
- Produces: `require("compat.bit")` returns `{band, bor, bxor, bnot, lshift, rshift, arshift, tobit, tohex}` with LuaJIT semantics (32-bit, results as signed 32-bit integers, float inputs truncated).
- Produces: `require("compat.lua51").install()` sets `_G.unpack = table.unpack`, `math.pow`, `_G.loadstring = loadstring or load`, and `_G.module(name, ...)` which creates or reuses `_G[name]`, stores it in `package.loaded[name]`, sets `_NAME` and `_M`, applies each option function (so `package.seeall` works), and replaces the calling chunk's `_ENV` upvalue with that table via `debug.getinfo(2, "f").func` and `debug.setupvalue`.

- [ ] **Step 1: Write `tests/lua/check.lua` and `tests/lua/run.sh`**; `chmod +x tests/lua/run.sh`.
- [ ] **Step 2: Write `tests/lua/test_bit.lua`** asserting: `band(0xff, 0x0f) == 15`, `bor(0xf0, 0x0f) == 255`, `bxor(0xff, 0x0f) == 0xf0`, `lshift(1, 4) == 16`, `rshift(0x80, 7) == 1`, `bnot(0) == -1`, `lshift(1, 31) == -2147483648`, `rshift(-1, 28) == 15`, `arshift(-16, 2) == -4`, `tobit(0xffffffff) == -1`, `tohex(255) == "000000ff"`, `band(255.0, 15) == 15`, `band(0x1234, 0xff00) == 0x1200`.
- [ ] **Step 3: Run `tests/lua/run.sh`**. Expected: FAIL, `module 'compat.bit' not found`.
- [ ] **Step 4: Implement `compat/bit.lua`** (normalise with `math.tointeger(v) or math.floor(v)`, mask with `& 0xffffffff`, convert back to signed).
- [ ] **Step 5: Run `tests/lua/run.sh`**. Expected: `ok` for test_bit.
- [ ] **Step 6: Write `tests/lua/test_lua51.lua`**: after `install()`, `select("#", unpack({1, 2, 3})) == 3`, `math.pow(2, 10) == 1024`; `load('module("probe_mod", package.seeall) function f() return math.max(1, 2) end', "=probe")()` then `probe_mod.f() == 2`, `package.loaded.probe_mod == probe_mod`, `_G.probe_mod == probe_mod`; a second chunk calling `module("probe_mod")` and defining `g` makes `probe_mod.g` available on the same table; `_G.f == nil` (module functions do not leak).
- [ ] **Step 7: Run**. Expected: FAIL, `module 'compat.lua51' not found`.
- [ ] **Step 8: Implement `compat/lua51.lua`**.
- [ ] **Step 9: Run `tests/lua/run.sh`**. Expected: both files `ok`.
- [ ] **Step 10: Commit** `Add Lua test harness, bit library and Lua 5.1 polyfills`.

### Task 2: Line protocol (Lua side)

**Files:**
- Create: `platform/protocol.lua`
- Test: `tests/lua/test_protocol.lua`

**Interfaces:**
- Produces: `protocol.escape(s)`, `protocol.unescape(s)`, `protocol.encode(fields) -> string` (joined with tabs, terminated by `\n`; booleans become `1`/`0`; numbers with `math.tointeger` become `%d`, other numbers `tostring`), `protocol.decode(line) -> fields` (splits on tabs, unescapes each, strips one trailing `\r`), `protocol.LineBuffer.new() -> buffer` with `buffer:feed(chunk) -> {complete lines without newline}`.
- Escapes: `\` to `\\`, tab to `\t`, newline to `\n`; unescape maps any other `\c` to `c`.

- [ ] **Step 1: Write `tests/lua/test_protocol.lua`**: `encode({"SPEAK", 1, "a\tb\nc\\d"}) == "SPEAK\t1\ta\\tb\\nc\\\\d\n"`; `decode("KEY\tDOWN\tshift+H")` equals `{"KEY", "DOWN", "shift+H"}`; `decode(encode({"X", "Pokémon", true, false, 3.0, 1.5}))` equals `{"X", "Pokémon", "1", "0", "3", "1.5"}`; `unescape("\\q") == "q"`; buffer: `feed("HEL")` returns `{}`, `feed("LO\t1\nKEY\tDOWN\tT\nPAR")` returns `{"HELLO\t1", "KEY\tDOWN\tT"}`, `feed("T\r\n")` returns `{"PART"}`.
- [ ] **Step 2: Run**. Expected: FAIL, module not found.
- [ ] **Step 3: Implement `platform/protocol.lua`**.
- [ ] **Step 4: Run**. Expected: `ok`.
- [ ] **Step 5: Commit** `Add the helper line protocol for Lua`.

### Task 3: Held-key tracker

**Files:**
- Create: `platform/keys.lua`
- Test: `tests/lua/test_keys.lua`

**Interfaces:**
- Produces: `Keys.new() -> tracker`; `tracker:press(chord)`, `tracker:release(chord)` where a chord is names joined by `+` (`"shift+H"`, `"T"`, `"shift+0"`); `tracker:raw(key, state, modifiers)` for mGBA 0.11 key events; `tracker:held() -> table` (a fresh copy, name -> `true`); `tracker:clear()`.
- Raw mapping (values recorded in the Phase 1 probe): key 65..90 is that letter, 97..122 its uppercase letter, 48..57 the digit, 8388658 is `shift`; the shifted digit characters `) ! @ # $ % ^ & * (` (codes 41 33 64 35 36 37 94 38 42 40) map to `0`..`9`; `modifiers & 3 ~= 0` on a press also marks `shift`; state 1 = down, 0 = up, 2 (held repeat) ignored; unknown keys ignored.

- [ ] **Step 1: Write `tests/lua/test_keys.lua`**: `press("shift+H")` then `held()` equals `{H = true, shift = true}`; `release("shift+H")` then `held()` equals `{}`; `raw(84, 1, 0)` gives `{T = true}`, `raw(84, 0, 0)` clears it; `raw(8388658, 1, 3)` then `raw(72, 1, 3)` gives `{H = true, shift = true}`; `raw(41, 1, 3)` gives `{["0"] = true, shift = true}`; `raw(72, 2, 3)` changes nothing; mutating the table returned by `held()` does not change the next `held()`.
- [ ] **Step 2: Run**. Expected: FAIL.
- [ ] **Step 3: Implement `platform/keys.lua`**.
- [ ] **Step 4: Run**. Expected: `ok`.
- [ ] **Step 5: Commit** `Add the held-key tracker shared by both key sources`.

### Task 4: Speech batching

**Files:**
- Create: `platform/speech.lua`
- Test: `tests/lua/test_speech.lua`

**Interfaces:**
- Produces: `Speech.new(send) -> speech` where `send(interrupt, text)` is called at most once per flush; `speech:output(text)` appends (ignores `nil` and `""`, `tostring`s other values); `speech:silence()` drops pending lines and sets the interrupt flag; `speech:flush()` sends pending lines joined with `\n` (interrupt flag as recorded), or `send(true, "")` when only a silence is pending, or nothing; then resets.

- [ ] **Step 1: Write `tests/lua/test_speech.lua`**: three outputs then flush produce one call `(false, "a\nb\nc")`; `silence()` then `output("x")` then flush produce `(true, "x")`; `silence()` alone produces `(true, "")`; flush with nothing produces no call; `output("")` and `output(nil)` produce no call; `output(42)` produces `(false, "42")`.
- [ ] **Step 2: Run**. Expected: FAIL.
- [ ] **Step 3: Implement `platform/speech.lua`**.
- [ ] **Step 4: Run**. Expected: `ok`.
- [ ] **Step 5: Commit** `Batch speech per frame so VoiceOver gets one utterance per command`.

### Task 5: VBA API compatibility shim

**Files:**
- Create: `compat/vba_api.lua`
- Create: `tests/lua/fake_platform.lua`
- Test: `tests/lua/test_vba_api.lua`

**Interfaces:**
- Consumes the platform interface implemented in Task 7 (and faked here):
  `read8(addr)`, `read16(addr)`, `read32(addr)`, `read_range(addr, n) -> 1-based table`, `rom_read8(off)`, `rom_read16(off)`, `platform_id() -> 0|1`, `speak(text)`, `silence()`, `play_sound(path, loop, pan, vol) -> id`, `stop_sound(id)`, `set_pitch(id, value)`, `held_keys() -> table`, `prompt_text(title, caption, default) -> id`, `prompt_choice(title, caption, items, multi, default) -> id`, `take_reply(id) -> nil | {ok = boolean, values = {strings}}`, `set_breakpoint(addr, fn) -> boolean`, `log(text)`.
- Produces: `compat.install(platform) -> api` and `compat.fix_path(path)` (backslashes to `/`, runs of `/` collapsed). `api.reset_handler` (set by `memory.registerexec(0x100 | 0x8000000, fn)`), `api.exec_handlers` (addr -> fn for other addresses when `platform.set_breakpoint` returned false), `api.poll_exec()`.
- Globals installed: `memory.readbyte`, `readbyteunsigned`, `readbytesigned`, `readword`, `readdword`, `readbyterange`, `gbromreadbyte`, `gbromreadword`, `registerexec`; `emu.frameadvance = coroutine.yield`, `emu.platform`; `input.read()` returning `platform.held_keys()`; `bit`; `unpack`, `module`, `math.pow` (Task 1); wrappers for `loadfile`, `dofile`, `io.open`, `os.rename` applying `fix_path`; `io.popen` returning a handle whose `lines()` yields nothing and `close()` returns `true` after `platform.log("io.popen unsupported: <cmd>")`; `package.preload.tolk` (`output`, `silence`), `package.preload["win-controls"]` (`inputbox`, `combobox`), `package.loadlib` override: a name ending in `audio.dll` returns a loader that returns `{play, stop, pitch}`; any other name falls through to the original.
- `inputbox(title, caption, default)`: send `prompt_text`, then `coroutine.yield()` until `take_reply(id)` returns; result `values[1]` or `nil` on cancel. `combobox(title, caption, list, data)`: `multi = type(data) == "table"`, default `data`; single returns `tonumber(values[1])`, multi returns the numbers of all values, cancel returns `nil`.
- `audio.play(path, loop, pan, vol)`: `platform.play_sound(fix_path(path), loop == true or (type(loop) == "number" and loop ~= 0), pan, vol)`.
- `poll_exec()`: when `_G.RAM_MAP_NUMBER`, `_G.RAM_PLAYER_X`, `_G.RAM_PLAYER_Y` are numbers, read the three bytes; the first poll records; later polls call every `exec_handlers` function (with `pcall`, errors to `platform.log`) when the triple changed.

- [ ] **Step 1: Write `tests/lua/fake_platform.lua`**: `fake.new{mem = {}, rom = "", platform_id = 1, breakpoints = false}` returning the interface above; records every call in `fake.calls` as `{name, ...}`; `prompt_*` return increasing ids; tests set `fake.replies[id]`; `held` table is `fake.held`; `set_breakpoint` returns `fake.breakpoints`.
- [ ] **Step 2: Write `tests/lua/test_vba_api.lua`** covering: `readbyterange(0xC000, 3)` equals `{0x42, 0, 0x37}` for `mem = {[0xC000] = 0x42, [0xC002] = 0x37}`; `readword(0xC010)` with `0x34, 0x12` is `0x1234`; `readbytesigned` of `0xFF` is `-1`; `gbromreadword(0x14e)` little-endian from `rom`; `emu.platform() == 1`; `input.read()` equals `fake.held` by value; `compat.fix_path("/a/b/\\message\\en.lua") == "/a/b/message/en.lua"`; `io.open("tests\\lua\\check.lua")` returns a file; `require("tolk").output("hi")` records `{"speak", "hi"}` and `silence()` records `{"silence"}`; `assert(package.loadlib("C:\\x\\audio.dll", "luaopen_audio"))().play("/x/sounds\\gb\\s_grass.wav", 0, -100, 30)` records `{"play_sound", "/x/sounds/gb/s_grass.wav", false, -100, 30}` and returns `1`; `package.loadlib("other.so", "f")` returns `nil` plus a message; `inputbox` inside a coroutine yields, returns `"Blue"` after `fake.replies[1] = {ok = true, values = {"Blue"}}`, and `nil` on `{ok = false}`; `combobox` single returns `2` for values `{"2"}`, multi returns `{1, 3}`; `registerexec(0x100, f)` sets `api.reset_handler == f`; `registerexec(0x603, g)` with `breakpoints = false` sets `api.exec_handlers[0x603] == g`; with `RAM_MAP_NUMBER, RAM_PLAYER_X, RAM_PLAYER_Y` set, the first `poll_exec()` does not fire, changing the X byte fires once; `registerexec(0x603, nil)` removes it; `io.popen("dir /b x")` returns a handle whose `lines()` loop runs zero times; `bit.band(3, 1) == 1` and `unpack` exist.
- [ ] **Step 3: Run**. Expected: FAIL, `module 'compat.vba_api' not found`.
- [ ] **Step 4: Implement `compat/vba_api.lua`**.
- [ ] **Step 5: Run `tests/lua/run.sh`**. Expected: all files `ok`.
- [ ] **Step 6: Commit** `Add the VBA-ReRecording API shim over the platform layer`.

### Task 6: Helper link (socket client)

**Files:**
- Create: `platform/helper_link.lua`
- Create: `tests/lua/fake_socket.lua`
- Test: `tests/lua/test_helper_link.lua`

**Interfaces:**
- Consumes mGBA's socket API as verified in Phase 1: `socket.connect(host, port) -> sock | nil, err`, `sock:send(data) -> bytes | nil, err`, `sock:receive(max) -> data | nil, socket.ERRORS.AGAIN`, `sock:add("received", fn)`, `sock:add("error", fn)`, `sock:close()`.
- Produces: `Link.new(socket_lib, host, port) -> link`; `link:connect() -> ok, err`; `link.connected`; `link:send(fields) -> boolean` (encodes with `protocol.encode`; returns `false` when not connected); `link:on(type, fn)` (handler receives the decoded fields table); `link:poll()` (receives until AGAIN, feeds a `LineBuffer`, dispatches by first field, unknown types go to `link.on_unknown` if set); `link:close()`.
- Produces: `fake_socket.new() -> lib` with `lib.ERRORS = {AGAIN = "again"}`, `lib.refuse` flag, `lib.sent` (list of strings), `lib:push(data)`, and the created `sock` exposing `callbacks[name]`.

- [ ] **Step 1: Write `tests/lua/fake_socket.lua` and `tests/lua/test_helper_link.lua`**: connect succeeds (`link.connected == true`); `send({"HELLO", 1, "helper", "Lua 5.4"})` appends `"HELLO\t1\thelper\tLua 5.4\n"`; with `lib.refuse = true` connect returns `false` and `send` returns `false`; push `"WELCOME\t0.1\thelper\nKEY\tDOWN\tT\nKE"` then `poll()` calls the `WELCOME` handler with `{"WELCOME", "0.1", "helper"}` and the `KEY` handler with `{"KEY", "DOWN", "T"}`; push `"Y\tUP\tT\n"` then `poll()` calls `KEY` with `{"KEY", "UP", "T"}`; invoking the registered `error` callback sets `connected == false`.
- [ ] **Step 2: Run**. Expected: FAIL.
- [ ] **Step 3: Implement `platform/helper_link.lua`**.
- [ ] **Step 4: Run**. Expected: `ok`.
- [ ] **Step 5: Commit** `Add the socket link to the helper`.

### Task 7: mGBA platform layer and its VBA counterpart

**Files:**
- Create: `platform/mgba.lua`, `platform/vba.lua`
- Create: `tests/lua/fake_mgba.lua`
- Test: `tests/lua/test_mgba_platform.lua`

**Interfaces:**
- Consumes mGBA globals verified in Phase 1: `emu:read8/read16/read32/readRange`, `emu.memory.cart0:read8/read16/readRange`, `emu:platform()`, `emu:setBreakpoint(fn, addr)` (0.11 only), `callbacks:add(name, fn) -> id`, `callbacks:remove(id)`, `console:log`, `socket`, `os.getenv`.
- Produces: `platform/mgba.lua` returns `M` implementing the Task 5 interface plus: `M.setup(opts)` (`opts.port` or `POKEMON_ACCESS_PORT`, `opts.key_source` default `"auto"`), `M.has_key_events` (true when `rawget(_G, "input")` is a userdata at load time, which only 0.11 provides), `M.key_source` (`"lua"` when key events exist, else `"helper"`), `M.connected()`, `M.send_hello(info)` (`HELLO 1 <key_source> <info>`), `M.poll()` (link poll; reconnect attempt every 300 frames while disconnected), `M.end_frame()` (speech flush, sent as `SPEAK <0|1> <text>` or `SILENCE`), `M.on_frame(fn)`, `M.on_reset(fn)` (both `reset` and `start` callbacks), `M.shutdown()` (removes registered callbacks).
- Message handlers: `KEY DOWN|UP <chord>` -> tracker press/release; `REPLY <id> OK|CANCEL <values...>` -> stored for `take_reply`; `WELCOME` -> logged.
- Fallbacks when not connected: speech through `os.execute("(killall say 2>/dev/null; /usr/bin/say -- '<text>') >/dev/null 2>&1 &")` with single quotes escaped as `'\''`; silence through `killall say`; sounds through `afplay -v <vol/100> '<path>' &`; prompts answered immediately with `{ok = false}` and a log line.
- `platform/vba.lua`: the same interface for VBA-ReRecording using `memory.*`, `require "tolk"`, `package.loadlib("audio.dll", "luaopen_audio")`, `require "win-controls"` (prompts answered synchronously), `input.read()` without mouse fields. Not runnable here; checked with `luac5.4 -p`.

- [ ] **Step 1: Write `tests/lua/fake_mgba.lua`**: `fake.install{bus = {}, rom = "", platform_id = 1, key_events = false, env = {}}` sets globals `emu`, `callbacks` (with `fake:fire(name, ...)`), `socket` (from Task 6's fake), `console` (logs recorded in `fake.logs`), `input` userdata stand-in when `key_events` (a table is fine if `M` checks `~= nil`; use `type(...) ~= "nil"` in `M` and document), and overrides `os.getenv` and `os.execute` (recorded in `fake.executed`); `fake.remove()` restores.
- [ ] **Step 2: Write `tests/lua/test_mgba_platform.lua`**: with env port `48890`, `M.setup{}` connects and `M.send_hello("Lua 5.4")` sends `"HELLO\t1\thelper\tLua 5.4\n"`; `M.speak("a")`, `M.speak("b")`, `M.end_frame()` sends `"SPEAK\t0\ta\\nb\n"`; `M.silence()`, `M.end_frame()` sends `"SILENCE\n"`; `M.play_sound("/p.wav", false, -100, 30)` returns `1` and sends `"SOUND\t1\t/p.wav\t0\t-100\t30\n"`; `M.prompt_text("t", "c", "d")` sends `"PROMPT_TEXT\t1\tt\tc\td\n"`; pushing `"KEY\tDOWN\tshift+H\n"` then `M.poll()` makes `M.held_keys()` equal `{H = true, shift = true}`; pushing `"REPLY\t1\tOK\tBlue\n"` then `M.poll()` makes `M.take_reply(1)` equal `{ok = true, values = {"Blue"}}` and a second call return `nil`; `M.read8(0xC000)`, `M.read16`, `M.read_range(0xC000, 2)`, `M.rom_read8(0x134)` read the fake bus and ROM; with `key_events = true`, `M.has_key_events` and `M.key_source == "lua"`, and `fake:fire("key", {key = 72, state = 1, modifiers = 3})` yields held `{H = true, shift = true}`; with `lib.refuse = true`, `M.connected() == false` and `M.speak("x")` plus `M.end_frame()` records an `os.execute` string containing `/usr/bin/say -- 'x'`.
- [ ] **Step 3: Run**. Expected: FAIL.
- [ ] **Step 4: Implement `platform/mgba.lua`**, then `platform/vba.lua`.
- [ ] **Step 5: Run `tests/lua/run.sh` and `/opt/homebrew/opt/lua@5.4/bin/luac5.4 -p platform/vba.lua`**. Expected: all `ok`, no parse errors.
- [ ] **Step 6: Commit** `Add the mGBA platform layer and a VBA counterpart`.

### Task 8: Runner, entry script and the first run inside mGBA

**Files:**
- Create: `platform/runner.lua`, `pokemon-access.lua`
- Create: `tools/dev/fake_helper.py`, `tools/dev/run_in_mgba.sh`
- Test: `tests/lua/test_runner.lua`

**Interfaces:**
- Produces: `Runner.new(platform, api, chunk) -> runner`; `runner:frame()` (starts lazily on the first frame, so the ROM is running); `runner:reset()`; `runner:shutdown()`; `runner.alive`.
- `frame()`: return if shut down; `platform.poll()`; if a reset is pending: when not alive, start again, else `pcall(api.reset_handler)`; `api.poll_exec()`; resume the coroutine; on error log `"script error: " .. err .. "\n" .. debug.traceback(co)`, speak `Pokemon Access script error. See the log.` once, set `alive = false`; finally `platform.end_frame()`.
- `pokemon-access.lua`: derives `script_dir` from `debug.getinfo(1, "S").source`, prepends `script_dir .. "?.lua"` to `package.path`, calls `os.setlocale("C", "numeric")`, requires `platform.mgba`, `compat.vba_api`, `platform.runner`, shuts down a previous `_G.pokemon_access_runner`, `M.setup{}`, `api = compat.install(M)`, creates the runner with `function() dofile(script_dir .. "pokemon.lua") end`, registers `on_frame` and `on_reset`, `M.send_hello(_VERSION)`, logs `pokemon-access loaded, key source = <source>`.
- `tools/dev/fake_helper.py --port N --log FILE [--send LINE --after SECONDS]... [--reply-ok VALUE]`: one client at a time; writes each received line with a timestamp to the log (escaped as received); answers `HELLO` with `WELCOME\t0.0-dev\thelper`; sends each `--send` line (with `\t` sequences expanded) `--after` seconds after `HELLO`; answers every `PROMPT_*` with `REPLY\t<id>\tOK\t<VALUE>` when `--reply-ok` is given.
- `tools/dev/run_in_mgba.sh ROM [--duration S] [fake_helper args...]`: port 48890, a scratch directory under the session scratchpad with `xdg/` and `data/`; refuses to run when mGBA is already running; launches `/Applications/mGBA.app/Contents/MacOS/mGBA ROM` with `XDG_CONFIG_HOME` and `POKEMON_ACCESS_PORT`, cwd `data/`; loads `pokemon-access.lua` with `tools/mgba-probe/load_script.applescript` and `dofile([==[<abs path>]==])`; waits up to 30 s for `HELLO` in the log; sleeps `--duration` (default 15); quits mGBA; prints the log.

- [ ] **Step 1: Write `tests/lua/test_runner.lua`** with the fake platform and `compat.install`: chunk `memory.registerexec(0x100, function() tolk.output("Ready") end); frames = 0; while true do emu.frameadvance(); frames = frames + 1; if frames == 3 then error("boom") end end`. Assertions: after two `frame()` calls `frames == 2` and `runner.alive`; the third call records `{"speak", "Pokemon Access script error. See the log."}` once and a log call containing `boom`, `alive == false`; two more `frame()` calls add no speak calls; `reset()` then `frame()` restarts (`alive == true`, `frames == 0`); `reset()` while alive then `frame()` records `{"speak", "Ready"}`; `shutdown()` then `frame()` changes nothing.
- [ ] **Step 2: Run**. Expected: FAIL.
- [ ] **Step 3: Implement `platform/runner.lua`**.
- [ ] **Step 4: Run `tests/lua/run.sh`**. Expected: all `ok`.
- [ ] **Step 5: Write `pokemon-access.lua`, `tools/dev/fake_helper.py`, `tools/dev/run_in_mgba.sh`**.
- [ ] **Step 6: Run** `tools/dev/run_in_mgba.sh <scratch>/probe.gb --send 'KEY\tDOWN\tT' --send 'KEY\tUP\tT' --after 6` (generate the ROM with `tools/mgba-probe/make_test_rom.py` first). Expected in the log, in order: `HELLO\t1\thelper\tLua 5.4`, `SPEAK\t0\tGame not supported.`, then after the key `SPEAK\t1\tScript not loaded.`.
- [ ] **Step 7: Commit** `Run upstream pokemon.lua inside mGBA through a frame-driven coroutine`.

### Task 9: Swift package and the core types

**Files:**
- Create: `helper/Package.swift`
- Create: `helper/Sources/PokemonAccessCore/LineProtocol.swift`, `LineBuffer.swift`, `KeySource.swift`, `LuaMessage.swift`, `HelperMessage.swift`, `HotkeyChord.swift`, `HotkeyTable.swift`, `RomHeader.swift`, `KnownGame.swift`, `MgbaConfig.swift`, `LaunchOptions.swift`
- Create: `helper/Sources/PokemonAccess/main.swift` (prints the version for now)
- Test: `helper/Tests/PokemonAccessCoreTests/LineProtocolTests.swift`, `LineBufferTests.swift`, `LuaMessageTests.swift`, `HelperMessageTests.swift`, `HotkeyTableTests.swift`, `RomHeaderTests.swift`, `MgbaConfigTests.swift`, `LaunchOptionsTests.swift`

**Interfaces:**
- `Package.swift`: tools version 5.10, `platforms: [.macOS(.v14)]`, library `PokemonAccessCore`, executable `PokemonAccess` depending on it, test target; `swiftLanguageVersions: [.v5]`.
- `enum LineProtocol { static func escape(_ s: String) -> String; static func unescape(_ s: String) -> String; static func encode(_ fields: [String]) -> String; static func decode(_ line: String) -> [String] }`.
- `struct LineBuffer { mutating func feed(_ data: Data) -> [String] }` (UTF-8, strips one trailing `\r`).
- `enum KeySource: String { case helper, lua }`.
- `enum LuaMessage: Equatable { case hello(protocolVersion: Int, keySource: KeySource, info: String); case speak(interrupt: Bool, text: String); case silence; case sound(id: Int, path: String, loop: Bool, pan: Int, volume: Int); case soundStop(id: Int); case soundPitch(id: Int, value: Double); case promptText(id: Int, title: String, caption: String, defaultValue: String); case promptChoice(id: Int, title: String, caption: String, multi: Bool, defaults: [Int], items: [String]); case log(level: String, text: String); static func parse(_ fields: [String]) throws -> LuaMessage }` with `enum LuaMessageError: Error, Equatable { case empty; case unknownType(String); case malformed(String) }`. Wire format: `PROMPT_CHOICE <id> <title> <caption> <multi 0|1> <defaults comma-separated> <item>...`.
- `enum HelperMessage { case welcome(version: String, keySource: KeySource); case key(down: Bool, chord: String); case reply(id: Int, ok: Bool, values: [String]); var line: String }`.
- `struct HotkeyChord: Hashable { let key: Character; let shift: Bool; var name: String }` (`"shift+H"`, `"T"`); `enum HotkeyTable { static let all: [HotkeyChord] }` listing the 15 letters `Y J K L P T M E D G R V F C H` plain and with shift, plus `shift+0` (31 chords, from `pokemon.lua:824-853`).
- `struct RomHeader { let title: String; let globalChecksum: UInt16; let cartridgeType: UInt8; init?(data: Data); var knownGame: KnownGame? }`; title is bytes `0x134..<0x144` up to the first byte that is `0x00`, `0x80` or `0xC0`, trimmed; `enum KnownGame: Equatable { case red(language: String), blue(language: String), yellow(language: String); var displayName: String }` from the checksum table in `gb.lua:10-28`.
- `struct MgbaConfig { var volume: Int = 128; var ini: String }` rendering `[ports.qt]` with `showFps=0`, `showOSD=0`, `volume=<volume>`, `pauseOnFocusLost=0`, `pauseOnMinimize=0`, `fullscreen=0`, `width=480`, `height=320`, and `[gba.input.QT_K]` with the default bindings recorded in Phase 1 (`keyA=88`, `keyB=90`, `keyL=65`, `keyR=83`, `keyStart=16777220`, `keySelect=16777219`, `keyUp=16777235`, `keyDown=16777237`, `keyLeft=16777234`, `keyRight=16777236`).
- `struct LaunchOptions { var rom: URL?; var noLaunch = false; var port: UInt16?; var hotkeysAlways = false; var quitAfter: TimeInterval?; var luaRoot: URL?; var mgbaApp: URL?; var probeMgba = false; static func parse(_ arguments: [String]) -> LaunchOptions }` for `--rom PATH`, `--no-launch`, `--port N`, `--hotkeys-always`, `--quit-after SECONDS`, `--lua-root PATH`, `--mgba PATH`, `--probe-mgba`; a bare path argument ending in `.gb` or `.gbc` is the ROM.

- [ ] **Step 1: Write `Package.swift`, empty source files with the type names above, and the tests** using the values: `encode(["SPEAK", "1", "a\tb\nc\\d"]) == "SPEAK\t1\ta\\tb\\nc\\\\d\n"`; `decode("KEY\tDOWN\tshift+H") == ["KEY", "DOWN", "shift+H"]`; `decode(encode(["X", "Pokémon\tRouge"])) == ["X", "Pokémon\tRouge"]`; buffer feeds `"HEL"`, `"LO\t1\nKEY\tDOWN\tT\nPAR"`, `"T\r\n"` give `[]`, `["HELLO\t1", "KEY\tDOWN\tT"]`, `["PART"]`; `LuaMessage.parse(["HELLO", "1", "helper", "Lua 5.4"]) == .hello(protocolVersion: 1, keySource: .helper, info: "Lua 5.4")`; `["SPEAK", "1", "hi"]` gives `.speak(interrupt: true, text: "hi")`; `["SOUND", "3", "/p.wav", "0", "-100", "30"]` gives `.sound(id: 3, path: "/p.wav", loop: false, pan: -100, volume: 30)`; `["PROMPT_CHOICE", "2", "T", "C", "1", "1,3", "a", "b", "c"]` gives the matching `promptChoice`; `["BOGUS"]` throws `.unknownType("BOGUS")`; `["SPEAK"]` throws `.malformed`; `HelperMessage.key(down: true, chord: "shift+H").line == "KEY\tDOWN\tshift+H\n"`; `.reply(id: 7, ok: false, values: []).line == "REPLY\t7\tCANCEL\n"`; `.welcome(version: "0.1.0", keySource: .helper).line == "WELCOME\t0.1.0\thelper\n"`; `HotkeyTable.all.count == 31`, contains `HotkeyChord(key: "0", shift: true)`, `Set(all).count == 31`, `HotkeyChord(key: "H", shift: true).name == "shift+H"`; `RomHeader` from a 0x150-byte buffer with `POKEMON RED` at 0x134 followed by `0x00` and `0x80`, bytes `0x91 0xE6` at 0x14E has `title == "POKEMON RED"`, `globalChecksum == 0x91e6`, `knownGame == .red(language: "en")`; a 0x100-byte buffer gives `nil`; checksum `0x1234` gives `knownGame == nil`; `MgbaConfig(volume: 128).ini` contains `[ports.qt]`, `showFps=0`, `volume=128`, `pauseOnFocusLost=0`, `keyA=88`, `keyStart=16777220`; `LaunchOptions.parse(["x", "--no-launch", "--port", "48891", "--rom", "/r/a b.gb"])` has `noLaunch`, `port == 48891`, `rom?.path == "/r/a b.gb"`.
- [ ] **Step 2: Run `swift test --package-path helper`**. Expected: compile errors or failures for every unimplemented type.
- [ ] **Step 3: Implement the Core types**.
- [ ] **Step 4: Run `swift test --package-path helper`**. Expected: all tests pass.
- [ ] **Step 5: Commit** `Add the Swift helper package with the protocol and ROM header types`.

### Task 10: Speech engines, logging and the TCP server

**Files:**
- Create: `helper/Sources/PokemonAccess/Support/AppPaths.swift`, `Support/FileLog.swift`, `Support/Preferences.swift`, `Support/AppVersion.swift`
- Create: `helper/Sources/PokemonAccess/Speech/SpeechEngine.swift`, `Speech/VoiceOverSpeech.swift`, `Speech/AVSpeech.swift`, `Speech/SaySpeech.swift`, `Speech/SpeechRouter.swift`
- Create: `helper/Sources/PokemonAccess/Server/HelperServer.swift`, `Server/ClientConnection.swift`
- Create: `helper/Sources/PokemonAccess/Session/MessageHandler.swift`
- Modify: `helper/Sources/PokemonAccess/main.swift` (dev mode `--no-launch`)
- Create: `tools/dev/vo_output_semantics.swift`

**Interfaces:**
- `enum AppPaths { static var dataDirectory: URL /* ~/Library/Application Support/Pokemon Access */; static var romsDirectory: URL /* dataDirectory/ROMs */; static var mgbaConfigHome: URL /* dataDirectory/config, mGBA appends mgba/ */; static var logDirectory: URL /* ~/Library/Logs/Pokemon Access */; static var logFile: URL /* logDirectory/pokemon-access.log */; static func luaRoot(override: URL?) -> URL /* override, else Preferences.luaRoot, else Bundle.main.resourceURL/lua */; static func ensureDirectories() throws }`.
- `final class FileLog { static let shared: FileLog; func start(previousKept: Bool); func info(_ s: String); func error(_ s: String) }` writing `yyyy-MM-dd HH:mm:ss.SSS level message` lines; `start` renames the existing file to `pokemon-access.previous.log`.
- `enum AppVersion { static let current: String }` from `CFBundleShortVersionString`, else `0.0-dev`.
- `final class Preferences { static let shared: Preferences; var speechEngine: String /* "auto" */; var voiceIdentifier: String?; var speechRate: Float?; var soundGain: Double /* 1.0 */; var romPath: String?; var luaRoot: String?; var mgbaVolume: Int /* 128 */ }` over `UserDefaults.standard`.
- `protocol SpeechEngine: AnyObject { var name: String { get }; func speak(_ text: String, interrupt: Bool) throws; func silence() }`.
- `VoiceOverSpeech`: `init?()` returns `nil` unless `NSWorkspace.shared.isVoiceOverEnabled`; compiles once `on speakText(t)\n tell application "VoiceOver" to output t\nend speakText`; `speak` calls the handler on the main thread through `executeAppleEvent`; throws `SpeechError.voiceOverRefused(code)` on any AppleScript error (`-1743` is the Automation permission denial).
- `AVSpeech`: `AVSpeechSynthesizer`; `interrupt` stops at `.immediate` first; voice from `Preferences.voiceIdentifier`, rate from `Preferences.speechRate`.
- `SaySpeech`: `/usr/bin/say` processes; `interrupt` terminates the running process.
- `SpeechRouter: SpeechEngine`: order from `Preferences.speechEngine` (`auto` = VoiceOver, AVSpeech, say; or the named engine first); on a thrown error logs it, drops to the next engine for the rest of the session, and speaks `VoiceOver did not accept speech from Pokemon Access. Using the system voice instead.` through the next engine when VoiceOver was the one that failed.
- `final class HelperServer { init(port: UInt16); func start() throws -> UInt16; var onMessage: ((LuaMessage) -> Void)?; var onConnect: (() -> Void)?; var onDisconnect: (() -> Void)?; func send(_ message: HelperMessage); func stop() }` using `NWListener` bound to `127.0.0.1`, one active `ClientConnection` (a new client replaces the old one), lines parsed with `LineBuffer`, parse errors logged and skipped.
- `final class MessageHandler { init(speech: SpeechEngine, log: FileLog); func handle(_ message: LuaMessage, reply: (HelperMessage) -> Void) }`: `.hello` -> log `hello from script: ...` and reply `.welcome(version: AppVersion.current, keySource:)`; `.speak` -> `speech.speak`, log `speak via <engine>: <text>`; `.silence` -> `speech.silence()`; `.log` -> log `lua <level>: <text>`; others log `unhandled` until later tasks.
- Dev mode in `main.swift`: `--no-launch [--port N]` starts the server and speech only, prints `listening on <port>`, runs the AppKit run loop.

- [ ] **Step 1: Write `tools/dev/vo_output_semantics.swift`**: polls `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default output device every 0.25 s for 12 s after issuing `output` of a 120-word paragraph followed 0.5 s later by `output "bravo"` through `osascript`; prints a timeline. Run it with `swift tools/dev/vo_output_semantics.swift` while nothing else plays audio. Interpretation: audio stops within 3 s = `output` interrupts; audio continues past 8 s = `output` queues. Record the result in `PORTING.md` section 5 (one sentence) in Task 16.
- [ ] **Step 2: Implement the support, speech and server files and the dev mode.** Run `swift build --package-path helper`. Expected: builds.
- [ ] **Step 3: Verify the server and speech** with the debug binary: `helper/.build/debug/PokemonAccess --no-launch --port 48891 &` then `printf 'HELLO\t1\thelper\tdev\nSPEAK\t0\tHello from the Pokemon Access test\nLOG\tinfo\tping\n' | nc -w 2 127.0.0.1 48891`. Expected: `nc` prints `WELCOME\t<version>\thelper`; the log file contains `hello from script`, `speak via voiceover: Hello from the Pokemon Access test` (or `avspeech` when VoiceOver is off), and `lua info: ping`.
- [ ] **Step 4: Commit** `Add speech engines, file logging and the helper TCP server`.

### Task 11: Sound cues

**Files:**
- Create: `helper/Sources/PokemonAccess/Sound/SoundPlayer.swift`
- Modify: `helper/Sources/PokemonAccess/Session/MessageHandler.swift`

**Interfaces:**
- `final class SoundPlayer: NSObject, AVAudioPlayerDelegate { init(root: URL, gain: Double); func play(id: Int, path: String, loop: Bool, pan: Int, volume: Int); func stop(id: Int); func setPitch(id: Int, value: Double) }`: preloads every `.wav` under `root/sounds` into `[String: Data]` keyed by standardized absolute path; `play` rejects (logs `rejected sound path`) any path that does not resolve inside `root`; creates `AVAudioPlayer(data:)`, `pan = clamp(pan, -100, 100) / 100`, `volume = clamp(volume, 0, 100) / 100 * gain`, `numberOfLoops = loop ? -1 : 0`, `enableRate = true`; keeps players in `[Int: AVAudioPlayer]` until `audioPlayerDidFinishPlaying`; `setPitch` sets `rate` (the GBA path uses it later).
- `MessageHandler` gains `init(speech:, sounds: SoundPlayer, log:)` and routes `.sound`, `.soundStop`, `.soundPitch`.

- [ ] **Step 1: Implement and build.**
- [ ] **Step 2: Verify** in dev mode with the repository as Lua root (`--lua-root <repo>`): `printf 'SOUND\t1\t<repo>/sounds/common/pass.wav\t0\t-50\t50\nSOUND\t2\t/etc/hosts\t0\t0\t50\n' | nc -w 2 127.0.0.1 48891`. Expected log: `sound 1 sounds/common/pass.wav pan -0.5 volume 0.5 playing`, `rejected sound path /etc/hosts`.
- [ ] **Step 3: Commit** `Play the upstream WAV cues with pan and volume`.

### Task 12: Hot keys without the Accessibility permission

**Files:**
- Create: `helper/Sources/PokemonAccessCore/AnsiKeyCodes.swift`
- Create: `helper/Sources/PokemonAccess/Hotkeys/KeyboardLayout.swift`, `Hotkeys/HotkeyMonitor.swift`, `Hotkeys/FrontmostAppWatcher.swift`
- Modify: `helper/Sources/PokemonAccess/main.swift` (dev flag `--hotkeys-always`)
- Test: `helper/Tests/PokemonAccessCoreTests/AnsiKeyCodesTests.swift`

**Interfaces:**
- `enum AnsiKeyCodes { static func keyCode(for character: Character) -> UInt16? }` for `A`..`Z` and `0`..`9` (`T` = 0x11, `H` = 0x04, `0` = 0x1D).
- `struct KeyboardLayout { static func current() -> KeyboardLayout; func keyCode(for character: Character) -> UInt16? }`: builds the map with `TISCopyCurrentKeyboardLayoutInputSource` and `UCKeyTranslate` over key codes 0..<128 with no modifiers; falls back to `AnsiKeyCodes` for characters the layout does not produce.
- `final class HotkeyMonitor { init(chords: [HotkeyChord], layout: KeyboardLayout, onEvent: @escaping (HotkeyChord, Bool) -> Void); func enable() throws; func disable(); var isEnabled: Bool }`: one `InstallEventHandler` on `GetApplicationEventTarget()` for `kEventHotKeyPressed` and `kEventHotKeyReleased`; `RegisterEventHotKey(keyCode, shift ? UInt32(shiftKey) : 0, EventHotKeyID(signature: "PKAC", id: index + 1), target, 0, &ref)` per chord; `UnregisterEventHotKey` on `disable`.
- `final class FrontmostAppWatcher { init(bundleIdentifier: String, onChange: @escaping (Bool) -> Void) }`: reports the initial state and every `NSWorkspace.didActivateApplicationNotification` change.
- Dev flag `--hotkeys-always`: enable the monitor at start regardless of the frontmost app and send `.key` to the connected client; log `KEY DOWN <chord>` / `KEY UP <chord>`.

- [ ] **Step 1: Write `AnsiKeyCodesTests`** (`keyCode(for: "T") == 0x11`, `"H" == 0x04`, `"0" == 0x1D`, `"é" == nil`). Run `swift test`. Expected: FAIL.
- [ ] **Step 2: Implement all four files and the dev flag.** Run `swift test`. Expected: PASS.
- [ ] **Step 3: Verify** with the screen unlocked: `helper/.build/debug/PokemonAccess --no-launch --port 48892 --hotkeys-always &`, `nc 127.0.0.1 48892 > /tmp/keys.txt &`, then `osascript -e 'tell application "System Events" to keystroke "t"' -e 'tell application "System Events" to keystroke "h" using shift down'`. Expected in `/tmp/keys.txt`: `KEY\tDOWN\tT`, `KEY\tUP\tT`, `KEY\tDOWN\tshift+H`, `KEY\tUP\tshift+H`.
- [ ] **Step 4: Commit** `Capture the upstream hotkeys with Carbon hot keys while mGBA is frontmost`.

### Task 13a: Finding, configuring and launching mGBA

**Files:**
- Create: `helper/Sources/PokemonAccess/Mgba/MgbaInstallation.swift`, `Mgba/MgbaLauncher.swift`, `Mgba/MgbaConfigWriter.swift`

**Interfaces:**
- `struct MgbaInstallation { let bundleURL: URL; var executableURL: URL /* Contents/MacOS/mGBA */; var version: String /* CFBundleShortVersionString */; static func find(override: URL?) -> MgbaInstallation? }` using `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.endrift.mgba-qt")` then `/Applications/mGBA.app`.
- `final class MgbaLauncher { init(installation: MgbaInstallation); func supportsScriptOption() -> Bool /* runs mGBA --help with a 10 s timeout and looks for "--script" */; func launch(rom: URL, script: URL?, environment: [String: String], workingDirectory: URL, onExit: @escaping (Int32) -> Void) throws -> Process; func terminate() }`.
- `enum MgbaConfigWriter { static func ensure(configHome: URL, config: MgbaConfig) throws -> URL /* writes configHome/mgba/config.ini only when missing */ }`.

- [ ] **Step 1: Implement and build.**
- [ ] **Step 2: Verify** with `helper/.build/debug/PokemonAccess --probe-mgba`: prints `found /Applications/mGBA.app version 0.10.5 script option: false`.
- [ ] **Step 3: Commit** `Locate, configure and launch mGBA from the helper`.

### Task 13b: Accessibility permission and script injection on 0.10.5

**Files:**
- Create: `helper/Sources/PokemonAccessCore/InjectionSnippet.swift`
- Create: `helper/Sources/PokemonAccess/Mgba/AccessibilityPermission.swift`, `Mgba/ScriptInjector.swift`
- Test: `helper/Tests/PokemonAccessCoreTests/InjectionSnippetTests.swift`

**Interfaces:**
- `enum InjectionSnippet { static func dofile(path: String) -> String }` returning `dofile([==[<path>]==])` (long brackets, so spaces and quotes in the path need no escaping).
- `enum AccessibilityPermission { static var isTrusted: Bool; static func prompt(); static func waitUntilTrusted(timeout: TimeInterval) async -> Bool /* polls every second */ }`.
- `final class ScriptInjector { init(pid: pid_t); func load(script: URL, timeout: TimeInterval) throws }` with `enum InjectionError: Error { case noWindow, noScriptingMenu, noScriptingWindow, noPrompt, noRunButton, setValueFailed(AXError) }`. Sequence: wait for `kAXWindowsAttribute` to be non-empty; menu bar -> item titled `Tools` -> its menu -> item whose title starts with `Scripting` -> `kAXPressAction`; wait for a window titled `Scripting`; depth-first search for the first `AXTextField` and the `AXButton` titled `Run`; set `kAXValueAttribute` to the snippet; press `Run`; press the Scripting window's `kAXCloseButtonAttribute`; `kAXRaiseAction` on the first remaining window.

- [ ] **Step 1: Write `InjectionSnippetTests`**: `dofile(path: "/Users/x/Pokemon Access/lua/pokemon-access.lua") == "dofile([==[/Users/x/Pokemon Access/lua/pokemon-access.lua]==])"`. Run `swift test`. Expected: FAIL.
- [ ] **Step 2: Implement.** Run `swift test`. Expected: PASS; `swift build` succeeds.
- [ ] **Step 3: Commit** `Load the entry script into mGBA 0.10.5 through the Accessibility API`.

### Task 13c: Choosing the ROM

**Files:**
- Create: `helper/Sources/PokemonAccessCore/RomCandidates.swift`
- Create: `helper/Sources/PokemonAccess/Rom/RomLocator.swift`
- Test: `helper/Tests/PokemonAccessCoreTests/RomCandidatesTests.swift`

**Interfaces:**
- `enum RomCandidates { static func filter(fileNames: [String]) -> [String] }` keeps `.gb` and `.gbc` (case-insensitive), sorted by localized name.
- `@MainActor final class RomLocator { init(romsDirectory: URL, preferences: Preferences); func resolve(opened: URL?) -> URL? }`: an opened URL wins and is remembered in `Preferences.romPath`; else the remembered path if it still exists; else the ROMs directory: one candidate is used, several are offered in an `NSAlert` with an `NSPopUpButton` accessory (title `Choose a ROM`), none opens an `NSOpenPanel` (message `Choose your Pokémon Red or Blue ROM`, allowed extensions `gb`, `gbc`); a chosen file is remembered; cancel returns `nil`.
- `RomLocator.describe(_ url: URL) -> (header: RomHeader?, warning: String?)`: warning `This ROM is not a known Pokémon Red or Blue dump. Starting anyway.` when the header parses but `knownGame` is `nil`, `This file is not a Game Boy ROM.` when it does not parse.

- [ ] **Step 1: Write `RomCandidatesTests`**: `filter(["b.GB", "a.gbc", "notes.txt", "c.gba"]) == ["a.gbc", "b.GB"]`. Run. Expected: FAIL.
- [ ] **Step 2: Implement.** Run `swift test`. Expected: PASS.
- [ ] **Step 3: Commit** `Find the player's ROM in the ROMs folder or ask with the open panel`.

### Task 13d: Session, status window, app bundle

**Files:**
- Create: `helper/Sources/PokemonAccess/App/AppDelegate.swift`, `App/StatusWindowController.swift`, `App/MainMenu.swift`
- Create: `helper/Sources/PokemonAccess/Session/Session.swift`, `Session/SessionError.swift`
- Create: `helper/Resources/Info.plist`
- Create: `scripts/build-app.sh`
- Modify: `helper/Sources/PokemonAccess/main.swift`

**Interfaces:**
- `StatusWindowController`: window titled `Pokemon Access` with a wrapping `NSTextField` (accessibility label `Status`) and a default `Quit` button; `func show(status: String)`.
- `MainMenu.build() -> NSMenu` with the application menu and `Quit Pokemon Access` (Cmd+Q).
- `enum SessionError: LocalizedError { case mgbaMissing, romMissing, accessibilityDenied, scriptNotStarted, mgbaFailed(Int32) }` with the spoken copy: `mGBA is not installed. Install it with Homebrew: brew install --cask mgba-app. Then open Pokemon Access again.`; `No ROM chosen. Pokemon Access will quit.`; `Pokemon Access needs the Accessibility permission to load its script into mGBA. In System Settings, Privacy and Security, Accessibility, turn on Pokemon Access, then come back to this window.`; `The script did not start inside mGBA. The log is in the Logs folder of your Library folder, under Pokemon Access.`; `mGBA stopped unexpectedly.`
- `@MainActor final class Session { init(options: LaunchOptions, status: StatusWindowController, speech: SpeechEngine, log: FileLog); func start() async; var openedRom: URL? }`. Order: `AppPaths.ensureDirectories()`; find mGBA; resolve ROM (warning spoken when `describe` returns one); `mode = launcher.supportsScriptOption() ? .script : .inject`; for `.inject`, if not trusted: speak the permission copy, `prompt()`, `waitUntilTrusted(timeout: 600)`, then speak `Thank you. Starting mGBA.`; write the config; start `HelperServer` on `options.port ?? 0`; launch mGBA with environment `XDG_CONFIG_HOME`, `POKEMON_ACCESS_PORT`, `POKEMON_ACCESS_LOG`, working directory `AppPaths.dataDirectory`, `--script <entry>` in `.script` mode; in `.inject` mode run `ScriptInjector.load` (timeout 30 s); wait up to 30 s for `.hello`; on success status `Connected to the script. Switch to mGBA to play.`, enable hot keys when `keySource == .helper` and mGBA is frontmost; on mGBA exit speak `mGBA closed. Pokemon Access will quit.` and terminate the app; every `SessionError` is spoken, shown in the status window and logged.
- `Info.plist`: `CFBundleIdentifier com.abstractsingleton.pokemon-access`, `CFBundleName Pokemon Access`, `CFBundleExecutable PokemonAccess`, `CFBundleShortVersionString @VERSION@`, `CFBundlePackageType APPL`, `LSMinimumSystemVersion 14.0`, `NSPrincipalClass NSApplication`, `NSHighResolutionCapable true`, `NSAppleEventsUsageDescription Pokemon Access sends the game text to VoiceOver so it is spoken with your VoiceOver voice.`, `CFBundleDocumentTypes` for extensions `gb` and `gbc` (role Viewer).
- `scripts/build-app.sh [--install]`: `swift build -c release --package-path helper`; assemble `build/Pokemon Access.app` (`Contents/MacOS/PokemonAccess`, `Contents/Info.plist` with `@VERSION@` replaced by `git describe --always --dirty`, `Contents/PkgInfo`, `Contents/Resources/lua/` holding `pokemon-access.lua pokemon.lua gb.lua gba.lua a-star.lua serpent.lua message.lua compat platform game message sounds`); `codesign --force --sign - --identifier com.abstractsingleton.pokemon-access --requirements '=designated => identifier "com.abstractsingleton.pokemon-access"'`; `--install` replaces `~/Applications/Pokemon Access.app` with `ditto`.
- `main.swift`: parse `LaunchOptions`, start `FileLog`, build `NSApplication` with `AppDelegate`, menu and status window; `--no-launch` keeps the dev behaviour; `--quit-after` terminates after the delay.

- [ ] **Step 1: Implement all files.** Run `swift build --package-path helper` and `scripts/build-app.sh`. Expected: `build/Pokemon Access.app` exists, `codesign -dr - "build/Pokemon Access.app"` prints `designated => identifier "com.abstractsingleton.pokemon-access"`.
- [ ] **Step 2: Commit** `Add the Pokemon Access application: session flow, status window and bundle script`.

### Task 14: End-to-end smoke test with the generated ROM

**Files:**
- Create: `scripts/smoke-test.sh`

**Interfaces:**
- `scripts/smoke-test.sh`: refuses when mGBA runs; builds the app; generates `<scratch>/probe.gb` with `tools/mgba-probe/make_test_rom.py` when missing; runs `"build/Pokemon Access.app/Contents/MacOS/PokemonAccess" --rom <probe.gb> --quit-after 40 --lua-root <repo>` with `POKEMON_ACCESS_LOG=<scratch>/smoke.log` and `XDG_CONFIG_HOME` left to the app (the app sets it for mGBA); waits for exit; greps the log for `mGBA started`, `script loaded`, `hello from script`, `speak via`, `Game not supported.`; exits 0 only when all are present and prints the log otherwise.
- Running the executable from the shell makes this session's parent the responsible process for TCC, so the Accessibility calls work unattended; a Finder launch needs the one-time grant handled by the Session.

- [ ] **Step 1: Write the script and run it.** Expected: `smoke test passed` and the five log lines present.
- [ ] **Step 2: Fix whatever the run exposes (Lua 5.4 runtime errors in upstream code are recorded in PORTING.md 6.4 when a patch is needed).**
- [ ] **Step 3: Commit** `Add an end-to-end smoke test that drives mGBA with the generated ROM`.

### Task 15: Rename prompts (Phase 3 step 9)

**Files:**
- Create: `helper/Sources/PokemonAccess/Prompts/PromptPresenter.swift`
- Modify: `helper/Sources/PokemonAccess/Session/MessageHandler.swift`

**Interfaces:**
- `@MainActor final class PromptPresenter { func text(id: Int, title: String, caption: String, defaultValue: String, reply: @escaping (HelperMessage) -> Void); func choice(id: Int, title: String, caption: String, multi: Bool, defaults: [Int], items: [String], reply: @escaping (HelperMessage) -> Void) }`: `NSAlert` with `messageText = title`, `informativeText = caption`, an `NSTextField` accessory (accessibility label `Name`) or an `NSTableView` accessory (`allowsMultipleSelection = multi`); buttons `OK` and `Cancel`; the alert is run modally after `NSApp.activate(ignoringOtherApps: true)`; replies `.reply(id:, ok: true, values: [text])` or `[indices as 1-based strings]`, `.reply(id:, ok: false, values: [])` on cancel; afterwards re-activates mGBA (`NSRunningApplication` with bundle id `com.endrift.mgba-qt`).
- `MessageHandler` routes `.promptText` and `.promptChoice` to the presenter.

- [ ] **Step 1: Implement and build.**
- [ ] **Step 2: Verify** in dev mode: `printf 'PROMPT_TEXT\t7\tRename\tNew name\told\n' | nc 127.0.0.1 48891 &` then `osascript -e 'tell application "System Events" to tell process "PokemonAccess" to keystroke "Blue" & return'`. Expected: `nc` prints `REPLY\t7\tOK\tBlue`; a second prompt answered with Escape prints `REPLY\t8\tCANCEL`.
- [ ] **Step 3: Commit** `Show rename prompts as accessible alerts`.

### Task 16: Documentation and spec updates

**Files:**
- Create: `README-macOS.md`
- Modify: `PORTING.md` (section 5: VoiceOver `output` semantics result; section 6: "as built" notes; section 6.4: any patches made; section 7: status per step)

- [ ] **Step 1: Write `README-macOS.md`**: requirements (Apple Silicon, macOS 14+, Xcode command line tools, Homebrew mGBA), install (`brew install --cask mgba-app`, `git clone`, `scripts/build-app.sh --install`), first launch (ROM folder path, Accessibility permission wording, VoiceOver automation prompt), playing (the upstream key list with VoiceOver notes: Quick Nav off, Control stops speech), settings (`defaults write com.abstractsingleton.pokemon-access speechEngine voiceover|avspeech|say`, `voiceIdentifier`, `speechRate`, `soundGain`, `mgbaVolume`), troubleshooting (log path, permission lost after rebuild: remove and re-add in Accessibility, mGBA not found), development (tests: `tests/lua/run.sh`, `swift test --package-path helper`, `scripts/smoke-test.sh`, `tools/dev/run_in_mgba.sh`).
- [ ] **Step 2: Update `PORTING.md`.**
- [ ] **Step 3: Commit** `Document installing and playing Pokemon Access on macOS`.

### Task 17: Game checks with the player's ROM (blocked until the ROM is in the ROMs folder)

**Files:**
- Create: `docs/game-checklist.md`

- [ ] **Step 1: Write the checklist** mapping PORTING.md section 7 steps to concrete actions and the expected log lines: launch speaks `Ready`; `t` speaks the title screen or dialogue text; `m` the map name after leaving the bedroom; `y` the coordinates; `j`/`k`/`l` cycle objects (with `shift` variants filtering); `p` on an object speaks the path; `h` and `shift+h` in the first battle speak enemy and player HP; `d g r v f` camera moves play `pass.wav`/`s_wall.wav` with pan; walking plays tile sounds; `shift+k` opens the rename prompt.
- [ ] **Step 2: Run the checklist** once `~/Library/Application Support/Pokemon Access/ROMs/` holds the Red or Blue ROM, fixing any Lua 5.4 issue found (patches recorded in PORTING.md 6.4), one commit per fix.
