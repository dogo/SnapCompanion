import Foundation
import os
import Security

/// Trusts the extension's per-install MITM CA. The extension (sandboxed) can't
/// modify the trust store, and modifying the *admin/system* store needs root, so
/// the app — running as the user — adds the CA to the **user** trust domain via
/// an in-process Security call. The game runs as the same user and honors it.
/// One login-keychain prompt, replacing the manual `sudo security add-trusted-cert`.
enum CATrust {
    /// Written by the extension (`CertificateStore.publicCAPath`) on first run.
    static let caPath = "/tmp/snapcompanion-ca.pem"
    private static let log = Logger(subsystem: "br.com.anykey.SnapSync", category: "catrust")
    private static let lock = NSLock()   // serialize triggers so we prompt at most once

    /// Waits for the freshly generated CA and, if not trusted yet, adds it as a
    /// trusted root in the **user** trust domain — an in-process Security call the
    /// app can make as the user (no root, no subprocess). The game runs as the
    /// same user, so its trust evaluation honors it. May pop one login-keychain
    /// prompt. Safe to call repeatedly; call off the main thread.
    static func ensureTrusted() {
        lock.lock(); defer { lock.unlock() }
        guard let cert = waitForCert() else { log.error("CA cert never appeared"); return }
        if isTrusted(cert) { return }
        let status = SecTrustSettingsSetTrustSettings(cert, .user, nil)   // nil ⇒ trust root
        log.info("set user trust settings -> \(status, privacy: .public)")
    }

    private static func waitForCert(timeout: TimeInterval = 15) -> SecCertificate? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let cert = loadCert() { return cert }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return nil
    }

    private static func loadCert() -> SecCertificate? {
        guard let pem = try? String(contentsOfFile: caPath, encoding: .utf8),
              let der = derBytes(fromPEM: pem) else { return nil }
        return SecCertificateCreateWithData(nil, der as CFData)
    }

    private static func isTrusted(_ cert: SecCertificate) -> Bool {
        var settings: CFArray?
        return SecTrustSettingsCopyTrustSettings(cert, .user, &settings) == errSecSuccess
    }

    private static func derBytes(fromPEM pem: String) -> Data? {
        let body = pem.split(whereSeparator: \.isNewline)
            .filter { !$0.contains("-----") }
            .joined()
        return Data(base64Encoded: body)
    }
}
