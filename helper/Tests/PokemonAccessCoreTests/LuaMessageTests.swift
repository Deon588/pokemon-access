import XCTest
@testable import PokemonAccessCore

final class LuaMessageTests: XCTestCase {
    func testHello() throws {
        XCTAssertEqual(try LuaMessage.parse(["HELLO", "1", "helper", "Lua 5.4"]),
                       .hello(protocolVersion: 1, keySource: .helper, info: "Lua 5.4", token: nil))
    }

    func testSpeak() throws {
        XCTAssertEqual(try LuaMessage.parse(["SPEAK", "1", "hi"]), .speak(interrupt: true, text: "hi"))
        XCTAssertEqual(try LuaMessage.parse(["SPEAK", "0", "a\nb"]), .speak(interrupt: false, text: "a\nb"))
    }

    func testSilenceAndLog() throws {
        XCTAssertEqual(try LuaMessage.parse(["SILENCE"]), .silence)
        XCTAssertEqual(try LuaMessage.parse(["LOG", "info", "ping"]), .log(level: "info", text: "ping"))
    }

    func testSound() throws {
        XCTAssertEqual(try LuaMessage.parse(["SOUND", "3", "/p.wav", "0", "-100", "30"]),
                       .sound(id: 3, path: "/p.wav", loop: false, pan: -100, volume: 30))
        XCTAssertEqual(try LuaMessage.parse(["SOUND_STOP", "3"]), .soundStop(id: 3))
        XCTAssertEqual(try LuaMessage.parse(["SOUND_PITCH", "3", "1.5"]), .soundPitch(id: 3, value: 1.5))
    }

    func testPrompts() throws {
        XCTAssertEqual(try LuaMessage.parse(["PROMPT_TEXT", "7", "Rename", "New name", "old"]),
                       .promptText(id: 7, title: "Rename", caption: "New name", defaultValue: "old"))
        XCTAssertEqual(try LuaMessage.parse(["PROMPT_CHOICE", "2", "T", "C", "1", "1,3", "a", "b", "c"]),
                       .promptChoice(id: 2, title: "T", caption: "C", multi: true, defaults: [1, 3], items: ["a", "b", "c"]))
    }

    func testErrors() {
        XCTAssertThrowsError(try LuaMessage.parse(["BOGUS"])) { error in
            XCTAssertEqual(error as? LuaMessageError, .unknownType("BOGUS"))
        }
        XCTAssertThrowsError(try LuaMessage.parse(["SPEAK"])) { error in
            XCTAssertEqual(error as? LuaMessageError, .malformed("SPEAK"))
        }
        XCTAssertThrowsError(try LuaMessage.parse([])) { error in
            XCTAssertEqual(error as? LuaMessageError, .empty)
        }
        XCTAssertThrowsError(try LuaMessage.parse(["SOUND", "x", "/p.wav", "0", "0", "0"])) { error in
            XCTAssertEqual(error as? LuaMessageError, .malformed("SOUND"))
        }
    }
}

final class LuaMessageTokenTests: XCTestCase {
    func testHelloCarriesAnOptionalToken() throws {
        XCTAssertEqual(try LuaMessage.parse(["HELLO", "1", "helper", "Lua 5.4", "secret"]),
                       .hello(protocolVersion: 1, keySource: .helper, info: "Lua 5.4", token: "secret"))
        XCTAssertEqual(try LuaMessage.parse(["HELLO", "1", "lua", "Lua 5.4"]),
                       .hello(protocolVersion: 1, keySource: .lua, info: "Lua 5.4", token: nil))
    }
}

final class LuaMessageFractionTests: XCTestCase {
    func testSoundAcceptsFractionalPanAndVolumeByTruncating() throws {
        XCTAssertEqual(try LuaMessage.parse(["SOUND", "1", "/p.wav", "0", "-88.888888888889", "30.5"]),
                       .sound(id: 1, path: "/p.wav", loop: false, pan: -88, volume: 30))
        XCTAssertEqual(try LuaMessage.parse(["SOUND", "2", "/p.wav", "1", "100", "0"]),
                       .sound(id: 2, path: "/p.wav", loop: true, pan: 100, volume: 0))
    }
}

final class LuaMessageRangeTests: XCTestCase {
    func testOutOfRangeNumbersAreMalformedInsteadOfTrapping() {
        for text in ["1e300", "-1e300", "nan", "inf", "99999999999999999999"] {
            XCTAssertThrowsError(try LuaMessage.parse(["SOUND", "1", "/p.wav", "0", text, "0"]), text) { error in
                XCTAssertEqual(error as? LuaMessageError, .malformed("SOUND"))
            }
        }
    }
}
