import Foundation

/// Everything that can stop a session before the game is playable, with the
/// sentence the player hears.
enum SessionError: LocalizedError {
    case mgbaMissing
    case romMissing
    case luaMissing(String)
    case accessibilityDenied
    case scriptNotStarted
    case mgbaFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .mgbaMissing:
            return "mGBA is not installed. Install it with Homebrew: brew install --cask mgba-app. Then open Pokemon Access again."
        case .romMissing:
            return "No ROM chosen. Pokemon Access will quit."
        case let .luaMissing(path):
            return "The Pokemon Access scripts were not found at \(path)."
        case .accessibilityDenied:
            return "Pokemon Access needs the Accessibility permission to load its script into mGBA. In System Settings, Privacy and Security, Accessibility, turn on Pokemon Access, then come back to this window."
        case .scriptNotStarted:
            return "The script did not start inside mGBA. The log is in the Logs folder of your Library folder, under Pokemon Access."
        case let .mgbaFailed(status):
            return "mGBA stopped unexpectedly with status \(status)."
        }
    }
}
