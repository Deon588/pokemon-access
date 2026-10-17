import XCTest
@testable import PokemonAccessCore

final class LineBufferTests: XCTestCase {
    func testPartialLinesAreHeldUntilComplete() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.feed(Data("HEL".utf8)), [])
        XCTAssertEqual(buffer.feed(Data("LO\t1\nKEY\tDOWN\tT\nPAR".utf8)), ["HELLO\t1", "KEY\tDOWN\tT"])
        XCTAssertEqual(buffer.feed(Data("T\r\n".utf8)), ["PART"])
        XCTAssertEqual(buffer.feed(Data()), [])
    }

    func testUtf8SplitAcrossChunksIsReassembled() {
        var buffer = LineBuffer()
        let bytes = Array("Pokémon\n".utf8)
        XCTAssertEqual(buffer.feed(Data(bytes[0..<4])), [])
        XCTAssertEqual(buffer.feed(Data(bytes[4...])), ["Pokémon"])
    }
}
