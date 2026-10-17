/// One upstream hotkey: a letter or digit, alone or with shift. `name` is the
/// spelling upstream's commands table and the KEY message use ("shift+H", "T").
public struct HotkeyChord: Hashable, Sendable {
    public let key: Character
    public let shift: Bool

    public init(key: Character, shift: Bool) {
        self.key = key
        self.shift = shift
    }

    public var name: String {
        shift ? "shift+\(key)" : String(key)
    }
}
