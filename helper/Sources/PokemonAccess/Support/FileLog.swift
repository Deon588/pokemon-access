import Foundation

/// Timestamped log lines to a file (and to standard error, for scripted runs).
/// The previous run's file is kept as pokemon-access.previous.log.
final class FileLog {
    static let shared = FileLog()

    private let queue = DispatchQueue(label: "pokemon-access.log")
    private var handle: FileHandle?
    private(set) var url: URL?
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    func start(at url: URL) {
        queue.sync {
            let files = FileManager.default
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: url.path) {
                let previous = url.deletingPathExtension().appendingPathExtension("previous.log")
                try? files.removeItem(at: previous)
                try? files.moveItem(at: url, to: previous)
            }
            files.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
            self.url = url
        }
    }

    func info(_ message: String) { write("info", message) }
    func error(_ message: String) { write("error", message) }

    private func write(_ level: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) \(level) \(message)\n"
        let data = Data(line.utf8)
        queue.async { [handle] in
            try? handle?.write(contentsOf: data)
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }
}
