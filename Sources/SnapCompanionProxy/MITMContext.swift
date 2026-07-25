import Foundation
import NIOSSL

/// Builds the NIOSSL server context used to terminate the game's TLS. The leaf
/// chain + key are generated per install by `CertificateStore` (never bundled).
enum MITMContext {
    static func makeServerContext() -> NIOSSLContext? {
        do {
            let (chainURL, keyURL) = try CertificateStore.ensure()
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
