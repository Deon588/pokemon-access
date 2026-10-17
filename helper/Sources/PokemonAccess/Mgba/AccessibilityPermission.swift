import ApplicationServices
import Foundation

/// The Accessibility permission, needed only to load the script into
/// mGBA 0.10.5's Scripting window.
enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system dialog that opens the Accessibility settings pane.
    static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Polls once a second until the permission is granted or `timeout` passes.
    static func waitUntilTrusted(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isTrusted { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return isTrusted
    }
}
