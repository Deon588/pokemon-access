import XCTest
@testable import PokemonAccessCore

final class RomHeaderTests: XCTestCase {
    private func rom(title: String, padding: [UInt8], checksum: UInt16) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x150)
        let titleBytes = Array(title.utf8) + padding
        for (offset, byte) in titleBytes.enumerated() where offset < 16 {
            bytes[0x134 + offset] = byte
        }
        bytes[0x147] = 0x03
        bytes[0x14E] = UInt8(checksum >> 8)
        bytes[0x14F] = UInt8(checksum & 0xFF)
        return Data(bytes)
    }

    func testParsesRedHeader() {
        let header = RomHeader(data: rom(title: "POKEMON RED", padding: [0x00, 0x80], checksum: 0x91e6))
        XCTAssertEqual(header?.title, "POKEMON RED")
        XCTAssertEqual(header?.globalChecksum, 0x91e6)
        XCTAssertEqual(header?.cartridgeType, 0x03)
        XCTAssertEqual(header?.knownGame, .red(language: "en"))
    }

    func testBlueAndYellow() {
        XCTAssertEqual(RomHeader(data: rom(title: "POKEMON BLUE", padding: [], checksum: 0x9d0a))?.knownGame, .blue(language: "en"))
        XCTAssertEqual(RomHeader(data: rom(title: "POKEMON YELLOW", padding: [0x80], checksum: 0x047c))?.knownGame, .yellow(language: "en"))
        XCTAssertEqual(KnownGame.red(language: "en").displayName, "Pokémon Red (en)")
    }

    func testTooShortIsNil() {
        XCTAssertNil(RomHeader(data: Data(count: 0x100)))
    }

    func testUnknownChecksumHasNoKnownGame() {
        let header = RomHeader(data: rom(title: "PROBE", padding: [], checksum: 0x1234))
        XCTAssertEqual(header?.title, "PROBE")
        XCTAssertNil(header?.knownGame)
    }

    func testDataSliceWithNonZeroStartIndex() {
        let full = Data([0xAA, 0xBB]) + rom(title: "POKEMON RED", padding: [], checksum: 0x91e6)
        let header = RomHeader(data: full.dropFirst(2))
        XCTAssertEqual(header?.title, "POKEMON RED")
    }
}
