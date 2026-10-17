/// Something that can speak text. `name` identifies the engine in the log.
protocol SpeechEngine: AnyObject {
    var name: String { get }
    /// `interrupt` asks the engine to cut whatever it is saying first.
    func speak(_ text: String, interrupt: Bool) throws
    func silence()
}

enum SpeechError: Error, CustomStringConvertible {
    case voiceOverRefused(code: Int, message: String)
    case noEngine

    var description: String {
        switch self {
        case let .voiceOverRefused(code, message): return "VoiceOver refused (\(code)): \(message)"
        case .noEngine: return "no speech engine left"
        }
    }
}
