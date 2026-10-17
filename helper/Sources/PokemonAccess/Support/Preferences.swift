import Foundation

/// User settings, changed with `defaults write com.abstractsingleton.pokemon-access <key> <value>`.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    /// "auto" (VoiceOver when it runs, else the system voice), "voiceover", "avspeech" or "say".
    var speechEngine: String { defaults.string(forKey: "speechEngine") ?? "auto" }
    /// An AVSpeechSynthesisVoice identifier for the "avspeech" engine.
    var voiceIdentifier: String? { defaults.string(forKey: "voiceIdentifier") }
    /// AVSpeechUtterance rate (0 to 1) for the "avspeech" engine.
    var speechRate: Float? { defaults.object(forKey: "speechRate") == nil ? nil : defaults.float(forKey: "speechRate") }
    /// Multiplier applied to every sound cue's volume.
    var soundGain: Double { defaults.object(forKey: "soundGain") == nil ? 1.0 : defaults.double(forKey: "soundGain") }
    /// mGBA's game volume, 0 to 256.
    var mgbaVolume: Int { defaults.object(forKey: "mgbaVolume") == nil ? 128 : defaults.integer(forKey: "mgbaVolume") }
    /// A checkout of this repository to run the Lua files from instead of the bundled copy.
    var luaRoot: String? { defaults.string(forKey: "luaRoot") }
    /// The ROM chosen last time.
    var romPath: String? {
        get { defaults.string(forKey: "romPath") }
        set { defaults.set(newValue, forKey: "romPath") }
    }
}
