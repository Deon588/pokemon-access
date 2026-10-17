import XCTest
@testable import PokemonAccessCore

final class AnsiKeyCodesTests: XCTestCase {
    func testLettersAndDigitsOfTheAnsiLayout() {
        XCTAssertEqual(AnsiKeyCodes.keyCode(for: "T"), 0x11)
        XCTAssertEqual(AnsiKeyCodes.keyCode(for: "H"), 0x04)
        XCTAssertEqual(AnsiKeyCodes.keyCode(for: "0"), 0x1D)
        XCTAssertEqual(AnsiKeyCodes.keyCode(for: "A"), 0x00)
        XCTAssertEqual(AnsiKeyCodes.keyCode(for: "M"), 0x2E)
    }

    func testLowercaseIsAccepted() {
        XCTAssertEqual(AnsiKeyCodes.keyCode(for: "t"), 0x11)
    }

    func testUnknownCharactersHaveNoCode() {
        XCTAssertNil(AnsiKeyCodes.keyCode(for: "é"))
        XCTAssertNil(AnsiKeyCodes.keyCode(for: "+"))
    }

    func testEveryUpstreamChordHasACode() {
        for chord in HotkeyTable.all {
            XCTAssertNotNil(AnsiKeyCodes.keyCode(for: chord.key), "no key code for \(chord.name)")
        }
    }
}
