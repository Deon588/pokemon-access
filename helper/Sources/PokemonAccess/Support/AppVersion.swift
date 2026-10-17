import Foundation

enum AppVersion {
    static let current: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0-dev"
}
