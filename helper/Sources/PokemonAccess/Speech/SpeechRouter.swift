import Foundation

/// Picks the speech engine from the preference ("auto", "voiceover",
/// "avspeech", "say") and drops to the next one when an engine fails, telling
/// the player when VoiceOver was the one that failed.
final class SpeechRouter: SpeechEngine {
    static let voiceOverFallbackNotice =
        "VoiceOver did not accept speech from Pokemon Access. Using the system voice instead."

    private var engines: [SpeechEngine]
    private let log: FileLog
    private let lock = NSLock()

    var name: String { engines.first?.name ?? "none" }

    init(preference: String, log: FileLog) {
        self.log = log
        let voiceOver = VoiceOverSpeech()
        let system = AVSpeech(voiceIdentifier: Preferences.shared.voiceIdentifier, rate: Preferences.shared.speechRate)
        let say = SaySpeech()
        switch preference {
        case "avspeech": engines = [system, say]
        case "say": engines = [say]
        default: engines = ([voiceOver, system, say] as [SpeechEngine?]).compactMap { $0 }
        }
        if preference == "voiceover", voiceOver == nil {
            log.error("speech engine voiceover requested but VoiceOver is not running")
        }
        log.info("speech engines: \(engines.map(\.name).joined(separator: ", "))")
    }

    func speak(_ text: String, interrupt: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        while let engine = engines.first {
            do {
                try engine.speak(text, interrupt: interrupt)
                return
            } catch {
                log.error("speech engine \(engine.name) failed: \(error)")
                engines.removeFirst()
                if engine.name == "voiceover", let next = engines.first {
                    try? next.speak(Self.voiceOverFallbackNotice, interrupt: false)
                }
            }
        }
        throw SpeechError.noEngine
    }

    func silence() {
        lock.lock()
        engines.first?.silence()
        lock.unlock()
    }
}
