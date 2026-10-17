import Foundation

/// A snapshot of what we know about the current match, written for the app.
public struct MatchSnapshot: Equatable, Sendable {
    public var opponentName = ""
    public var opponentCards: [String] = []
    public var opponentDeckCards: [String] = []   // revealed cards that started in their deck (no generated cards)
    public var locations: [String] = []
    public var locationPowers: [[Int]] = []   // [you, opponent] per location, same order; empty until calibrated
    public var turn = 0
    public var totalTurns = 0
    public var cubeValue = 0
    public var snaps = 0        // players who snapped (excludes the automatic final-turn doubling)
    public var youSnapped = false
    public var opponentSnapped = false
    public var result: MatchResult?   // set the moment the server reports the outcome

    public var json: Data? {
        let result = result.flatMap { try? JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        return try? JSONSerialization.data(withJSONObject: [
            "opponentName": opponentName,
            "opponentCards": opponentCards,
            "opponentDeckCards": opponentDeckCards,
            "locations": locations,
            "locationPowers": locationPowers,
            "turn": turn,
            "totalTurns": totalTurns,
            "cubeValue": cubeValue,
            "snaps": snaps,
            "youSnapped": youSnapped,
            "opponentSnapped": opponentSnapped,
            "result": result ?? NSNull(),
        ])
    }
}

/// Parses the game's WebSocket messages (GetChangesResponse changes) into a
/// MatchSnapshot. Swift port + extension of spike/snap_tracker.py.
public final class MatchTracker {
    private var me: String?
    private var players: [Int: (account: String?, name: String)] = [:]
    private var cardOwner: [Int: Int] = [:]      // card entityId -> owner (player) entityId
    private var revealed: [Int: String] = [:]    // card entityId -> CardDefId
    private var generated: Set<Int> = []         // card entityIds created mid-match by a card/location/effect
    private var snappers: Set<Int> = []          // player entityIds that raised the stakes
    private var locations: [Int: String] = [:]   // location entityId -> LocationDefId
    private var powers: [Int: (p1: Int, p2: Int)] = [:]  // location entityId -> Player1/Player2 power
    private var iAmPlayer1: Bool?                // learned from a location's winner; nil until known
    private var cubeValue = 0
    private var snapshot = MatchSnapshot()

    public init() {}

    /// Returns the snapshot if this message changed it.
    public func process(_ message: Data) -> MatchSnapshot? {
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
                // Cube escalates (2 → 4 → 8). TotalRaisedCount also counts the automatic final-turn
                // doubling, so snaps are counted per player from snappers instead.
                if let cv = change["CubeValue"] as? Int { cubeValue = cv }
            } else if type.contains("GameCreatePlayerChange") {
                if let id = change["EntityId"] as? Int {
                    let info = change["PlayerInfo"] as? [String: Any]
                    players[id] = (info?["AccountId"] as? String, (info?["Name"] as? String ?? "").trimmingCharacters(in: .whitespaces))
                }
            } else if type.contains("GameCreateCardChange") {
                if let id = change["EntityId"] as? Int, let owner = change["OwnerEntityId"] as? Int {
                    cardOwner[id] = owner
                }
            } else if type.contains("GameRevealCardChange") {
                if let id = change["EntityId"] as? Int, let def = change["CardDefId"] as? String {
                    revealed[id] = def
                    // Created* is null for cards that started in the deck (field names from IL2CPP metadata).
                    let creators = ["CreatedByCardDefId", "CreatedByLocationDefId", "CreatedByFactionDefId"]
                    if creators.contains(where: { (change[$0] as? String).map { !$0.isEmpty && $0 != "None" } ?? false }) {
                        generated.insert(id)
                    }
                }
            } else if type.contains("GameResultChange") {
                // Message may arrive as an object or as embedded JSON text.
                let message = change["Message"] as? [String: Any]
                    ?? (change["Message"] as? String).flatMap {
                        try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
                    }
                snapshot.result = message.flatMap { MatchResult.parse(message: $0, myAccount: me) }
            } else if type.contains("PlayerStakesRaisedChange") || type.contains("GameRaiseStakesForNextTurnChange") {
                if let player = change["PlayerEntityId"] as? Int { snappers.insert(player) }
            } else if type.contains("GameCreateLocationChange") || type.contains("LocationTransformChange") {
                // Create gives a "RevealOnN" placeholder; Transform gives the real
                // LocationDefId on reveal (and on later transforms). Latest wins.
                if let id = change["EntityId"] as? Int, let def = change["LocationDefId"] as? String {
                    locations[id] = def
                }
            }
        }
        for change in (obj["Changes"] as? [[String: Any]]) ?? [] {
            let type = change["$type"] as? String ?? ""
            guard type.contains("LocationPowerTotalsChange") || type.contains("GameCreateLocationChange"),
                  let id = change["EntityId"] as? Int else { continue }
            // The game omits zero-valued fields, so a missing power means 0.
            let p1 = change["Player1Power"] as? Int ?? 0, p2 = change["Player2Power"] as? Int ?? 0
            powers[id] = (p1, p2)
            // Player1/Player2 isn't tied to an account in the payload; the leading side's winner tells us which we are.
            if let winner = change["WinnerEntityId"] as? Int, let mine = myEntity, p1 != p2,
               players[winner] != nil {
                iAmPlayer1 = (winner == mine) == (p1 > p2)
            }
        }
        // Turn arrives on various changes; take the latest seen anywhere.
        let ints = Self.scanInts(obj, keys: ["Turn", "TotalTurns"])
        if let turn = ints["Turn"] { snapshot.turn = turn }
        if let total = ints["TotalTurns"] { snapshot.totalTurns = total }

        snapshot.opponentName = opponentName
        snapshot.opponentCards = opponentCards()
        snapshot.opponentDeckCards = opponentCards(excludingGenerated: true)
        snapshot.locations = locations.sorted { $0.key < $1.key }.map(\.value)
        snapshot.locationPowers = iAmPlayer1.map { first in
            locations.keys.sorted().map { id in
                let power = powers[id] ?? (0, 0)
                return first ? [power.p1, power.p2] : [power.p2, power.p1]
            }
        } ?? []
        snapshot.cubeValue = cubeValue
        snapshot.snaps = snappers.count
        snapshot.youSnapped = myEntity.map(snappers.contains) ?? false
        snapshot.opponentSnapped = opponentEntity.map(snappers.contains) ?? false

        return snapshot
    }

    private func reset() {
        players.removeAll(); cardOwner.removeAll(); revealed.removeAll(); generated.removeAll()
        snappers.removeAll(); locations.removeAll(); powers.removeAll(); iAmPlayer1 = nil
        cubeValue = 0
        snapshot = MatchSnapshot()
    }

    private var opponentEntity: Int? {
        players.first { $0.value.account != nil && $0.value.account != me }?.key
    }

    private var myEntity: Int? {
        players.first { $0.value.account != nil && $0.value.account == me }?.key
    }

    private var opponentName: String {
        opponentEntity.flatMap { players[$0]?.name } ?? ""
    }

    private func opponentCards(excludingGenerated: Bool = false) -> [String] {
        guard let opponent = opponentEntity else { return [] }
        var seen = Set<String>()
        var cards: [String] = []
        for (id, def) in revealed.sorted(by: { $0.key < $1.key })
            where cardOwner[id] == opponent && !(excludingGenerated && generated.contains(id)) && seen.insert(def).inserted {
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
