import Foundation
import Network
import NetworkExtension

/// Raw TCP relay for a taken flow we don't want to MITM. We must take every
/// SNAP :443 flow to peek its SNI; the ones that aren't the game WebSocket are
/// piped through untouched so the game keeps working.
///
/// ponytail: @unchecked Sendable — state is serialized on `queue`.
final class FlowPassthrough: Relay, @unchecked Sendable {
    private let flow: NEAppProxyTCPFlow
    private let conn: NWConnection
    private let queue = DispatchQueue(label: "snap.mitm.pass")
    private let initial: Data
    private let onClose: () -> Void
    private var closed = false
    var isOpen: Bool { !closed }

    init(flow: NEAppProxyTCPFlow, endpoint: NWEndpoint, initial: Data, onClose: @escaping () -> Void) {
        self.flow = flow
        self.initial = initial
        self.onClose = onClose
        self.conn = NWConnection(to: endpoint, using: .tcp)
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.queue.async {
                    if !self.initial.isEmpty {
                        self.conn.send(content: self.initial, completion: .contentProcessed { _ in })
                    }
                    self.pumpFromServer()
                    self.pumpFromGame()
                }
            case .failed:
                self.teardown()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func pumpFromGame() {
        flow.readData { [weak self] data, error in
            guard let self else { return }
            self.queue.async {
                guard error == nil, let data, !data.isEmpty else { self.teardown(); return }
                self.conn.send(content: data, completion: .contentProcessed { _ in })
                self.pumpFromGame()
            }
        }
    }

    private func pumpFromServer() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let data, !data.isEmpty { self.flow.write(data) { _ in } }
                if isComplete || error != nil { self.teardown() } else { self.pumpFromServer() }
            }
        }
    }

    private func teardown() {
        guard !closed else { return }
        closed = true
        conn.cancel()
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
        onClose()
    }
}
