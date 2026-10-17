/// Every chord upstream pokemon.lua binds (its `commands` table): fifteen
/// letters, each alone and with shift, plus shift+0 for the hack ROM setup.
public enum HotkeyTable {
    public static let letters: [Character] = ["Y", "J", "K", "L", "P", "T", "M", "E", "D", "G", "R", "V", "F", "C", "H"]

    public static let all: [HotkeyChord] =
        letters.flatMap { [HotkeyChord(key: $0, shift: false), HotkeyChord(key: $0, shift: true)] }
        + [HotkeyChord(key: "0", shift: true)]
}
