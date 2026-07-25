import Foundation
import NIOSSL

/// Builds the NIOSSL server context used to terminate the game's TLS with our
/// bundled leaf. ponytail: dev-only bundled key; a shipped build must generate
/// a unique CA per install so the private key isn't extractable from the app.
enum MITMContext {
    static func makeServerContext() -> NIOSSLContext? {
        guard let chainURL = Bundle.main.url(forResource: "leaf-chain", withExtension: "pem"),
              let keyURL = Bundle.main.url(forResource: "leaf", withExtension: "key") else { return nil }
        do {
            let chain = try NIOSSLCertificate.fromPEMFile(chainURL.path)
                .map { NIOSSLCertificateSource.certificate($0) }
            let key = try NIOSSLPrivateKey(file: keyURL.path, format: .pem)
            var config = TLSConfiguration.makeServerConfiguration(
                certificateChain: chain,
                privateKey: .privateKey(key)
            )
            config.applicationProtocols = ["http/1.1"]
            return try NIOSSLContext(configuration: config)
        } catch {
            return nil
        }
    }
}
