import XCTest
@testable import PokemonAccessCore

final class RomCandidatesTests: XCTestCase {
    func testKeepsGameBoyRomsSorted() {
        XCTAssertEqual(RomCandidates.filter(fileNames: ["b.GB", "a.gbc", "notes.txt", "c.gba", ".DS_Store"]), ["a.gbc", "b.GB"])
    }

    func testEmpty() {
        XCTAssertEqual(RomCandidates.filter(fileNames: []), [])
    }
}
