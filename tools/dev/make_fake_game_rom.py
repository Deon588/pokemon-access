#!/usr/bin/env python3
"""Generate a 1 MiB Game Boy ROM that upstream recognises as Pokémon Red or
Blue (English) without containing any game: only the cartridge header, the
checksum bytes upstream keys on, and a tiny program that writes the word
HELLO in the game's character encoding into the text area at 0xC3A0.

Upstream's table readers stop at 0xFF, so the rest of the ROM is 0xFF: every
table comes out empty and the game logic runs on blank data. This exercises
the whole Lua port (data loading, text reading, map and object code) on an
emulator without a copyrighted ROM. It is a development tool, not a game.

Usage: make_fake_game_rom.py OUTPUT.gb [red|blue]
"""
import sys

ROM_SIZE = 0x100000
GLOBAL_CHECKSUMS = {"red": 0x91E6, "blue": 0x9D0A}  # gb.lua oldgame_checksum, English
TITLES = {"red": b"POKEMON RED", "blue": b"POKEMON BLUE"}
NINTENDO_LOGO = bytes.fromhex(
    "CEED6666CC0D000B03730083000C000D0008111F8889000EDCCC6EE6DDDDD999"
    "BBBB67636E0EECCCDDDC999FBBB9333E"
)
# "HELLO" in the Generation 1 text encoding (0x80 is A).
HELLO = [0x87, 0x84, 0x8B, 0x8B, 0x8E]


def code(start: int) -> bytes:
    program = bytearray()
    program += b"\xF3"              # di
    program += b"\x31\xFE\xFF"      # ld sp, $FFFE
    for offset, value in enumerate(HELLO):
        address = 0xC3A0 + offset
        program += b"\x3E" + bytes([value])             # ld a, value
        program += b"\xEA" + address.to_bytes(2, "little")  # ld [address], a
    loop = start + len(program)
    program += b"\xFA\x01\xC0"      # ld a,[$C001]
    program += b"\x3C"              # inc a
    program += b"\xEA\x01\xC0"      # ld [$C001],a
    program += b"\xC3" + loop.to_bytes(2, "little")  # jp loop
    return bytes(program)


def main(path: str, game: str) -> None:
    rom = bytearray(b"\xFF" * ROM_SIZE)
    rom[0x100:0x104] = b"\x00\xC3\x50\x01"  # nop ; jp $0150
    rom[0x104:0x134] = NINTENDO_LOGO
    rom[0x134:0x144] = TITLES[game].ljust(16, b"\x00")
    rom[0x144:0x146] = b"\x00\x00"  # new licensee
    rom[0x146] = 0x00  # no SGB
    rom[0x147] = 0x13  # MBC3 + RAM + battery, like the real cartridge
    rom[0x148] = 0x05  # 1 MiB
    rom[0x149] = 0x03  # 32 KiB cartridge RAM
    rom[0x14A] = 0x01  # non-Japanese
    rom[0x14B] = 0x01  # Nintendo
    rom[0x14C] = 0x00
    checksum = 0
    for b in rom[0x134:0x14D]:
        checksum = (checksum - b - 1) & 0xFF
    rom[0x14D] = checksum
    rom[0x14E:0x150] = GLOBAL_CHECKSUMS[game].to_bytes(2, "big")
    program = code(0x150)
    rom[0x150:0x150 + len(program)] = program
    with open(path, "wb") as fh:
        fh.write(rom)
    print(f"wrote {path} ({len(rom)} bytes, header of Pokémon {game.capitalize()} EN)")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] not in TITLES):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else "red")
