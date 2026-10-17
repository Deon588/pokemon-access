import XCTest
@testable import PokemonAccessCore

final class LaunchOptionsTests: XCTestCase {
    func testFlagsAndValues() {
        let options = LaunchOptions.parse(["x", "--no-launch", "--port", "48891", "--rom", "/r/a b.gb", "--quit-after", "2.5", "--hotkeys-always", "--probe-mgba", "--lua-root", "/lua", "--mgba", "/Applications/mGBA.app"])
        XCTAssertTrue(options.noLaunch)
        XCTAssertEqual(options.port, 48891)
        XCTAssertEqual(options.rom?.path, "/r/a b.gb")
        XCTAssertEqual(options.quitAfter, 2.5)
        XCTAssertTrue(options.hotkeysAlways)
        XCTAssertTrue(options.probeMgba)
        XCTAssertEqual(options.luaRoot?.path, "/lua")
        XCTAssertEqual(options.mgbaApp?.path, "/Applications/mGBA.app")
    }

    func testBareRomPathAndUnknownArgumentsAreIgnored() {
        let options = LaunchOptions.parse(["x", "-NSDocumentRevisionsDebugMode", "YES", "/roms/Red.GB"])
        XCTAssertEqual(options.rom?.path, "/roms/Red.GB")
        XCTAssertFalse(options.noLaunch)
        XCTAssertNil(options.port)
    }
}
