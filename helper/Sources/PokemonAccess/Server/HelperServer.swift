import Foundation
import Network
import PokemonAccessCore

/// TCP server on 127.0.0.1 for the Lua side. One client at a time: a new
/// connection replaces the previous one (the script was reloaded).
final class HelperServer {
    private let requestedPort: UInt16
    private let log: FileLog
    private let queue = DispatchQueue(label: "pokemon-access.server")
    private var listener: NWListener?
    private var client: ClientConnection?

    private(set) var port: UInt16 = 0
    var onMessage: ((LuaMessage) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    /// `port` 0 asks the system for a free port; `start()` returns the actual one.
    init(port: UInt16, log: FileLog) {
        requestedPort = port
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
        client?.cancel()
        let client = ClientConnection(connection)
        client.onLine = { [weak self] line in
            guard let self else { return }
            let fields = LineProtocol.decode(line)
            do {
                let message = try LuaMessage.parse(fields)
                self.onMessage?(message)
            } catch {
                self.log.error("bad message from script: \(error) in \(line)")
            }
        }
        client.onClosed = { [weak self, weak client] in
            guard let self, self.client === client else { return }
            self.client = nil
            self.log.info("script disconnected")
            self.onDisconnect?()
        }
        self.client = client
        client.start(on: queue)
        log.info("script connected")
        onConnect?()
    }

    func send(_ message: HelperMessage) {
        client?.send(message.line)
    }

    func stop() {
        client?.cancel()
        client = nil
        listener?.cancel()
        listener = nil
    }
}
