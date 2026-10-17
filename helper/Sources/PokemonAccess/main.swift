import AppKit
import Foundation
import PokemonAccessCore

let options = LaunchOptions.parse(CommandLine.arguments)
let log = FileLog.shared
log.start(at: AppPaths.logFile)
log.info("Pokemon Access \(AppVersion.current) starting: \(CommandLine.arguments.dropFirst().joined(separator: " "))")

if options.noLaunch {
    // Development mode: speak and serve the protocol without launching mGBA.
    let speech = SpeechRouter(preference: Preferences.shared.speechEngine, log: log)
    let handler = MessageHandler(speech: speech, log: log)
    let server = HelperServer(port: options.port ?? 0, log: log)
    server.onMessage = { message in
        handler.handle(message) { server.send($0) }
    }
    let port = try server.start()
    print("listening on \(port)")
    if let quitAfter = options.quitAfter {
        DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) { exit(0) }
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    print("PokemonAccess \(AppVersion.current): the launcher arrives in a later task; use --no-launch for now")
}
