/// Games upstream recognises by the cartridge header's global checksum
/// (the `oldgame_checksum` table in gb.lua).
public enum KnownGame: Equatable, Sendable {
    case red(language: String)
    case blue(language: String)
    case yellow(language: String)

    private static let byChecksum: [UInt16: KnownGame] = [
        0x91e6: .red(language: "en"), 0x384a: .red(language: "es"), 0x7afc: .red(language: "fr"),
        0x89d2: .red(language: "it"), 0x5cdc: .red(language: "de"),
        0x9d0a: .blue(language: "en"), 0x14d7: .blue(language: "es"), 0x56a4: .blue(language: "fr"),
        0x5e9c: .blue(language: "it"), 0x2ebc: .blue(language: "de"),
        0x047c: .yellow(language: "en"),
    ]

    public static func match(globalChecksum: UInt16) -> KnownGame? {
        byChecksum[globalChecksum]
    }

    public var displayName: String {
        switch self {
        case let .red(language): return "Pokémon Red (\(language))"
        case let .blue(language): return "Pokémon Blue (\(language))"
        case let .yellow(language): return "Pokémon Yellow (\(language))"
        }
    }
}
