import AppKit

/// Reports whether the application with `bundleIdentifier` is frontmost, now
/// and on every change.
final class FrontmostAppWatcher {
    private var observer: NSObjectProtocol?

    init(bundleIdentifier: String, onChange: @escaping (Bool) -> Void) {
        onChange(NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            onChange(application?.bundleIdentifier == bundleIdentifier)
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
