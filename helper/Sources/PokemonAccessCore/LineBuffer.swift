import Foundation

/// Accumulates socket chunks and hands back complete lines without their
/// newline (a trailing carriage return is dropped too).
public struct LineBuffer {
    private var pending: [UInt8] = []

    public init() {}

    public mutating func feed(_ data: Data) -> [String] {
        pending.append(contentsOf: data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = Array(pending[..<newline])
            if line.last == 0x0D { line.removeLast() }
            lines.append(String(decoding: line, as: UTF8.self))
            pending.removeSubrange(...newline)
        }
        return lines
    }
}
