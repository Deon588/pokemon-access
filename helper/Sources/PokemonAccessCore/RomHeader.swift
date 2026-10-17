import Foundation

/// The parts of a Game Boy cartridge header the launcher cares about.
public struct RomHeader: Equatable {
    public static let minimumSize = 0x150

    public let title: String
    public let globalChecksum: UInt16
    public let cartridgeType: UInt8

    /// Returns nil when `data` is shorter than a header.
    public init?(data: Data) {
        guard data.count >= Self.minimumSize else { return nil }
        let bytes = [UInt8](data.prefix(Self.minimumSize))
        var titleBytes: [UInt8] = []
        for byte in bytes[0x134..<0x144] {
            // Padding, or the CGB flag that later cartridges put at 0x143.
            if byte == 0x00 || byte == 0x80 || byte == 0xC0 { break }
            titleBytes.append(byte)
        }
        title = String(decoding: titleBytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        cartridgeType = bytes[0x147]
        globalChecksum = UInt16(bytes[0x14E]) << 8 | UInt16(bytes[0x14F])
    }

    public var knownGame: KnownGame? {
        KnownGame.match(globalChecksum: globalChecksum)
    }
}
