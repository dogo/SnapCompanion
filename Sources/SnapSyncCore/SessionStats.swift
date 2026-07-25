import Foundation

/// Per-deck record for the current session.
public struct DeckStat: Sendable, Equatable, Identifiable {
    public let deck: String
    public var games: Int
    public var wins: Int
    public var cubes: Int    // net cubes this session (won − lost)

    public var id: String { deck }
    public var losses: Int { games - wins }
    public var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
}

/// Aggregates finished-match results per deck for the current app session.
/// In-memory only — session stats reset when the app relaunches (no database).
public struct SessionStats: Sendable, Equatable {
    private var byDeck: [String: DeckStat] = [:]
    private var seenGames: Set<String> = []

    public init() {}

    /// Records a finished match, once per `gameId`. Returns true if it counted.
    @discardableResult
    public mutating func record(_ result: MatchResult) -> Bool {
        guard !result.gameId.isEmpty, seenGames.insert(result.gameId).inserted else { return false }
        let deck = result.deck.isEmpty ? "Unknown" : result.deck
        var stat = byDeck[deck] ?? DeckStat(deck: deck, games: 0, wins: 0, cubes: 0)
        stat.games += 1
        stat.wins += result.didWin ? 1 : 0
        stat.cubes += result.didWin ? result.cubes : -result.cubes
        byDeck[deck] = stat
        return true
    }

    /// Decks by most-played, then name.
    public var decks: [DeckStat] {
        byDeck.values.sorted { $0.games != $1.games ? $0.games > $1.games : $0.deck < $1.deck }
    }
    public var totalGames: Int { byDeck.values.reduce(0) { $0 + $1.games } }
    public var totalWins: Int { byDeck.values.reduce(0) { $0 + $1.wins } }
    public var totalCubes: Int { byDeck.values.reduce(0) { $0 + $1.cubes } }
    public var isEmpty: Bool { byDeck.isEmpty }
}
