import NetworkExtension
import Network
import NIOSSL
import os

/// A per-flow relay owned by the provider until it closes.
protocol Relay: AnyObject, Sendable {
    var isOpen: Bool { get }
    func start()
}

/// Transparent proxy that MITMs the game's realtime WebSocket to observe match
/// state, and passes every other flow through untouched.
final class TransparentProxyProvider: NETransparentProxyProvider {
    private let log = Logger(subsystem: "br.com.anykey.SnapSync.proxy", category: "proxy")
    private var serverContext: NIOSSLContext?
    private let lock = NSLock()
    private var retained: [ObjectIdentifier: any Relay] = [:]
    private let tracker = MatchTracker()
    private let trackerLock = NSLock()
    private var lastSnapshot: MatchSnapshot?
    static let liveMatchPath = "/tmp/snapcompanion-live-match.json"

    override func startProxy(options: [String: Any]?, completionHandler: @escaping (Error?) -> Void) {
        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        // Match outbound TCP to port 443 (all TLS, including the game WebSocket).
        // A fully-wildcard rule (0.0.0.0:0) is rejected — a non-wildcard port or
        // address is required. We filter by host in handleNewFlow.
        let httpsAny = NWEndpoint.hostPort(host: "0.0.0.0", port: 443)
        settings.includedNetworkRules = [
            NENetworkRule(destinationNetworkEndpoint: httpsAny, prefix: 0, protocol: .TCP)
        ]
        serverContext = MITMContext.makeServerContext()
        log.info("MITM server context loaded=\(self.serverContext != nil, privacy: .public)")
        setTunnelNetworkSettings(settings) { error in
            self.log.info("startProxy applied, error=\(String(describing: error), privacy: .public)")
            completionHandler(error)
        }
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // Only touch the game's own flows; everything else the OS handles directly.
        guard flow.metaData.sourceAppSigningIdentifier == "com.nvsgames.snap",
              let tcp = flow as? NEAppProxyTCPFlow,
              case let .hostPort(_, port) = tcp.remoteFlowEndpoint, port.rawValue == 443 else {
            return false
        }
        let endpoint = tcp.remoteFlowEndpoint

        tcp.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            if let error {
                self.log.error("flow open failed: \(String(describing: error), privacy: .public)")
                return
            }
            // Read the first packet (ClientHello) to learn the intended host via SNI.
            tcp.readData { [weak self] data, error in
                guard let self else { return }
                guard error == nil, let data, !data.isEmpty else {
                    tcp.closeReadWithError(nil); tcp.closeWriteWithError(nil); return
                }
                let sni = SNIParser.hostname(data) ?? ""
                // Only the realtime WebSocket host. The API host is HTTP/2 and
                // MITMing it triggers a reconnect storm — not worth it.
                if sni.contains("-ws-cf.nvprod.snapgametech.com"), let context = self.serverContext {
                    self.log.info("MITM \(sni, privacy: .public)")
                    self.retain(FlowMITM(
                        flow: tcp, host: sni, port: 443, initial: data, context: context, log: self.log,
                        onServerMessage: { [weak self] msg in self?.observe(msg) },
                        onClose: { [weak self] in self?.prune() }
                    ))
                } else {
                    self.retain(FlowPassthrough(
                        flow: tcp, endpoint: endpoint, initial: data,
                        onClose: { [weak self] in self?.prune() }
                    ))
                }
            }
        }
        return true
    }

    private func retain(_ relay: (any Relay)?) {
        guard let relay else { return }
        lock.withLock { retained[ObjectIdentifier(relay)] = relay }
        relay.start()
    }

    private func observe(_ message: Data) {
        trackerLock.lock()
        let snapshot = tracker.process(message)
        let changed = snapshot != nil && snapshot != lastSnapshot
        if changed { lastSnapshot = snapshot }
        trackerLock.unlock()
        guard changed, let snapshot, let json = snapshot.json else { return }
        log.info("match: opp=\(snapshot.opponentName, privacy: .public) cards=\(snapshot.opponentCards.count) locs=\(snapshot.locations.count) turn=\(snapshot.turn)/\(snapshot.totalTurns)")
        try? json.write(to: URL(fileURLWithPath: Self.liveMatchPath))
    }

    private func prune() {
        lock.withLock { retained = retained.filter { $0.value.isOpen } }
    }
}
