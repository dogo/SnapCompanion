import Crypto
import Foundation
import os
import X509

/// Per-install MITM certificate material.
///
/// On first use the (root) extension generates a unique CA + leaf, signs the
/// leaf, then **discards the CA private key** — we only ever need one leaf, so
/// nothing can issue further certificates and no CA key persists anywhere. The
/// leaf private key + chain live in the extension's private container (0600);
/// the CA public certificate is also copied to a world-readable path for the
/// one-time trust step. Nothing secret is ever bundled with the app.
enum CertificateStore {
    private static let log = Logger(subsystem: "br.com.anykey.SnapSync.proxy", category: "cert")

    /// World-readable copy of the CA cert, for `security add-trusted-cert`.
    static let publicCAPath = "/tmp/snapcompanion-ca.pem"

    private static let sans = [
        "*.nvprod.snapgametech.com",
        "nvprod.snapgametech.com",
        "*.snapgametech.com",
    ]

    private static var dir: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SnapCompanion", isDirectory: true)
    }
    private static var leafChainURL: URL { dir.appendingPathComponent("leaf-chain.pem") }
    private static var leafKeyURL: URL { dir.appendingPathComponent("leaf.key") }
    private static var caURL: URL { dir.appendingPathComponent("ca.pem") }

    /// Paths to the leaf chain + private key, generating them on first call.
    static func ensure() throws -> (chain: URL, key: URL) {
        let fm = FileManager.default
        if !(fm.fileExists(atPath: leafChainURL.path) && fm.fileExists(atPath: leafKeyURL.path)) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try generate(fm: fm)
            log.info("generated per-install MITM CA + leaf")
        }
        // Always (re)publish the public CA — /tmp is cleared on reboot but the app
        // needs it there to trust the CA even when generation was skipped.
        try? publishPublicCA()
        return (leafChainURL, leafKeyURL)
    }

    private static func publishPublicCA() throws {
        guard let caPEM = try? String(contentsOf: caURL, encoding: .utf8) else { return }
        try write(caPEM, to: URL(fileURLWithPath: publicCAPath), mode: 0o644)
    }

    private static func generate(fm: FileManager) throws {
        let notBefore = Date().addingTimeInterval(-3600)
        let notAfter = Date().addingTimeInterval(10 * 365 * 24 * 3600)

        // CA (self-signed). `caKey` is local and discarded when this returns.
        let caKey = Certificate.PrivateKey(P256.Signing.PrivateKey())
        let caName = try DistinguishedName { CommonName("SnapCompanion Install CA") }
        let ca = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: caKey.publicKey,
            notValidBefore: notBefore, notValidAfter: notAfter,
            issuer: caName, subject: caName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
                Critical(KeyUsage(keyCertSign: true))
            },
            issuerPrivateKey: caKey
        )

        // Leaf for the game's realtime hosts, signed by the CA.
        let leafKey = P256.Signing.PrivateKey()
        let leafCertKey = Certificate.PrivateKey(leafKey)
        let leafName = try DistinguishedName { CommonName("*.nvprod.snapgametech.com") }
        let leaf = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: leafCertKey.publicKey,
            notValidBefore: notBefore, notValidAfter: notAfter,
            issuer: caName, subject: leafName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                KeyUsage(digitalSignature: true, keyEncipherment: true)
                try ExtendedKeyUsage([.serverAuth])
                SubjectAlternativeNames(sans.map { .dnsName($0) })
            },
            issuerPrivateKey: caKey
        )

        let caPEM = try ca.serializeAsPEM().pemString
        let chainPEM = try leaf.serializeAsPEM().pemString + "\n" + caPEM
        try write(chainPEM, to: leafChainURL, mode: 0o600)
        try write(leafKey.pemRepresentation, to: leafKeyURL, mode: 0o600)
        try write(caPEM, to: caURL, mode: 0o644)
        // The public CA is exposed at publicCAPath by ensure() → publishPublicCA().
    }

    private static func write(_ pem: String, to url: URL, mode: Int) throws {
        try Data((pem + "\n").utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
}
