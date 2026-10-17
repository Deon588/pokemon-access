/// Where hotkeys come from: the helper's Carbon hot keys (mGBA 0.10.5) or
/// mGBA's own key events in Lua (0.11). The Lua side decides and tells the
/// helper in HELLO.
public enum KeySource: String, Equatable, Sendable {
    case helper
    case lua
}
