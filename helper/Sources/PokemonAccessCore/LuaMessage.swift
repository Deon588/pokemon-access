/// Messages the Lua side sends to the helper.
public enum LuaMessage: Equatable {
    case hello(protocolVersion: Int, keySource: KeySource, info: String, token: String?)
    case speak(interrupt: Bool, text: String)
    case silence
    case sound(id: Int, path: String, loop: Bool, pan: Int, volume: Int)
    case soundStop(id: Int)
    case soundPitch(id: Int, value: Double)
    case promptText(id: Int, title: String, caption: String, defaultValue: String)
    case promptChoice(id: Int, title: String, caption: String, multi: Bool, defaults: [Int], items: [String])
    case log(level: String, text: String)

    /// Parses the decoded fields of one line.
    public static func parse(_ fields: [String]) throws -> LuaMessage {
        guard let type = fields.first else { throw LuaMessageError.empty }

        func need(_ count: Int) throws {
            if fields.count < count { throw LuaMessageError.malformed(type) }
        }
        func int(_ index: Int) throws -> Int {
            guard let value = Int(fields[index]) else { throw LuaMessageError.malformed(type) }
            return value
        }
        func flag(_ index: Int) -> Bool { fields[index] == "1" }
        // Upstream computes some values as floats; like the C API it targeted,
        // truncate. Values outside Int are malformed rather than a trap.
        func number(_ index: Int) throws -> Int {
            if let value = Int(fields[index]) { return value }
            guard let value = Double(fields[index]), value.isFinite,
                  let integer = Int(exactly: value.rounded(.towardZero)) else {
                throw LuaMessageError.malformed(type)
            }
            return integer
        }

        switch type {
        case "HELLO":
            try need(4)
            guard let source = KeySource(rawValue: fields[2]) else { throw LuaMessageError.malformed(type) }
            let token = fields.count > 4 && !fields[4].isEmpty ? fields[4] : nil
            return .hello(protocolVersion: try int(1), keySource: source, info: fields[3], token: token)
        case "SPEAK":
            try need(3)
            return .speak(interrupt: flag(1), text: fields[2])
        case "SILENCE":
            return .silence
        case "SOUND":
            try need(6)
            return .sound(id: try int(1), path: fields[2], loop: flag(3), pan: try number(4), volume: try number(5))
        case "SOUND_STOP":
            try need(2)
            return .soundStop(id: try int(1))
        case "SOUND_PITCH":
            try need(3)
            guard let value = Double(fields[2]) else { throw LuaMessageError.malformed(type) }
            return .soundPitch(id: try int(1), value: value)
        case "PROMPT_TEXT":
            try need(5)
            return .promptText(id: try int(1), title: fields[2], caption: fields[3], defaultValue: fields[4])
        case "PROMPT_CHOICE":
            try need(6)
            let defaults = fields[5].split(separator: ",").compactMap { Int($0) }
            return .promptChoice(id: try int(1), title: fields[2], caption: fields[3], multi: flag(4),
                                 defaults: defaults, items: Array(fields[6...]))
        case "LOG":
            try need(3)
            return .log(level: fields[1], text: fields[2])
        default:
            throw LuaMessageError.unknownType(type)
        }
    }
}

public enum LuaMessageError: Error, Equatable {
    case empty
    case unknownType(String)
    case malformed(String)
}
