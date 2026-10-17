import Foundation

/// Per-deck record.
public struct DeckStat: Sendable, Equatable, Identifiable, Codable {
    public let deck: String
    public var games: Int
    public var wins: Int
    public var cubes: Int    // net cubes this session (won − lost)
    public var retreats = 0           // games you retreated
    public var opponentRetreats = 0   // games the opponent retreated
    public var botGames = 0

    public var id: String { deck }
    public var losses: Int { games - wins }
    public var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }

    public init(deck: String, games: Int, wins: Int, cubes: Int) {
        self.deck = deck
        self.games = games
        self.wins = wins
        self.cubes = cubes
    }

    // Stats saved before retreat/bot tracking lack those keys; default them so history isn't dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deck = try c.decode(String.self, forKey: .deck)
        games = try c.decode(Int.self, forKey: .games)
        wins = try c.decode(Int.self, forKey: .wins)
        cubes = try c.decode(Int.self, forKey: .cubes)
        retreats = try c.decodeIfPresent(Int.self, forKey: .retreats) ?? 0
        opponentRetreats = try c.decodeIfPresent(Int.self, forKey: .opponentRetreats) ?? 0
        botGames = try c.decodeIfPresent(Int.self, forKey: .botGames) ?? 0
    }
}

/// Aggregates finished-match results per deck. Persisted to a private JSON file
/// so per-deck history survives app relaunches (no database). Dedup by `gameId`
/// carries across relaunches via the stored `seenGames`.
public struct SessionStats: Sendable, Equatable, Codable {
    private var byDeck: [String: DeckStat] = [:]
    // ponytail: seenGames grows one entry per game forever; a personal match log
    // stays tiny for years. Cap it (keep last N) only if the JSON ever gets large.
    private var seenGames: Set<String> = []

    public init() {}

    public static var defaultURL: URL {
        SyncCheckpoint.defaultURL
            .deletingLastPathComponent()
            .appendingPathComponent("deck-stats.json")
    }

    /// Loads persisted stats, or empty stats if absent/unreadable.
    public static func load(from url: URL = defaultURL) -> SessionStats {
        guard FileManager.default.fileExists(atPath: url.path) else { return SessionStats() }
        do {
            try securePrivateFile(at: url)
            return try JSONDecoder().decode(SessionStats.self, from: Data(contentsOf: url))
        } catch {
            return SessionStats()
        }
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try securePrivateFile(at: url)
    }

    public static func clear(at url: URL = defaultURL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Records a finished match, once per `gameId`. Returns true if it counted.
    @discardableResult
    public mutating func record(_ result: MatchResult) -> Bool {
        guard !result.gameId.isEmpty, seenGames.insert(result.gameId).inserted else { return false }
        let deck = result.deck.isEmpty ? "Unknown" : result.deck
        var stat = byDeck[deck] ?? DeckStat(deck: deck, games: 0, wins: 0, cubes: 0)
        stat.games += 1
        stat.wins += result.didWin ? 1 : 0
        stat.cubes += result.didWin ? result.cubes : -result.cubes
        stat.retreats += result.retreat == .you ? 1 : 0
        stat.opponentRetreats += result.retreat == .opponent ? 1 : 0
        stat.botGames += result.vsBot ? 1 : 0
        byDeck[deck] = stat
        return true
    }

    public enum Sort: Sendable { case games, winRate, cubes, name }

    /// Decks sorted by the chosen metric (descending), ties broken by name.
    public func decks(by sort: Sort = .games) -> [DeckStat] {
        byDeck.values.sorted { a, b in
            switch sort {
            case .games: return a.games != b.games ? a.games > b.games : a.deck < b.deck
            case .winRate: return a.winRate != b.winRate ? a.winRate > b.winRate : a.deck < b.deck
            case .cubes: return a.cubes != b.cubes ? a.cubes > b.cubes : a.deck < b.deck
            case .name: return a.deck < b.deck
            }
        }
    }

    /// Decks by most-played, then name.
    public var decks: [DeckStat] { decks(by: .games) }
    public var totalGames: Int { byDeck.values.reduce(0) { $0 + $1.games } }
    public var totalWins: Int { byDeck.values.reduce(0) { $0 + $1.wins } }
    public var totalCubes: Int { byDeck.values.reduce(0) { $0 + $1.cubes } }
    public var totalRetreats: Int { byDeck.values.reduce(0) { $0 + $1.retreats } }
    public var totalOpponentRetreats: Int { byDeck.values.reduce(0) { $0 + $1.opponentRetreats } }
    public var totalBotGames: Int { byDeck.values.reduce(0) { $0 + $1.botGames } }
    public var isEmpty: Bool { byDeck.isEmpty }
}
