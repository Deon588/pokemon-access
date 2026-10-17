import Foundation

/// Last resort: one `/usr/bin/say` process per utterance. The previous
/// utterance is cut whenever a new one starts, since `say` cannot queue.
final class SaySpeech: SpeechEngine {
    let name = "say"
    private var current: Process?
    private let lock = NSLock()

    func speak(_ text: String, interrupt: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        current?.terminate()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["--", text]
        try process.run()
        current = process
    }

    func silence() {
        lock.lock()
        current?.terminate()
        current = nil
        lock.unlock()
    }
}
