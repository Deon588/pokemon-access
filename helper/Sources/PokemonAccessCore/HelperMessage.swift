/// Messages the helper sends to the Lua side.
public enum HelperMessage: Equatable {
    case welcome(version: String, keySource: KeySource)
    case key(down: Bool, chord: String)
    case reply(id: Int, ok: Bool, values: [String])

    public var fields: [String] {
        switch self {
        case let .welcome(version, keySource):
            return ["WELCOME", version, keySource.rawValue]
        case let .key(down, chord):
            return ["KEY", down ? "DOWN" : "UP", chord]
        case let .reply(id, ok, values):
            return ["REPLY", String(id), ok ? "OK" : "CANCEL"] + values
        }
    }

    /// The encoded protocol line, newline included.
    public var line: String { LineProtocol.encode(fields) }
}
