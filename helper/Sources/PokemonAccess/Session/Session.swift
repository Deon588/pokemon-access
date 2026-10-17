import AppKit
import Foundation
import PokemonAccessCore

/// The launch flow: find mGBA and the ROM, get the Accessibility permission
/// when the script has to go through the Scripting window, start the server
/// and mGBA, load the script, wait for its HELLO, then relay hotkeys and
/// messages until mGBA quits.
@MainActor
final class Session {
    enum Mode: String {
        case script // mGBA 0.11: --script on the command line
        case inject // mGBA 0.10.5: the Scripting window through Accessibility
    }

    static let connectedStatus = "Connected to the script. Switch to mGBA to play."
    static let permissionGranted = "Thank you. Starting mGBA."
    static let mgbaClosed = "mGBA closed. Pokemon Access will quit."

    private let options: LaunchOptions
    private let status: StatusWindowController
    private let speech: SpeechEngine
    private let log: FileLog

    private var server: HelperServer?
    private var launcher: MgbaLauncher?
    private var sounds: SoundPlayer?
    private var handler: MessageHandler?
    private var hotkeys: HotkeyMonitor?
    private var frontmost: FrontmostAppWatcher?
    private var helloReceived = false
    private var quitting = false

    var openedRom: URL?

    init(options: LaunchOptions, status: StatusWindowController, speech: SpeechEngine, log: FileLog) {
        self.options = options
        self.status = status
        self.speech = speech
        self.log = log
    }

    func start() async {
        do {
            try await run()
        } catch let error as SessionError {
            fail(error.errorDescription ?? "\(error)")
            if case .romMissing = error {
                quitSoon()
            }
        } catch {
            fail("Pokemon Access could not start: \(error.localizedDescription)")
        }
    }

    private func run() async throws {
        try AppPaths.ensureDirectories()
        guard let installation = MgbaInstallation.find(override: options.mgbaApp) else {
            throw SessionError.mgbaMissing
        }
        let launcher = MgbaLauncher(installation: installation, log: log)
        self.launcher = launcher

        if !NSRunningApplication.runningApplications(withBundleIdentifier: MgbaInstallation.bundleIdentifier).isEmpty {
            throw SessionError.mgbaAlreadyRunning
        }

        let locator = RomLocator(romsDirectory: AppPaths.romsDirectory, preferences: Preferences.shared)
        var rejected: Set<String> = []
        var rom: URL
        var header: RomHeader?
        while true {
            guard let candidate = locator.resolve(explicit: options.rom, opened: openedRom, rejected: rejected) else {
                throw SessionError.romMissing
            }
            let (parsed, warning) = locator.describe(candidate)
            if parsed == nil {
                // Not a Game Boy ROM at all: say so and ask again instead of launching.
                log.error("not a Game Boy ROM: \(candidate.path)")
                say(warning ?? RomLocator.notARomWarning)
                rejected.insert(candidate.path)
                continue
            }
            if let warning {
                say(warning)
            }
            rom = candidate
            header = parsed
            break
        }
        log.info("ROM \(rom.path): title \(header?.title ?? "?"), checksum \(String(format: "%04x", header?.globalChecksum ?? 0)), \(header?.knownGame?.displayName ?? "unknown game")")

        let luaRoot = AppPaths.luaRoot(override: options.luaRoot)
        let entry = luaRoot.appendingPathComponent("pokemon-access.lua")
        guard FileManager.default.fileExists(atPath: entry.path) else {
            throw SessionError.luaMissing(entry.path)
        }

        let mode: Mode = launcher.supportsScriptOption() ? .script : .inject
        log.info("mGBA \(installation.version) at \(installation.bundleURL.path), mode \(mode.rawValue)")
        if mode == .inject, !AccessibilityPermission.isTrusted {
            let message = SessionError.accessibilityDenied.errorDescription ?? ""
            show(message)
            say(message)
            AccessibilityPermission.prompt()
            guard await AccessibilityPermission.waitUntilTrusted(timeout: 600) else {
                throw SessionError.accessibilityDenied
            }
            say(Self.permissionGranted)
        }

        try MgbaConfigWriter.ensure(configHome: AppPaths.mgbaConfigHome, config: MgbaConfig(volume: Preferences.shared.mgbaVolume))

        let token = HandshakeGate.makeToken()
        let server = HelperServer(port: options.port ?? 0, token: token, log: log)
        let sounds = SoundPlayer(root: luaRoot, gain: Preferences.shared.soundGain, log: log)
        let handler = MessageHandler(speech: speech, sounds: sounds, prompts: PromptPresenter(log: log), log: log)
        handler.onHello = { [weak self] keySource in
            Task { @MainActor in self?.scriptSaidHello(keySource: keySource) }
        }
        server.onMessage = { [weak server, handler] message in
            handler.handle(message) { reply in server?.send(reply) }
        }
        self.server = server
        self.sounds = sounds
        self.handler = handler
        let port = try server.start()

        show("Starting mGBA.")
        let environment = [
            "XDG_CONFIG_HOME": AppPaths.mgbaConfigHome.path,
            "POKEMON_ACCESS_PORT": String(port),
            "POKEMON_ACCESS_TOKEN": token,
            "POKEMON_ACCESS_LOG": log.url?.path ?? "",
        ]
        try launcher.launch(rom: rom, script: mode == .script ? entry : nil, environment: environment,
                            workingDirectory: AppPaths.dataDirectory) { [weak self] exitStatus in
            Task { @MainActor in self?.mgbaExited(status: exitStatus) }
        }

        if mode == .inject {
            guard let pid = launcher.processIdentifier else { throw SessionError.mgbaFailed(-1) }
            let injector = ScriptInjector(pid: pid, log: log)
            try await Task.detached {
                try injector.load(script: entry, timeout: 30)
            }.value
        }

        let deadline = Date().addingTimeInterval(30)
        while !helloReceived, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard helloReceived else { throw SessionError.scriptNotStarted }
        show(Self.connectedStatus)
    }

