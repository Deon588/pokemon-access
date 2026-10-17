import Foundation

/// Game Boy ROM files among a directory listing, sorted for display.
public enum RomCandidates {
    public static func filter(fileNames: [String]) -> [String] {
        fileNames
            .filter { name in
                let lowered = name.lowercased()
                return lowered.hasSuffix(".gb") || lowered.hasSuffix(".gbc")
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
