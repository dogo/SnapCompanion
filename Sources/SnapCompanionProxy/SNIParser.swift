import Foundation

/// Extracts the SNI server name from a TLS ClientHello. The flow only gives us
/// the destination IP, so we read the hostname the game intends from its first
/// packet to decide whether to MITM and what SNI to present upstream.
enum SNIParser {
    static func hostname(_ data: Data) -> String? {
        let b = [UInt8](data)
        var i = 0
        func u8() -> Int? { guard i < b.count else { return nil }; defer { i += 1 }; return Int(b[i]) }
        func u16() -> Int? { guard let h = u8(), let l = u8() else { return nil }; return h << 8 | l }

        guard b.count > 5, b[0] == 0x16 else { return nil }   // TLS handshake record
        i = 5                                                 // skip record header
        guard u8() == 0x01 else { return nil }                // ClientHello
        i += 3                                                // handshake length
        i += 2 + 32                                           // client version + random
        guard let sidLen = u8() else { return nil }; i += sidLen
        guard let csLen = u16() else { return nil }; i += csLen
        guard let compLen = u8() else { return nil }; i += compLen
        guard u16() != nil else { return nil }                // extensions total length

        while i + 4 <= b.count {
            guard let type = u16(), let len = u16() else { return nil }
            if type == 0x0000 {                               // server_name
                guard u16() != nil, u8() == 0 else { return nil } // list length + name type=host
                guard let nameLen = u16(), i + nameLen <= b.count else { return nil }
                return String(bytes: b[i..<i + nameLen], encoding: .utf8)
            }
            i += len
        }
        return nil
    }
}
