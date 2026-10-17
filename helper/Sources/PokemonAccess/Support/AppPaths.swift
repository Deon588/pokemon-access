import Foundation

/// Where the application keeps its files.
enum AppPaths {
    static let appName = "Pokemon Access"

    /// ~/Library/Application Support/Pokemon Access
    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
    }

    /// Where the player drops their ROM.
    static var romsDirectory: URL {
        dataDirectory.appendingPathComponent("ROMs", isDirectory: true)
    }

    /// XDG_CONFIG_HOME for mGBA; mGBA appends "mgba/" itself.
    static var mgbaConfigHome: URL {
        dataDirectory.appendingPathComponent("config", isDirectory: true)
    }

    /// ~/Library/Logs/Pokemon Access
    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(appName)", isDirectory: true)
    }

    /// The log file; POKEMON_ACCESS_LOG overrides it for scripted runs.
    static var logFile: URL {
        if let override = ProcessInfo.processInfo.environment["POKEMON_ACCESS_LOG"] {
            return URL(fileURLWithPath: override)
        }
        return logDirectory.appendingPathComponent("pokemon-access.log")
    }

    /// The directory holding pokemon-access.lua and the upstream scripts: an
    /// explicit override, the luaRoot preference, POKEMON_ACCESS_LUA_ROOT, or
    /// the copy inside the application bundle.
    static func luaRoot(override: URL?) -> URL {
        if let override { return override }
        if let preference = Preferences.shared.luaRoot {
            return URL(fileURLWithPath: preference, isDirectory: true)
        }
        if let environment = ProcessInfo.processInfo.environment["POKEMON_ACCESS_LUA_ROOT"] {
            return URL(fileURLWithPath: environment, isDirectory: true)
        }
        return (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("lua", isDirectory: true)
    }

    static func ensureDirectories() throws {
        for directory in [dataDirectory, romsDirectory, mgbaConfigHome, logDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
