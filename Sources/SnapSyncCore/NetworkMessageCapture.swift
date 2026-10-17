import CoreFoundation
import Foundation

/// Bounded, local protocol diagnostics. Only explicit game fields retain values.
/// Lock protects admission; the queue owns the file and all writes.
public final class NetworkMessageCapture: @unchecked Sendable {
    public let url: URL
    private let expiresAt: Date
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "snap.network.capture", qos: .utility)
    private var remainingInputBytes = 8 * 1024 * 1024
    private var remainingOutputBytes = 8 * 1024 * 1024
    private var file: FileHandle?
    private var accountAliases: [String: String] = [:]

    private static let gameNumbers: Set<String> = [
        "EntityId", "OwnerEntityId", "CardEntityId", "CardOwnerEntityId", "PlayerEntityId",
        "StartedInDeckEntityId", "DeckEntityId", "HandEntityId", "GraveyardEntityId", "BanishedEntityId",
        "CreatedByPlayerEntityId", "OverrideAbilityFromPlayerEntityId",
        "ZoneEntityId", "TargetZoneEntityId", "FromZoneEntityId", "ToZoneEntityId", "TargetEntityId",
        "LocationEntityId", "WinnerEntityId", "WinnerId", "TargetEntityIds", "EntityIds",
        "Turn", "TotalTurns", "TurnsTaken", "LocationSlot", "ZonePosition", "TargetZonePosition", "CardZonePosition",
        "CurrentEnergy", "DefaultEnergy", "EnergySpent", "Cost", "Power", "Player1Power", "Player2Power",
        "CubeValue", "CubeValueNextTurn", "StartingCubeValue", "FinalCubeValue", "TotalRaisedCount",
        "TimeRemainingMilliseconds", "RequestId", "Index", "Count", "ChangeCount",
        "HighWatermarkRank", "CollectionScore", "Rank", "SnapPoints", "CardsDestroyed",
        "InfiniteLeaderboardSkillRating", "InfiniteLeaderboardStanding",
    ]
    private static let gameStrings: Set<String> = [
        "CardDefId", "LocationDefId", "StartedInDeckEntityId", "OverrideAbilityCardDefId",
        "CreatedByCardDefId", "CreatedByLocationDefId", "CreatedByFactionDefId",
        "CardDefIdUpdator",
        "CardDefIdsDrawn", "CardDefIdsPlayed", "LocationDefIdsAtEndOfGame",
        "AiConfigDefId", "AiPlayDefId", "NoStageOptionReason", "CollectionPrivacy",
    ]
    private static let gameFlags: Set<String> = [
        "IsWinner", "IsLoser", "Conceded", "OpponentConceded", "AllTurnsPlayed", "Accepted",
        "CanUndoEndTurn", "CanRaiseStakes", "IsPlayable", "IsAi", "IsBot", "Tie",
        "CanBeDestroyed", "CanBeDiscarded", "CanBeMovedToLocation", "CanHaveCostIncreased",
        "CanHaveCostReduced", "CanHavePowerReduced", "CanActivate", "ActivateUndoable",
    ]
    // Generic VFX field names must only retain values inside their declared game types.
    private static let effectStrings: [String: Set<String>] = [
        "CubeGame.VfxChange": ["Type", "DefType", "EntityId"],
        "CubeGame.VfxChangeItem": ["Key"],
        "CubeGame.VfxString": ["String"],
        "CubeGame.VfxListStrings": ["Strings"],
    ]

    public init(directory: URL, expiresAt: Date, ownerID: UInt32) throws {
        self.expiresAt = expiresAt
        guard mkdir(directory.path, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        url = directory.appendingPathComponent("messages.jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
        try FileManager.default.setAttributes([.ownerAccountID: ownerID], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.ownerAccountID: ownerID], ofItemAtPath: directory.path)
    }

    public func record(_ message: Data, direction: String, connection: String) {
        guard message.count <= 2 * 1024 * 1024 else { return }
        let accepted = lock.withLock {
            guard Date() < expiresAt, message.count < remainingInputBytes else { return false }
            remainingInputBytes -= max(1, message.count)
            return true
        }
        guard accepted else { return }
        let receivedAt = Date().timeIntervalSince1970
        queue.async { [self] in
            guard let file,
                  let object = try? JSONSerialization.jsonObject(with: message, options: [.fragmentsAllowed]) else { return }
            do {
                let record: [String: Any] = [
                    "timestamp": receivedAt, "direction": direction, "connection": connection,
                    "bytes": message.count, "captureFormat": 3, "shape": shape(object, depth: 0),
                ]
                var line = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                line.append(0x0a)
                guard line.count <= remainingOutputBytes else { return }
                remainingOutputBytes -= line.count
                try file.write(contentsOf: line)
            } catch {
                try? file.close()
                self.file = nil
            }
        }
    }

    public func finish() {
        lock.withLock { remainingInputBytes = 0 }
        queue.sync {
            try? file?.close()
            file = nil
        }
    }

    private func shape(_ value: Any, key: String = "", type: String = "", depth: Int) -> Any {
        if ["token", "password", "authorization", "credential", "secret", "cookie"]
            .contains(where: key.lowercased().contains) { return "<redacted>" }
        guard depth < 24 else { return "<depth-limit>" }
        if let object = value as? [String: Any] {
            var fields: [String: Any] = [:]
            let objectType = (object["$type"] as? String)?.components(separatedBy: ",").first ?? ""
            for (index, entry) in object.sorted(by: { $0.key < $1.key }).enumerated() {
                let (key, value) = entry
                let field = key.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]{0,79}$"#,
                                      options: .regularExpression) != nil ? key : "<dynamic-key-\(index)>"
                if key == "$type", let type = value as? String, type.count <= 160,
                   type.range(of: #"^(CubeGame\.|CubeMatchmaker\.)[A-Za-z0-9_.]+(, [A-Za-z0-9_.]+)?$|^[A-Za-z_][A-Za-z0-9_]*(Change|Request|Response|Notification)$"#,
                              options: .regularExpression) != nil {
                    fields[field] = type
                } else {
                    fields[field] = shape(value, key: key, type: objectType, depth: depth + 1)
                }
            }
            return fields
        }
        if let array = value as? [Any] { return array.map { shape($0, key: key, type: type, depth: depth + 1) } }
        if value is NSNull { return NSNull() }
        if let string = value as? String {
            if ["AccountId", "SenderAccountId"].contains(key) {
                if accountAliases[string] == nil { accountAliases[string] = "account-\(accountAliases.count + 1)" }
                return accountAliases[string] ?? "<account>"
            }
            if ["$id", "$ref"].contains(key),
               string.range(of: #"^[0-9]{1,12}$"#, options: .regularExpression) != nil { return string }
            if Self.gameStrings.contains(key) || Self.effectStrings[type]?.contains(key) == true, string.count <= 128,
               string.range(of: #"^[A-Za-z0-9_.:-]*$"#, options: .regularExpression) != nil { return string }
            if let embedded = string.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: embedded),
               object is [String: Any] || object is [Any] {
                return shape(object, depth: depth + 1)
            }
            return "<string>"
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return Self.gameFlags.contains(key) ? number : "<boolean>"
            }
            let effectNumber = (type == "CubeGame.VfxNumber" && key == "Number")
                || (type == "CubeGame.CardStatUpdate" && key == "Value")
            return Self.gameNumbers.contains(key) || effectNumber ? number : "<number>"
        }
        return "<unknown>"
    }
}
