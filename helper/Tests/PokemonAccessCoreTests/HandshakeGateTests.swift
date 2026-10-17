import XCTest
@testable import PokemonAccessCore

final class HandshakeGateTests: XCTestCase {
    private let hello = LuaMessage.hello(protocolVersion: 1, keySource: .helper, info: "Lua 5.4", token: "secret")

    func testFirstMessageMustBeHelloWithTheExpectedToken() {
        XCTAssertTrue(HandshakeGate.accepts(first: hello, expectedToken: "secret"))
        XCTAssertFalse(HandshakeGate.accepts(first: hello, expectedToken: "other"))
        XCTAssertFalse(HandshakeGate.accepts(first: .speak(interrupt: false, text: "hi"), expectedToken: "secret"))
    }

    func testWithoutAConfiguredTokenAnyHelloIsAccepted() {
        XCTAssertTrue(HandshakeGate.accepts(first: hello, expectedToken: nil))
        XCTAssertTrue(HandshakeGate.accepts(first: .hello(protocolVersion: 1, keySource: .helper, info: "x", token: nil), expectedToken: nil))
        XCTAssertFalse(HandshakeGate.accepts(first: .silence, expectedToken: nil))
    }

    func testTokensAreRandomAndLongEnough() {
        let first = HandshakeGate.makeToken()
        XCTAssertNotEqual(first, HandshakeGate.makeToken())
        XCTAssertGreaterThanOrEqual(first.count, 32)
        XCTAssertNil(first.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted))
    }
}
