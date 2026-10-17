import AVFoundation
import Foundation

/// The system speech synthesizer: used when VoiceOver is not running or
/// refuses, with an optional voice and rate from the preferences.
final class AVSpeech: SpeechEngine {
    let name = "avspeech"
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private let rate: Float

    init(voiceIdentifier: String?, rate: Float?) {
        voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        self.rate = rate ?? AVSpeechUtteranceDefaultSpeechRate
    }

    func speak(_ text: String, interrupt: Bool) throws {
        onMainThread {
            if interrupt, synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = rate
            synthesizer.speak(utterance)
        }
    }

    func silence() {
        onMainThread { synthesizer.stopSpeaking(at: .immediate) }
    }
}
