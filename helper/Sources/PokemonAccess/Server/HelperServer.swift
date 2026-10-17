import Foundation
import Network
import PokemonAccessCore

/// TCP server on 127.0.0.1 for the Lua side. One client at a time: a new
/// connection replaces the previous one (the script was reloaded) once it
/// has sent a valid HELLO; connections that start with anything else, or with
/// the wrong launch token, are dropped.
final class HelperServer {
    private let requestedPort: UInt16
    private let token: String?
    private let log: FileLog
    private let queue = DispatchQueue(label: "pokemon-access.server")
    private var listener: NWListener?
    private var client: ClientConnection?
    /// Connections that have not sent their HELLO yet; kept alive until they do or close.
    private var candidates: [ObjectIdentifier: ClientConnection] = [:]

    private(set) var port: UInt16 = 0
    var onMessage: ((LuaMessage) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    /// `port` 0 asks the system for a free port; `start()` returns the actual one.
    /// `token` nil accepts any HELLO (development mode).
    init(port: UInt16, token: String?, log: FileLog) {
        requestedPort = port
        self.token = token
        self.log = log
    }

    func start() throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: requestedPort) ?? .any)
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        var failure: Error?
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                self?.port = listener?.port?.rawValue ?? 0
                ready.signal()
            case let .failed(error):
                failure = error
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        if let failure { throw failure }
        self.listener = listener
        log.info("listening on 127.0.0.1:\(port)")
        return port
    }

    private func accept(_ connection: NWConnection) {
        let candidate = ClientConnection(connection)
        candidates[ObjectIdentifier(candidate)] = candidate
        var accepted = false
        candidate.onLine = { [weak self, weak candidate] line in
            guard let self, let candidate else { return }
            let fields = LineProtocol.decode(line)
            let message: LuaMessage
            do {
                message = try LuaMessage.parse(fields)
            } catch {
                if accepted {
                    self.log.error("bad message from script: \(error) in \(line)")
                } else {
                    self.log.error("rejected connection: first line was not a protocol message")
                    candidate.cancel()
                }
                return
            }
            if !accepted {
                guard HandshakeGate.accepts(first: message, expectedToken: self.token) else {
                    self.log.error("rejected connection: first message was not a HELLO with the launch token")
                    candidate.cancel()
                    return
                }
                accepted = true
                self.candidates.removeValue(forKey: ObjectIdentifier(candidate))
                self.client?.cancel()
                self.client = candidate
                self.log.info("script connected")
                self.onConnect?()
            }
            self.onMessage?(message)
        }
        candidate.onClosed = { [weak self, weak candidate] in
            guard let self, let candidate else { return }
            self.candidates.removeValue(forKey: ObjectIdentifier(candidate))
            guard self.client === candidate else { return }
            self.client = nil
            self.log.info("script disconnected")
            self.onDisconnect?()
        }
        candidate.start(on: queue)
    }

    func send(_ message: HelperMessage) {
        client?.send(message.line)
    }

    func stop() {
        candidates.values.forEach { $0.cancel() }
        candidates = [:]
        client?.cancel()
        client = nil
        listener?.cancel()
        listener = nil
    }
}
