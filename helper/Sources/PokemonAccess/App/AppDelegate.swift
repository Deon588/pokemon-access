import AppKit
import PokemonAccessCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let log: FileLog
    private var status: StatusWindowController?
    private var session: Session?
    private var openedRom: URL?

    init(options: LaunchOptions, log: FileLog) {
        self.options = options
        self.log = log
    }

    /// A ROM dropped on the icon or opened with the application.
    func application(_ application: NSApplication, open urls: [URL]) {
        openedRom = urls.first
        session?.openedRom = urls.first
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        let status = StatusWindowController()
        status.present()
        self.status = status
        let speech = SpeechRouter(preference: Preferences.shared.speechEngine, log: log)
        let session = Session(options: options, status: status, speech: speech, log: log)
        session.openedRom = openedRom
        self.session = session
        Task { @MainActor in
            await session.start()
        }
        if let quitAfter = options.quitAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
                self.log.info("quitting after \(quitAfter) s as requested")
                NSApp.terminate(nil)
            }
        }
    }

    /// Closing the status window keeps the game running; Command Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Reopening the application (Dock, Spotlight) brings the status window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        status?.present()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        session?.shutdown()
    }
}
