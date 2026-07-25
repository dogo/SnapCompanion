import Foundation
import Network
import NetworkExtension
import NIOCore
import NIOEmbedded
import NIOSSL
import os

/// TLS man-in-the-middle for a single intercepted flow. Terminates the game's
/// TLS with our leaf (NIOSSL driven over the flow's byte stream via an
/// EmbeddedChannel), opens a real TLS connection to the true server
/// (Network.framework), and relays plaintext between them while observing the
/// server → game direction (where the match changes arrive).
///
/// ponytail: @unchecked Sendable — all mutable state is serialized on `queue`;
/// the NE/NIO/Network types it holds aren't Sendable but are only touched there.
final class FlowMITM: Relay, @unchecked Sendable {
    private let flow: NEAppProxyTCPFlow
    private let queue = DispatchQueue(label: "snap.mitm.flow")
    private let channel: EmbeddedChannel
    private let capture: CaptureHandler
    private let client: NWConnection
    private let log: Logger
    private let onClose: () -> Void
    private let initial: Data
    private let wsParser = WebSocketFrameParser()
    private var clientReady = false
    private var pendingToServer: [Data] = []

    init?(flow: NEAppProxyTCPFlow, host: String, port: UInt16, initial: Data,
          context: NIOSSLContext, log: Logger,
          onServerMessage: @escaping (Data) -> Void,
          onClose: @escaping () -> Void) {
        self.flow = flow
        self.log = log
        self.initial = initial
        self.onClose = onClose
        self.wsParser.onMessage = onServerMessage
        self.capture = CaptureHandler()
        self.channel = EmbeddedChannel()
        do {
            try channel.pipeline.syncOperations.addHandler(NIOSSLServerHandler(context: context))
            try channel.pipeline.syncOperations.addHandler(capture)
            _ = try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        } catch {
            log.error("mitm channel setup failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        // We terminate the game side as HTTP/1.1 (NIOSSL), so force the same
        // upstream to keep the relayed bytes consistent (avoid HTTP/2 mismatch).
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
        client = NWConnection(host: .init(host), port: .init(rawValue: port)!, using: NWParameters(tls: tls))
    }

    func start() {
        capture.onPlaintext = { [weak self] data in self?.gameToServer(data) }
        client.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.queue.async { self.clientReady = true; self.flushToServer(); self.receiveFromServer() }
            case .failed(let error):
                self.log.error("mitm client failed: \(String(describing: error), privacy: .public)")
                self.teardown()
            default:
                break
            }
        }
        client.start(queue: queue)
        queue.async {
            self.processGameBytes(self.initial)   // the ClientHello we already read
            self.readFromGame()
        }
    }

    // Game → us (TLS bytes). Feed NIOSSL, drain its TLS output back to the game.
    private func readFromGame() {
        flow.readData { [weak self] data, error in
            guard let self else { return }
            self.queue.async {
                guard error == nil, let data, !data.isEmpty else { self.teardown(); return }
                self.processGameBytes(data)
                if self.isOpen { self.readFromGame() }
            }
        }
    }

    private func processGameBytes(_ data: Data) {
        guard !data.isEmpty else { return }
        do {
            var buf = channel.allocator.buffer(capacity: data.count)
            buf.writeBytes(data)
            try channel.writeInbound(buf)
            drainToGame()
        } catch {
            log.error("mitm writeInbound failed: \(String(describing: error), privacy: .public)")
            teardown()
        }
    }

    // Decrypted game request → real server.
    private func gameToServer(_ data: Data) {
        guard clientReady else { pendingToServer.append(data); return }
        client.send(content: data, completion: .contentProcessed { _ in })
    }

    private func flushToServer() {
        pendingToServer.forEach { client.send(content: $0, completion: .contentProcessed { _ in }) }
        pendingToServer.removeAll()
    }

    // Server → us (already decrypted by NWConnection). Observe + re-encrypt to game.
    private func receiveFromServer() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let data, !data.isEmpty {
                    self.wsParser.feed(data)
                    var buf = self.channel.allocator.buffer(capacity: data.count)
                    buf.writeBytes(data)
                    _ = try? self.channel.writeAndFlush(buf)
                    self.drainToGame()
                }
                if isComplete || error != nil { self.teardown() } else { self.receiveFromServer() }
            }
        }
    }

    private func drainToGame() {
        while let out = try? channel.readOutbound(as: ByteBuffer.self), out.readableBytes > 0 {
            flow.write(Data(out.readableBytesView)) { _ in }
        }
    }

    private var closed = false
    var isOpen: Bool { !closed }

    private func teardown() {
        guard !closed else { return }
        closed = true
        client.cancel()
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
        _ = try? channel.finish()
        onClose()
    }
}

/// Captures decrypted inbound (game → server) plaintext from the NIOSSL pipeline.
private final class CaptureHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    var onPlaintext: ((Data) -> Void)?
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        onPlaintext?(Data(unwrapInboundIn(data).readableBytesView))
    }
}
