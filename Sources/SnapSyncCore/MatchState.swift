import Foundation

/// Live match state read from `GameState.json`.
///
/// ponytail: GameState.json persists after a match ends, so this reflects the
/// latest match, not necessarily one in progress. Match start/end detection is
/// a later slice.
public struct MatchState: Sendable, Equatable {
    public let turn: Int
    public let totalTurns: Int
    public let cubeValue: Int
    public let cardsPlayed: [String]
    public let cardsDrawn: [String]
    public let result: MatchResult?     // present once the match has ended

    public init(turn: Int, totalTurns: Int, cubeValue: Int,
                cardsPlayed: [String], cardsDrawn: [String], result: MatchResult? = nil) {
        self.turn = turn
        self.totalTurns = totalTurns
        self.cubeValue = cubeValue
        self.cardsPlayed = cardsPlayed
        self.cardsDrawn = cardsDrawn
        self.result = result
    }

    public static func read(from source: SnapSource) -> MatchState? {
        let url = source.url.appendingPathComponent("GameState.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> MatchState? {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) } // UTF-8 BOM
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let remote = root["RemoteGame"] as? [String: Any],
              let game = remote["GameState"] as? [String: Any] else { return nil }
        let player = remote["ClientPlayerInfo"] as? [String: Any]
        return MatchState(
            turn: game["Turn"] as? Int ?? 0,
            totalTurns: game["TotalTurns"] as? Int ?? 0,
            cubeValue: game["CubeValue"] as? Int ?? 0,
            cardsPlayed: cards(player?["CardsPlayed"]),
            cardsDrawn: cards(player?["CardsDrawn"]),
            result: result(game: game, myAccount: player?["AccountId"] as? String)
        )
    }

    /// Reads the end-of-match result for the local player from `ClientResultMessage`,
    /// matching the account item by the client's own AccountId. Nil mid-match.
    private static func result(game: [String: Any], myAccount: String?) -> MatchResult? {
        guard let message = game["ClientResultMessage"] as? [String: Any],
              let items = message["GameResultAccountItems"] as? [[String: Any]] else { return nil }
        let mine = items.first { ($0["AccountId"] as? String) == myAccount } ?? items.first
        guard let mine else { return nil }
        let cubes = message["FinalCubeValue"] as? Int ?? mine["FinalCubeValue"] as? Int ?? 0
        return MatchResult(didWin: mine["IsWinner"] as? Bool ?? false, cubes: cubes)
    }

    private static func cards(_ value: Any?) -> [String] {
        (value as? [String])?.filter { $0 != "None" } ?? []
    }
}

/// End-of-match outcome for the local player. `cubes` is the stake magnitude;
/// the sign is implied by `didWin` (won +cubes / lost −cubes).
public struct MatchResult: Sendable, Equatable {
    public let didWin: Bool
    public let cubes: Int

    public init(didWin: Bool, cubes: Int) {
        self.didWin = didWin
        self.cubes = cubes
    }
}
