import AppKit
import Foundation
import PokemonAccessCore

let options = LaunchOptions.parse(CommandLine.arguments)
let log = FileLog.shared
log.start(at: AppPaths.logFile)
log.info("Pokemon Access \(AppVersion.current) starting: \(CommandLine.arguments.dropFirst().joined(separator: " "))")

if options.probeMgba {
    if let installation = MgbaInstallation.find(override: options.mgbaApp) {
        let launcher = MgbaLauncher(installation: installation, log: log)
        print("found \(installation.bundleURL.path) version \(installation.version) script option: \(launcher.supportsScriptOption())")
    } else {
        print("mGBA not found")
    }
    exit(0)
}

let app = NSApplication.shared

if options.noLaunch {
    // Development mode: speak and serve the protocol without launching mGBA.
    let speech = SpeechRouter(preference: Preferences.shared.speechEngine, log: log)
    let sounds = SoundPlayer(root: AppPaths.luaRoot(override: options.luaRoot), gain: Preferences.shared.soundGain, log: log)
    let handler = MessageHandler(speech: speech, sounds: sounds, prompts: PromptPresenter(log: log), log: log)
    let server = HelperServer(port: options.port ?? 0, token: nil, log: log)
    server.onMessage = { message in
        handler.handle(message) { server.send($0) }
    }
    let port = try server.start()
    print("listening on \(port)")
    var hotkeys: HotkeyMonitor?
    if options.hotkeysAlways {
        hotkeys = HotkeyMonitor(chords: HotkeyTable.all, layout: KeyboardLayout.current(), log: log) { chord, down in
            log.info("KEY \(down ? "DOWN" : "UP") \(chord.name)")
            server.send(.key(down: down, chord: chord.name))
        }
        try hotkeys?.enable()
    }
    if let quitAfter = options.quitAfter {
        DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) { exit(0) }
    }
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    let delegate = AppDelegate(options: options, log: log)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
