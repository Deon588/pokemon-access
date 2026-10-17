#!/usr/bin/env python3
"""Generate a tiny 64 KiB Game Boy test ROM for probing mGBA's Lua API.

The ROM contains no game data. It writes known byte values into WRAM and HRAM,
keeps a counter running at 0xC001, and places marker strings in ROM banks 1 to 3
so that linear ROM reads (the VBA-RR memory.gbromreadbyte model) can be checked.

Usage: make_test_rom.py OUTPUT.gb
"""
import sys

BANK = 0x4000
ROM_SIZE = 4 * BANK  # 64 KiB, four banks, MBC1

NINTENDO_LOGO = bytes.fromhex(
    "CEED6666CC0D000B03730083000C000D0008111F8889000EDCCC6EE6DDDDD999"
    "BBBB67636E0EECCCDDDC999FBBB9333E"
)


def code() -> bytes:
    # SM83 assembly, hand assembled.
    program = bytearray()
    program += b"\xF3"                  # di
    program += b"\x31\xFE\xFF"          # ld sp, $FFFE
    program += b"\x3E\x42\xEA\x00\xC0"  # ld a,$42 ; ld [$C000],a
    program += b"\x3E\x37\xEA\x00\xD0"  # ld a,$37 ; ld [$D000],a
    program += b"\x3E\x99\xE0\x80"      # ld a,$99 ; ldh [$FF80],a
    program += b"\x3E\x34\xEA\x10\xC0"  # ld a,$34 ; ld [$C010],a
    program += b"\x3E\x12\xEA\x11\xC0"  # ld a,$12 ; ld [$C011],a   (word 0x1234 at C010)
    loop = 0x150 + len(program)
    program += b"\xFA\x01\xC0"          # ld a,[$C001]
    program += b"\x3C"                  # inc a
    program += b"\xEA\x01\xC0"          # ld [$C001],a
    program += b"\xC3" + loop.to_bytes(2, "little")  # jp loop
    return bytes(program)


def main(path: str) -> None:
    rom = bytearray(ROM_SIZE)
    rom[0x100:0x104] = b"\x00\xC3\x50\x01"  # nop ; jp $0150
    rom[0x104:0x134] = NINTENDO_LOGO
    rom[0x134:0x144] = b"PROBE".ljust(16, b"\x00")
    rom[0x147] = 0x01  # MBC1
    rom[0x148] = 0x01  # 64 KiB
    rom[0x149] = 0x00  # no cartridge RAM
    rom[0x14A] = 0x01  # non-Japanese
    rom[0x14B] = 0x00  # old licensee
    rom[0x14C] = 0x00  # mask ROM version
    checksum = 0
    for b in rom[0x134:0x14D]:
        checksum = (checksum - b - 1) & 0xFF
    rom[0x14D] = checksum
    rom[0x150:0x150 + len(code())] = code()
    # Markers at the same in-bank offset of banks 1, 2 and 3.
    for bank in (1, 2, 3):
        marker = f"PROBE{bank}".encode()
        off = bank * BANK + 0x0100
        rom[off:off + len(marker)] = marker
    total = sum(rom) & 0xFFFF  # global checksum excludes its own two bytes (still zero here)
    rom[0x14E:0x150] = total.to_bytes(2, "big")
    with open(path, "wb") as fh:
        fh.write(rom)
    print(f"wrote {path} ({len(rom)} bytes)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
