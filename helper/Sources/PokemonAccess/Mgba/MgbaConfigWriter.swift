import Foundation
import PokemonAccessCore

/// Writes the private mGBA configuration (config.ini under XDG_CONFIG_HOME/mgba)
/// the first time; later runs keep whatever the player changed in mGBA.
enum MgbaConfigWriter {
    @discardableResult
    static func ensure(configHome: URL, config: MgbaConfig) throws -> URL {
        let directory = configHome.appendingPathComponent("mgba", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("config.ini")
        if !FileManager.default.fileExists(atPath: file.path) {
            try config.ini.write(to: file, atomically: true, encoding: .utf8)
        }
        return file
    }
}
