import XCTest
@testable import PokemonAccessCore

final class HotkeyTableTests: XCTestCase {
    func testThirtyOneDistinctChords() {
        XCTAssertEqual(HotkeyTable.all.count, 31)
        XCTAssertEqual(Set(HotkeyTable.all).count, 31)
    }

    func testContainsShiftZeroAndPlainLetters() {
        XCTAssertTrue(HotkeyTable.all.contains(HotkeyChord(key: "0", shift: true)))
        XCTAssertTrue(HotkeyTable.all.contains(HotkeyChord(key: "T", shift: false)))
        XCTAssertFalse(HotkeyTable.all.contains(HotkeyChord(key: "0", shift: false)))
    }

    func testNamesUseUpstreamSpelling() {
        XCTAssertEqual(HotkeyChord(key: "H", shift: true).name, "shift+H")
        XCTAssertEqual(HotkeyChord(key: "T", shift: false).name, "T")
        XCTAssertEqual(HotkeyChord(key: "0", shift: true).name, "shift+0")
    }
}
