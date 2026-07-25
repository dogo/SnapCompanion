import Foundation

/// Extracts WebSocket message payloads from a server → client byte stream:
/// skips the HTTP 101 upgrade response, then parses frames (server frames are
/// unmasked) and reassembles fragments. Control frames are ignored.
final class WebSocketFrameParser {
    private var buffer = Data()
    private var upgraded = false
    private var fragment = Data()
    var onMessage: ((Data) -> Void)?

    func feed(_ data: Data) {
        buffer.append(data)
        if !upgraded {
            guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
            buffer.removeSubrange(..<range.upperBound)
            upgraded = true
        }
        while parseFrame() {}
    }

    /// Parses one frame from the buffer; returns true if it consumed one.
    private func parseFrame() -> Bool {
        guard buffer.count >= 2 else { return false }
        let b = [UInt8](buffer.prefix(10))
        let fin = b[0] & 0x80 != 0
        let opcode = b[0] & 0x0f
        let masked = b[1] & 0x80 != 0
        var len = Int(b[1] & 0x7f)
        var offset = 2
        if len == 126 {
            guard buffer.count >= 4 else { return false }
            len = Int(b[2]) << 8 | Int(b[3]); offset = 4
        } else if len == 127 {
            guard buffer.count >= 10 else { return false }
            len = 0; for i in 2..<10 { len = len << 8 | Int(b[i]) }; offset = 10
        }
        let maskLen = masked ? 4 : 0
        guard buffer.count >= offset + maskLen + len else { return false }

        var payload = buffer.subdata(in: (offset + maskLen)..<(offset + maskLen + len))
        if masked {
            let mask = [UInt8](buffer.subdata(in: offset..<offset + 4))
            for i in 0..<payload.count { payload[i] ^= mask[i % 4] }
        }
        buffer.removeSubrange(..<(offset + maskLen + len))

        switch opcode {
        case 0x8: return false                 // close
        case 0x9, 0xA: return true             // ping/pong — ignore
        default:
            fragment.append(payload)           // 0 continuation, 1 text, 2 binary
            if fin { onMessage?(fragment); fragment = Data() }
            return true
        }
    }
}
