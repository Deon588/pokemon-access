import Foundation
import PokemonAccessCore

/// Routes messages from the Lua side to speech and the log; later tasks add
/// sounds and prompts.
final class MessageHandler {
    private let speech: SpeechEngine
    private let log: FileLog
    private(set) var keySource: KeySource = .helper
    var onHello: ((KeySource) -> Void)?

    init(speech: SpeechEngine, log: FileLog) {
        self.speech = speech
        self.log = log
    }

    func handle(_ message: LuaMessage, reply: (HelperMessage) -> Void) {
        switch message {
        case let .hello(protocolVersion, keySource, info):
            log.info("hello from script: protocol \(protocolVersion), keys from \(keySource.rawValue), \(info)")
            self.keySource = keySource
            reply(.welcome(version: AppVersion.current, keySource: keySource))
            onHello?(keySource)
        case let .speak(interrupt, text):
            do {
                try speech.speak(text, interrupt: interrupt)
                let oneLine = text.replacingOccurrences(of: "\n", with: " | ")
                log.info("speak via \(speech.name)\(interrupt ? " (interrupt)" : ""): \(oneLine)")
            } catch {
                log.error("speech failed: \(error)")
            }
        case .silence:
            speech.silence()
            log.info("silence")
        case let .log(level, text):
            log.info("lua \(level): \(text)")
        default:
            log.info("unhandled message: \(message)")
        }
    }
}
