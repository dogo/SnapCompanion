import Foundation
import NetworkExtension
import os
import SystemExtensions

/// Spike driver: activates the system extension and starts the transparent
/// proxy so we can confirm the extension intercepts the Marvel Snap process.
final class ProxyController: NSObject, ObservableObject, @unchecked Sendable {
    static let extensionBundleId = "br.com.anykey.SnapSync.proxy"
    private let log = Logger(subsystem: "br.com.anykey.SnapSync", category: "proxy")
    @Published private(set) var status = "idle"

    func activate() {
        setStatus("activating extension…")
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.extensionBundleId, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.status = text }
        log.info("proxy status: \(text, privacy: .public)")
    }

    private func startProxy() {
        NETransparentProxyManager.loadAllFromPreferences { managers, error in
            if let error { self.setStatus("load failed: \(error.localizedDescription)"); return }
            let manager = managers?.first ?? NETransparentProxyManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.extensionBundleId
            proto.serverAddress = "127.0.0.1"
            manager.protocolConfiguration = proto
            manager.localizedDescription = "SnapCompanion Proxy"
            manager.isEnabled = true
            manager.saveToPreferences { error in
                if let error { self.setStatus("save failed: \(error.localizedDescription)"); return }
                manager.loadFromPreferences { _ in
                    do {
                        try manager.connection.startVPNTunnel()
                        self.setStatus("proxy running")
                    } catch {
                        self.setStatus("start failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

extension ProxyController: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        setStatus("approve the extension in System Settings › Login Items & Extensions")
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        setStatus("extension activated (result \(result.rawValue))")
        startProxy()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        setStatus("extension failed: \(error.localizedDescription)")
    }
}
