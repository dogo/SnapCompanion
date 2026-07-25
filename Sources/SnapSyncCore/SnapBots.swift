import Foundation

public enum BotStatus: String, Sendable {
    case human
    case bot        // name matches a known AI list
    case lstmBot    // name matches the LSTM bot list
}

/// Known bot name lists from MarvelSnap.pro (do.php?cmd=getbots), used to flag
/// AI opponents by exact nickname match — the same logic the official tracker uses.
public struct BotIndex: Sendable {
    private let lstm: Set<String>
    private let others: Set<String>

    public init(lstm: [String], human: [String], marvel: [String], realPlayers: [String]) {
        self.lstm = Set(lstm)
        self.others = Set(human).union(marvel).union(realPlayers)
    }

    public func status(for nick: String) -> BotStatus {
        guard nick.count > 2 else { return .human }
        if lstm.contains(nick) { return .lstmBot }
        if others.contains(nick) { return .bot }
        return .human
    }
}

/// Loads and caches the bot name lists.
public actor SnapBots {
    public static let shared = SnapBots()
    private static var cacheURL: URL { URL.applicationSupportDirectory.appending(path: "SnapSync/bots.json") }

    private let load: @Sendable (URLRequest) async throws -> Data
    public init() {
        load = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, 200...299 ~= response.statusCode else {
                throw SnapSyncError.invalidResponse("bots request failed")
            }
            return data
        }
    }

    init(load: @escaping @Sendable (URLRequest) async throws -> Data) { self.load = load }

    public func index(now: Date = .now) async throws -> BotIndex {
        let modified = (try? Self.cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if now.timeIntervalSince(modified) < 86_400, let cached = try? Data(contentsOf: Self.cacheURL) {
            return try decode(cached)
        }
        let url = URL(string: "https://static2.marvelsnap.pro/snap/do.php?cmd=getbots")!
        let data = try await load(URLRequest(url: url))
        try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.cacheURL)
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> BotIndex {
        let remote = try JSONDecoder().decode(RemoteBots.self, from: data)
        return BotIndex(
            lstm: remote.HiddenAiLSTMNames ?? [],
            human: remote.HiddenAiHumanNames ?? [],
            marvel: remote.HiddenAiMarvelNames ?? [],
            realPlayers: remote.HiddenAiRealPlayerNames ?? []
        )
    }

    private struct RemoteBots: Decodable {
        let HiddenAiHumanNames: [String]?
        let HiddenAiLSTMNames: [String]?
        let HiddenAiMarvelNames: [String]?
        let HiddenAiRealPlayerNames: [String]?
    }
}
