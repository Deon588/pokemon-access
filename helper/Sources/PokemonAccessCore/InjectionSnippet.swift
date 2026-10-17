/// The one line of Lua typed into mGBA's Scripting prompt. Long brackets mean
/// spaces, quotes and backslashes in the path need no escaping.
public enum InjectionSnippet {
    public static func dofile(path: String) -> String {
        "dofile([==[\(path)]==])"
    }
}
