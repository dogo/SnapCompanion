import Foundation

/// Loads MarvelSnap.pro meta archetypes (do.php?cmd=getmeta), cached for a day.
public actor MetaArchetypes {
    public static let shared = MetaArchetypes()
    public nonisolated static var defaultCacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "SnapSync/meta-archetypes.json")
    }

    private let cacheURL: URL
    private let load: @Sendable (URLRequest) async throws -> Data

    public init() {
        cacheURL = Self.defaultCacheURL
        load = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, 200...299 ~= response.statusCode else {
                throw SnapSyncError.invalidResponse("meta request failed")
            }
            return data
        }
    }

    init(cacheURL: URL, load: @escaping @Sendable (URLRequest) async throws -> Data) {
        self.cacheURL = cacheURL
        self.load = load
    }

    public func archetypes(now: Date = .now) async throws -> [MetaArchetype] {
        if let cached = loadCache(), now.timeIntervalSince(cached.fetchedAt) < 86_400 {
            return cached.archetypes
        }
        do {
            let remote = try JSONDecoder().decode(RemoteMeta.self, from: try await load(request()))
            let archetypes = remote.archetypes.map { a in
                MetaArchetype(
                    name: a.name,
                    supertype: a.supertype ?? "",
                    decksCount: Int(a.decks_count ?? "") ?? 0,
                    cards: (a.structure ?? []).compactMap { c in
                        c.CardDefId.map { .init(id: $0, weight: Double(c.weight ?? "") ?? 0) }
                    }
                )
            }
            guard archetypes.isEmpty == false else {
                throw SnapSyncError.invalidResponse("meta is empty")
            }
            try? save(Cache(fetchedAt: now, archetypes: archetypes))
            return archetypes
        } catch {
            if let cached = loadCache() { return cached.archetypes }
            throw error
        }
    }

    private func request() throws -> URLRequest {
        guard let url = URL(string: "https://marvelsnap.pro/snap/do.php?cmd=getmeta") else {
            throw SnapSyncError.invalidResponse("meta URL is invalid")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func loadCache() -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private func save(_ cache: Cache) throws {
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
    }

    private struct Cache: Codable { let fetchedAt: Date; let archetypes: [MetaArchetype] }

    private struct RemoteMeta: Decodable { let archetypes: [RemoteArchetype] }
    private struct RemoteArchetype: Decodable {
        let name: String
        let supertype: String?
        let decks_count: String?
        let structure: [RemoteCard]?
    }
    private struct RemoteCard: Decodable { let CardDefId: String?; let weight: String? }
}
