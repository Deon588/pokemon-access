import XCTest
@testable import PokemonAccessCore

final class MgbaConfigTests: XCTestCase {
    func testIniContainsTheSettingsThatMatterToAScreenReaderUser() {
        let ini = MgbaConfig(volume: 128).ini
        XCTAssertTrue(ini.contains("[ports.qt]"))
        XCTAssertTrue(ini.contains("showFps=0\n"))
        XCTAssertTrue(ini.contains("volume=128\n"))
        XCTAssertTrue(ini.contains("pauseOnFocusLost=0\n"))
        XCTAssertTrue(ini.contains("[gba.input.QT_K]"))
        XCTAssertTrue(ini.contains("keyA=88\n"))
        XCTAssertTrue(ini.contains("keyStart=16777220\n"))
    }

    func testDefaultVolume() {
        XCTAssertEqual(MgbaConfig().volume, 128)
    }
}
