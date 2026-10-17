import XCTest
@testable import PokemonAccessCore

final class HelperMessageTests: XCTestCase {
    func testLines() {
        XCTAssertEqual(HelperMessage.key(down: true, chord: "shift+H").line, "KEY\tDOWN\tshift+H\n")
        XCTAssertEqual(HelperMessage.key(down: false, chord: "T").line, "KEY\tUP\tT\n")
        XCTAssertEqual(HelperMessage.reply(id: 7, ok: false, values: []).line, "REPLY\t7\tCANCEL\n")
        XCTAssertEqual(HelperMessage.reply(id: 7, ok: true, values: ["Blue"]).line, "REPLY\t7\tOK\tBlue\n")
        XCTAssertEqual(HelperMessage.welcome(version: "0.1.0", keySource: .helper).line, "WELCOME\t0.1.0\thelper\n")
    }

    func testReplyValuesAreEscaped() {
        XCTAssertEqual(HelperMessage.reply(id: 1, ok: true, values: ["a\tb"]).line, "REPLY\t1\tOK\ta\\tb\n")
    }
}