    private func scriptSaidHello(keySource: KeySource) {
        helloReceived = true
        if keySource == .helper {
            relayHotkeysWhileMgbaIsFrontmost()
        } else {
            hotkeys?.disable()
            frontmost = nil
        }
    }

    private func relayHotkeysWhileMgbaIsFrontmost() {
        if hotkeys == nil {
            hotkeys = HotkeyMonitor(chords: HotkeyTable.all, layout: KeyboardLayout.current(), log: log) { [weak self] chord, down in
                self?.server?.send(.key(down: down, chord: chord.name))
            }
        }
        frontmost = FrontmostAppWatcher(bundleIdentifier: MgbaInstallation.bundleIdentifier) { [weak self] isFrontmost in
            guard let self, let hotkeys = self.hotkeys else { return }
            if isFrontmost || self.options.hotkeysAlways {
                do { try hotkeys.enable() } catch { self.log.error("hotkeys could not be enabled: \(error)") }
            } else {
                hotkeys.disable()
            }
        }
    }

    private func mgbaExited(status exitStatus: Int32) {
        guard !quitting else { return }
        log.info("mGBA exited with status \(exitStatus)")
        show(Self.mgbaClosed)
        say(Self.mgbaClosed)
        quitSoon()
    }

    private func quitSoon() {
        quitting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NSApp.terminate(nil)
        }
    }

    private func fail(_ message: String) {
        log.error(message)
        show(message)
        say(message)
    }

    private func say(_ text: String) {
        do {
            try speech.speak(text, interrupt: false)
            log.info("speak via \(speech.name): \(text)")
        } catch {
            log.error("could not speak: \(error)")
        }
    }

    private func show(_ text: String) {
        status.show(status: text)
        log.info("status: \(text)")
    }

    /// Quitting Pokemon Access also quits mGBA, politely so it writes its saves.
    func shutdown() {
        quitting = true
        hotkeys?.disable()
        server?.stop()
        if let pid = launcher?.processIdentifier {
            NSRunningApplication(processIdentifier: pid)?.terminate()
        }
    }
}
