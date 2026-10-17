/// Virtual key codes of the ANSI US layout (the kVK_ANSI_* constants), used
/// when the current keyboard layout does not produce a character.
public enum AnsiKeyCodes {
    private static let codes: [Character: UInt16] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
        "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
        "T": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
        "7": 0x1A, "8": 0x1C, "0": 0x1D, "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25,
        "J": 0x26, "K": 0x28, "N": 0x2D, "M": 0x2E,
    ]

    public static func keyCode(for character: Character) -> UInt16? {
        guard let upper = character.uppercased().first else { return nil }
        return codes[upper]
    }
}
