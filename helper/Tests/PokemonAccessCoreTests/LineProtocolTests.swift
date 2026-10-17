import XCTest
@testable import PokemonAccessCore

final class LineProtocolTests: XCTestCase {
    func testEncodeEscapesTabsNewlinesAndBackslashes() {
        XCTAssertEqual(LineProtocol.encode(["SPEAK", "1", "a\tb\nc\\d"]), "SPEAK\t1\ta\\tb\\nc\\\\d\n")
    }

    func testDecodeSplitsOnTabs() {
        XCTAssertEqual(LineProtocol.decode("KEY\tDOWN\tshift+H"), ["KEY", "DOWN", "shift+H"])
    }

    func testRoundTripKeepsUnicodeAndEscapedCharacters() {
        let fields = ["X", "Pokémon\tRouge", "a\\b", "line\nbreak"]
        XCTAssertEqual(LineProtocol.decode(LineProtocol.encode(fields)), fields)
    }

    func testDecodeDropsTrailingNewlineAndCarriageReturn() {
        XCTAssertEqual(LineProtocol.decode("A\tb\r\n"), ["A", "b"])
    }

    func testUnknownEscapeKeepsTheCharacter() {
        XCTAssertEqual(LineProtocol.unescape("\\q"), "q")
    }

    func testEmptyFieldsSurvive() {
        XCTAssertEqual(LineProtocol.decode("REPLY\t7\tOK\t"), ["REPLY", "7", "OK", ""])
    }
}
