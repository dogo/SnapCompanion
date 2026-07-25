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

    public init(turn: Int, totalTurns: Int, cubeValue: Int, cardsPlayed: [String], cardsDrawn: [String]) {
        self.turn = turn
        self.totalTurns = totalTurns
        self.cubeValue = cubeValue
        self.cardsPlayed = cardsPlayed
        self.cardsDrawn = cardsDrawn
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
            cardsDrawn: cards(player?["CardsDrawn"])
        )
    }

    private static func cards(_ value: Any?) -> [String] {
        (value as? [String])?.filter { $0 != "None" } ?? []
    }
}
