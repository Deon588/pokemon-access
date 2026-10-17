import Foundation

/// Picks the speech engine from the preference ("auto", "voiceover",
/// "avspeech", "say") and drops to the next one when an engine fails, telling
/// the player when VoiceOver was the one that failed. Every engine call runs on
/// the main queue, asynchronously, so a caller on the server queue never waits
/// on the main thread (and the main thread never waits on the server queue).
final class SpeechRouter: SpeechEngine {
    static let voiceOverFallbackNotice =
        "VoiceOver did not accept speech from Pokemon Access. Using the system voice instead."

    private var engines: [SpeechEngine] // main queue only
    private let log: FileLog
    private let nameLock = NSLock()
    private var currentName: String

    var name: String {
        nameLock.lock()
        defer { nameLock.unlock() }
        return currentName
    }

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
        currentName = engines.first?.name ?? "none"
        if preference == "voiceover", voiceOver == nil {
            log.error("speech engine voiceover requested but VoiceOver is not running")
        }
        log.info("speech engines: \(engines.map(\.name).joined(separator: ", "))")
    }

    func speak(_ text: String, interrupt: Bool) throws {
        DispatchQueue.main.async { self.speakOnMain(text, interrupt: interrupt) }
    }

    func silence() {
        DispatchQueue.main.async { self.engines.first?.silence() }
    }

    private func speakOnMain(_ text: String, interrupt: Bool) {
        while let engine = engines.first {
            do {
                try engine.speak(text, interrupt: interrupt)
                return
            } catch {
                log.error("speech engine \(engine.name) failed: \(error)")
                engines.removeFirst()
                nameLock.lock()
                currentName = engines.first?.name ?? "none"
                nameLock.unlock()
                if engine.name == "voiceover", let next = engines.first {
                    try? next.speak(Self.voiceOverFallbackNotice, interrupt: false)
                }
            }
        }
        log.error("no speech engine left for: \(text)")
    }
}
