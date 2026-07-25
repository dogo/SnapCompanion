import Foundation

/// A snapshot of what we know about the current match, written for the app.
struct MatchSnapshot: Equatable {
    var opponentName = ""
    var opponentCards: [String] = []
    var locations: [String] = []
    var turn = 0
    var totalTurns = 0
    var cubeValue = 0
    var snaps = 0        // times stakes were raised this match

    var json: Data? {
        try? JSONSerialization.data(withJSONObject: [
            "opponentName": opponentName,
            "opponentCards": opponentCards,
            "locations": locations,
            "turn": turn,
            "totalTurns": totalTurns,
            "cubeValue": cubeValue,
            "snaps": snaps,
        ])
    }
}

/// Parses the game's WebSocket messages (GetChangesResponse changes) into a
/// MatchSnapshot. Swift port + extension of spike/snap_tracker.py.
final class MatchTracker {
    private var me: String?
    private var players: [Int: (account: String?, name: String)] = [:]
    private var cardOwner: [Int: Int] = [:]      // card entityId -> owner (player) entityId
    private var revealed: [Int: String] = [:]    // card entityId -> CardDefId
    private var locations: [Int: String] = [:]   // location entityId -> LocationDefId
    private var cubeValue = 0
    private var snaps = 0
    private var snapshot = MatchSnapshot()

    /// Returns the snapshot if this message changed it.
    func process(_ message: Data) -> MatchSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else { return nil }
        if (obj["$type"] as? String)?.contains("ChangeNotification") == true,
           let account = obj["AccountId"] as? String {
            me = account
        }
        for change in (obj["Changes"] as? [[String: Any]]) ?? [] {
            let type = change["$type"] as? String ?? ""
            if type.contains("GameCreateChange") {
                reset()
                cubeValue = change["StartingCubeValue"] as? Int ?? 1
            } else if type.contains("GameStakesRaisedChange") {
                // A snap: cube escalates (2 → 4 → 8). TotalRaisedCount counts snaps.
                if let cv = change["CubeValue"] as? Int { cubeValue = cv }
                if let n = change["TotalRaisedCount"] as? Int { snaps = n }
            } else if type.contains("GameCreatePlayerChange") {
                if let id = change["EntityId"] as? Int {
                    let info = change["PlayerInfo"] as? [String: Any]
                    players[id] = (info?["AccountId"] as? String, info?["Name"] as? String ?? "")
                }
            } else if type.contains("GameCreateCardChange") {
                if let id = change["EntityId"] as? Int, let owner = change["OwnerEntityId"] as? Int {
                    cardOwner[id] = owner
                }
            } else if type.contains("GameRevealCardChange") {
                if let id = change["EntityId"] as? Int, let def = change["CardDefId"] as? String {
                    revealed[id] = def
                }
            } else if type.contains("GameCreateLocationChange") || type.contains("LocationTransformChange") {
                // Create gives a "RevealOnN" placeholder; Transform gives the real
                // LocationDefId on reveal (and on later transforms). Latest wins.
                if let id = change["EntityId"] as? Int, let def = change["LocationDefId"] as? String {
                    locations[id] = def
                }
            }
        }
        // Turn arrives on various changes; take the latest seen anywhere.
        let ints = Self.scanInts(obj, keys: ["Turn", "TotalTurns"])
        if let turn = ints["Turn"] { snapshot.turn = turn }
        if let total = ints["TotalTurns"] { snapshot.totalTurns = total }

        snapshot.opponentName = opponentName
        snapshot.opponentCards = opponentCards()
        snapshot.locations = locations.sorted { $0.key < $1.key }.map(\.value)
        snapshot.cubeValue = cubeValue
        snapshot.snaps = snaps

        return snapshot
    }

    private func reset() {
        players.removeAll(); cardOwner.removeAll(); revealed.removeAll(); locations.removeAll()
        cubeValue = 0; snaps = 0
        snapshot = MatchSnapshot()
    }

    private var opponentEntity: Int? {
        players.first { $0.value.account != nil && $0.value.account != me }?.key
    }

    private var opponentName: String {
        opponentEntity.flatMap { players[$0]?.name } ?? ""
    }

    private func opponentCards() -> [String] {
        guard let opponent = opponentEntity else { return [] }
        var seen = Set<String>()
        var cards: [String] = []
        for (id, def) in revealed where cardOwner[id] == opponent && seen.insert(def).inserted {
            cards.append(def)
        }
        return cards
    }

    /// Finds the last integer value for each key anywhere in a nested JSON object.
    private static func scanInts(_ any: Any, keys: Set<String>) -> [String: Int] {
        var found: [String: Int] = [:]
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (k, v) in dict {
                    if keys.contains(k), let i = v as? Int { found[k] = i }
                    walk(v)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(any)
        return found
    }
}
