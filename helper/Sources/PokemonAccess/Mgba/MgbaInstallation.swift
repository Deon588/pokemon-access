import AppKit
import Foundation

/// The mGBA.app the launcher drives.
struct MgbaInstallation {
    static let bundleIdentifier = "com.endrift.mgba-qt"
    private static let standardLocation = URL(fileURLWithPath: "/Applications/mGBA.app")

    let bundleURL: URL

    var executableURL: URL {
        bundleURL.appendingPathComponent("Contents/MacOS/mGBA")
    }

    var version: String {
        Bundle(url: bundleURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// An explicit override, then /Applications/mGBA.app (what Homebrew installs),
    /// then whatever Launch Services knows under mGBA's bundle identifier.
    static func find(override: URL?) -> MgbaInstallation? {
        if let override {
            return isInstallation(override) ? MgbaInstallation(bundleURL: override) : nil
        }
        if isInstallation(standardLocation) {
            return MgbaInstallation(bundleURL: standardLocation)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier), isInstallation(url) {
            return MgbaInstallation(bundleURL: url)
        }
        return nil
    }

    private static func isInstallation(_ bundleURL: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: bundleURL.appendingPathComponent("Contents/MacOS/mGBA").path)
    }
}
