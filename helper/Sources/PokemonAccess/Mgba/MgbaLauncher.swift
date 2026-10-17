import Foundation

/// Starts mGBA with the ROM, the private configuration and the helper's
/// connection details in the environment, and reports when it exits.
final class MgbaLauncher {
    let installation: MgbaInstallation
    private let log: FileLog
    private(set) var process: Process?

    init(installation: MgbaInstallation, log: FileLog) {
        self.installation = installation
        self.log = log
    }

    var processIdentifier: pid_t? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    /// True when `mGBA --help` lists --script (0.11 and later).
    func supportsScriptOption() -> Bool {
        let probe = Process()
        probe.executableURL = installation.executableURL
        probe.arguments = ["--help"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = pipe
        do {
            try probe.run()
        } catch {
            log.error("could not run mGBA --help: \(error)")
            return false
        }
        var output = Data()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            finished.signal()
        }
        if finished.wait(timeout: .now() + 10) == .timedOut {
            probe.terminate()
            log.error("mGBA --help did not finish within 10 s")
            return false
        }
        probe.waitUntilExit()
        return String(decoding: output, as: UTF8.self).contains("--script")
    }

    /// `script` is passed as --script on builds that support it (see
    /// supportsScriptOption); `environment` is merged into the current one.
    @discardableResult
    func launch(rom: URL, script: URL?, environment: [String: String], workingDirectory: URL,
                onExit: @escaping (Int32) -> Void) throws -> Process {
        let process = Process()
        process.executableURL = installation.executableURL
        var arguments: [String] = []
        if let script {
            arguments += ["--script", script.path]
        }
        arguments.append(rom.path)
        process.arguments = arguments
        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            merged[key] = value
        }
        process.environment = merged
        process.currentDirectoryURL = workingDirectory
        process.terminationHandler = { finished in onExit(finished.terminationStatus) }
        try process.run()
        self.process = process
        log.info("mGBA started, pid \(process.processIdentifier): \(arguments.joined(separator: " "))")
        return process
    }

    func terminate() {
        process?.terminate()
    }
}
