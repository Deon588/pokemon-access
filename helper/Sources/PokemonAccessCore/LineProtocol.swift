/// The line protocol shared with the Lua side (PORTING.md 6.2): one message per
/// line, fields separated by tabs, and inside a field a backslash, a tab and a
/// newline written as `\\`, `\t` and `\n`. Works on UTF-8 bytes so multi-byte
/// characters and `\r\n` (one grapheme in Swift) are handled byte by byte.
public enum LineProtocol {
    private static let backslash: UInt8 = 0x5C
    private static let tab: UInt8 = 0x09
    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    public static func escape(_ text: String) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count + 8)
        for byte in text.utf8 {
            switch byte {
            case backslash: out.append(contentsOf: [backslash, backslash])
            case tab: out.append(contentsOf: [backslash, UInt8(ascii: "t")])
            case newline: out.append(contentsOf: [backslash, UInt8(ascii: "n")])
            default: out.append(byte)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func unescape(_ text: String) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(text.utf8.count)
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            if byte == backslash, let next = iterator.next() {
                switch next {
                case UInt8(ascii: "t"): out.append(tab)
                case UInt8(ascii: "n"): out.append(newline)
                default: out.append(next)
                }
            } else {
                out.append(byte)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Joins the fields into one line, newline included.
    public static func encode(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: "\t") + "\n"
    }

    /// Splits one line into its fields; a trailing newline or CRLF is dropped.
    public static func decode(_ line: String) -> [String] {
        var bytes = Array(line.utf8)
        if bytes.last == newline { bytes.removeLast() }
        if bytes.last == carriageReturn { bytes.removeLast() }
        return bytes
            .split(separator: tab, omittingEmptySubsequences: false)
            .map { unescape(String(decoding: $0, as: UTF8.self)) }
    }
}
