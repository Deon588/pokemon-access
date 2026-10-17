import Foundation
import Network
import PokemonAccessCore

/// One connected Lua script: turns received bytes into protocol lines.
final class ClientConnection {
    private let connection: NWConnection
    private var buffer = LineBuffer()
    var onLine: ((String) -> Void)?
    var onClosed: (() -> Void)?

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.onClosed?()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                for line in self.buffer.feed(data) {
                    self.onLine?(line)
                }
            }
            if isComplete || error != nil {
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    func send(_ text: String) {
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
    }

    func cancel() {
        connection.cancel()
    }
}
