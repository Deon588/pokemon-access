import AppKit
import Foundation
import PokemonAccessCore
import UniformTypeIdentifiers

/// Finds the ROM to play: a file opened with the app, the one remembered from
/// last time, the ROMs folder, or the standard open panel.
@MainActor
final class RomLocator {
    static let openPanelMessage = "Choose your Pokémon Red or Blue ROM"
    static let unknownRomWarning = "This ROM is not a known Pokémon Red or Blue dump. Starting anyway."
    static let notARomWarning = "This file is not a Game Boy ROM."

    private let romsDirectory: URL
    private let preferences: Preferences

    init(romsDirectory: URL, preferences: Preferences) {
        self.romsDirectory = romsDirectory
        self.preferences = preferences
    }

    func resolve(opened: URL?) -> URL? {
        let files = FileManager.default
        if let opened, files.fileExists(atPath: opened.path) {
            remember(opened)
            return opened
        }
        if let remembered = preferences.romPath, files.fileExists(atPath: remembered) {
            return URL(fileURLWithPath: remembered)
        }
        let names = (try? files.contentsOfDirectory(atPath: romsDirectory.path)) ?? []
        let candidates = RomCandidates.filter(fileNames: names)
        switch candidates.count {
        case 0:
            return openPanel()
        case 1:
            let url = romsDirectory.appendingPathComponent(candidates[0])
            remember(url)
            return url
        default:
            return choose(among: candidates)
        }
    }

    /// The parsed header and a spoken warning when the ROM is not a known dump.
    func describe(_ url: URL) -> (header: RomHeader?, warning: String?) {
        guard let data = try? Data(contentsOf: url), let header = RomHeader(data: data) else {
            return (nil, Self.notARomWarning)
        }
        return (header, header.knownGame == nil ? Self.unknownRomWarning : nil)
    }

    private func remember(_ url: URL) {
        preferences.romPath = url.path
    }

    private func choose(among names: [String]) -> URL? {
        let alert = NSAlert()
        alert.messageText = "Choose a ROM"
        alert.informativeText = "Several ROMs are in the ROMs folder. Which one do you want to play?"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        popup.addItems(withTitles: names)
        popup.setAccessibilityLabel("ROM")
        alert.accessoryView = popup
        alert.addButton(withTitle: "Play")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let url = romsDirectory.appendingPathComponent(names[max(0, popup.indexOfSelectedItem)])
        remember(url)
        return url
    }

    private func openPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.message = Self.openPanelMessage
        panel.prompt = "Play"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["gb", "gbc"].compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = romsDirectory
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        remember(url)
        return url
    }
}
