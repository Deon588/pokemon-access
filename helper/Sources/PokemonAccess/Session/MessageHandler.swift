import Foundation
import PokemonAccessCore

/// Routes messages from the Lua side to speech, sounds, prompts and the log.
/// Called on the server queue; prompts hop to the main thread and reply later.
final class MessageHandler {
    private let speech: SpeechEngine
    private let sounds: SoundPlayer
    private let prompts: PromptPresenter
    private let log: FileLog
    private(set) var keySource: KeySource = .helper
    var onHello: ((KeySource) -> Void)?

    init(speech: SpeechEngine, sounds: SoundPlayer, prompts: PromptPresenter, log: FileLog) {
        self.speech = speech
        self.sounds = sounds
        self.prompts = prompts
        self.log = log
    }

    func handle(_ message: LuaMessage, reply: @escaping (HelperMessage) -> Void) {
        switch message {
        case let .hello(protocolVersion, keySource, info, _):
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
        case let .sound(id, path, loop, pan, volume):
            sounds.play(id: id, path: path, loop: loop, pan: pan, volume: volume)
        case let .soundStop(id):
            sounds.stop(id: id)
        case let .soundPitch(id, value):
            sounds.setPitch(id: id, value: value)
        case let .log(level, text):
            log.info("lua \(level): \(text)")
        case let .promptText(id, title, caption, defaultValue):
            DispatchQueue.main.async { [prompts] in
                prompts.text(id: id, title: title, caption: caption, defaultValue: defaultValue, reply: reply)
            }
        case let .promptChoice(id, title, caption, multi, defaults, items):
            DispatchQueue.main.async { [prompts] in
                prompts.choice(id: id, title: title, caption: caption, multi: multi, defaults: defaults, items: items, reply: reply)
            }
        }
    }
}
