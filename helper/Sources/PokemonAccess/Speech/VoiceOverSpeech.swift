import AppKit
import Foundation

/// Speaks through VoiceOver itself (`tell application "VoiceOver" to output`),
/// so the player hears their own voice, rate and pronunciation settings.
/// Requires VoiceOver to be running with "Allow VoiceOver to be controlled
/// with AppleScript" enabled, and the Automation permission on first use.
final class VoiceOverSpeech: SpeechEngine {
    let name = "voiceover"
    private let script: NSAppleScript

    /// Nil when VoiceOver is not running.
    init?() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return nil }
        let source = """
        on speakText(theText)
            tell application "VoiceOver" to output theText
        end speakText
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var compileError: NSDictionary?
        guard script.compileAndReturnError(&compileError) else { return nil }
        self.script = script
    }

    /// VoiceOver's `output` offers no queue control; the Lua side already
    /// batches one utterance per frame so each command's text stays whole.
    /// Must run on the main thread (NSAppleScript); the router guarantees it.
    func speak(_ text: String, interrupt: Bool) throws {
        try callSpeakText(text)
    }

    /// Nothing to do: the next output replaces the current one, and the
    /// Control key stops VoiceOver at any time.
    func silence() {}

    private func callSpeakText(_ text: String) throws {
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string: text), at: 1)
        let event = NSAppleEventDescriptor(
            eventClass: fourCharCode("ascr"), eventID: fourCharCode("psbr"),
            targetDescriptor: nil, returnID: -1, transactionID: 0)
        event.setDescriptor(NSAppleEventDescriptor(string: "speaktext"), forKeyword: fourCharCode("snam"))
        event.setDescriptor(parameters, forKeyword: fourCharCode("----"))
        var error: NSDictionary?
        script.executeAppleEvent(event, error: &error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw SpeechError.voiceOverRefused(code: code, message: message)
        }
    }

    private func fourCharCode(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
