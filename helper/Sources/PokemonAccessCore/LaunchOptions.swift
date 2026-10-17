import Foundation

/// Command line options of the application (also reachable through
/// `open -a "Pokemon Access" --args ...`). Unknown arguments, such as the ones
/// macOS adds, are ignored; a bare path ending in .gb or .gbc is the ROM.
public struct LaunchOptions: Equatable {
    public var rom: URL?
    public var noLaunch = false
    public var port: UInt16?
    public var hotkeysAlways = false
    public var quitAfter: TimeInterval?
    public var luaRoot: URL?
    public var mgbaApp: URL?
    public var probeMgba = false

    public init() {}

    /// `arguments` includes the executable path at index 0.
    public static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        var index = 1
        func value() -> String? {
            index += 1
            return index < arguments.count ? arguments[index] : nil
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--rom":
                if let path = value() { options.rom = URL(fileURLWithPath: path) }
            case "--no-launch":
                options.noLaunch = true
            case "--port":
                if let text = value(), let port = UInt16(text) { options.port = port }
            case "--hotkeys-always":
                options.hotkeysAlways = true
            case "--quit-after":
                if let text = value(), let seconds = TimeInterval(text) { options.quitAfter = seconds }
            case "--lua-root":
                if let path = value() { options.luaRoot = URL(fileURLWithPath: path) }
            case "--mgba":
                if let path = value() { options.mgbaApp = URL(fileURLWithPath: path) }
            case "--probe-mgba":
                options.probeMgba = true
            default:
                let lowered = argument.lowercased()
                if lowered.hasSuffix(".gb") || lowered.hasSuffix(".gbc") {
                    options.rom = URL(fileURLWithPath: argument)
                }
            }
            index += 1
        }
        return options
    }
}
