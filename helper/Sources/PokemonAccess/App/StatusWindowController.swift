import AppKit

/// The one window of the application: a status text VoiceOver can read and a
/// Quit button. The player spends their time in mGBA; this window is where
/// they come back to when something needs attention.
@MainActor
final class StatusWindowController {
    let window: NSWindow
    private let statusField: NSTextField

    init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 190),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pokemon Access"
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 190))
        statusField = NSTextField(wrappingLabelWithString: "Starting.")
        statusField.frame = NSRect(x: 20, y: 70, width: 440, height: 100)
        statusField.isSelectable = true
        statusField.setAccessibilityLabel("Status")
        content.addSubview(statusField)

        // A plain button on purpose: Return must not end the game session;
        // Command Q quits, and closing this window only hides it.
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.frame = NSRect(x: 370, y: 20, width: 90, height: 32)
        content.addSubview(quit)
        window.contentView = content
    }

    func present() {
        window.makeKeyAndOrderFront(nil)
    }

    /// Updates the text and asks VoiceOver to announce it.
    func show(status: String) {
        statusField.stringValue = status
        NSAccessibility.post(element: statusField, notification: .valueChanged)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: status,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}
