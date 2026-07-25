import Foundation
import Testing
import zlib
@testable import SnapSyncCore

extension Tag {
    @Tag static var networking: Self
}

private enum HTTPStub: Sendable {
    case response(status: Int, headers: [String: String], body: [String: String])
    case failure(URLError.Code)
}

private actor HTTPRecorder {
    private var stubs: [HTTPStub]
    private(set) var requests: [URLRequest] = []
    private(set) var delays: [Duration] = []

    init(responses: [[String: String]]) {
        stubs = responses.map { .response(status: 200, headers: [:], body: $0) }
    }

    init(stubs: [HTTPStub]) {
        self.stubs = stubs
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard stubs.isEmpty == false, let url = request.url else {
            throw URLError(.badServerResponse)
        }
        requests.append(request)
        switch stubs.removeFirst() {
        case .failure(let code):
            throw URLError(code)
        case .response(let status, let headers, let body):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: headers
            ) else {
                throw URLError(.badServerResponse)
            }
            return (try JSONEncoder().encode(body), response)
        }
    }

    func record(delay: Duration) {
        delays.append(delay)
    }
}

private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private func gunzip(_ input: Data) throws -> Data {
    var stream = z_stream()
    let initialized = inflateInit2_(
        &stream,
        MAX_WBITS + 16,
        ZLIB_VERSION,
        Int32(MemoryLayout<z_stream>.size)
    )
    guard initialized == Z_OK else { throw URLError(.cannotDecodeRawData) }
    defer { inflateEnd(&stream) }

    return try input.withUnsafeBytes { inputBytes in
        stream.next_in = UnsafeMutablePointer(mutating: inputBytes.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(input.count)
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 32_768)
        let bufferSize = buffer.count
        var status: Int32

        repeat {
            status = buffer.withUnsafeMutableBytes { outputBytes in
                stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(bufferSize)
                return inflate(&stream, Z_NO_FLUSH)
            }
            guard status == Z_OK || status == Z_STREAM_END else { throw URLError(.cannotDecodeRawData) }
            result.append(contentsOf: buffer.prefix(bufferSize - Int(stream.avail_out)))
        } while status != Z_STREAM_END

        return result
    }
}

struct SnapSyncTests {
    @Test func doctorReportIsSanitized() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"AccountId":"account-1","ServerState":{"Account":{"Id":"account-1","Name":"Private Player"}}}"#.utf8)
            .write(to: directory.appendingPathComponent("ProfileState.json"))
        try Data(#"{"ServerState":{"Cards":[],"Decks":[{"Id":"deck-1","Name":"Secret Deck","Cards":[]}]}}"#.utf8)
            .write(to: directory.appendingPathComponent("CollectionState.json"))

        let report = SnapDoctor.report(
            source: try SnapSource.inspect(at: directory),
            tokenAvailable: true,
            checkpointURL: directory.appendingPathComponent("checkpoint.json"),
            outboxURL: directory.appendingPathComponent("outbox.json")
        )

        #expect(report.contains("Overall: READY"))
        #expect(report.contains("Schema V1 recognized"))
        #expect(report.contains("0 cards · 0 variants"))
        #expect(report.contains("1 decks"))
        #expect(report.contains(directory.path) == false)
        #expect(report.contains("Private Player") == false)
        #expect(report.contains("account-1") == false)
        #expect(report.contains("Secret Deck") == false)
    }

    @Test func securityScopedBookmarkRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let selectedFolder = directory.appendingPathComponent("nvprod")
        let bookmarkURL = directory.appendingPathComponent("folder.bookmark")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)

        try FolderBookmarkStore.saveAccess(to: selectedFolder, at: bookmarkURL)
        let restored = try #require(try FolderBookmarkStore.restoreURL(from: bookmarkURL))

        #expect(restored.resolvingSymlinksInPath() == selectedFolder.resolvingSymlinksInPath())
        let attributes = try FileManager.default.attributesOfItem(atPath: bookmarkURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try FolderBookmarkStore.clear(at: bookmarkURL)
        #expect(try FolderBookmarkStore.restoreURL(from: bookmarkURL) == nil)
    }

    @Test(.tags(.networking))
    func synchronizerPersistsSuccessAndSkipsTheSameSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"AccountId":"account-1","ServerState":{"Account":{"Id":"account-1","Name":"Test Player"}}}"#.utf8)
            .write(to: directory.appendingPathComponent("ProfileState.json"))
        try Data(#"{"ServerState":{"Cards":[],"Decks":[]}}"#.utf8)
            .write(to: directory.appendingPathComponent("CollectionState.json"))
        let source = try SnapSource.inspect(at: directory)
        let recorder = HTTPRecorder(responses: [["status": "OK"], ["status": "DONE"]])
        let synchronizer = SnapSynchronizer(
            client: MarvelSnapProClient(load: { try await recorder.load($0) }),
            loadToken: { "secret" },
            checkpointURL: directory.appendingPathComponent("checkpoint.json"),
            outboxURL: directory.appendingPathComponent("outbox/latest.json")
        )

        #expect(try await synchronizer.synchronize(source) == .synchronized("DONE"))
        #expect(try await synchronizer.synchronize(source) == .unchanged)
        #expect(await recorder.requests.count == 2)
        #expect(try SyncOutbox.load(from: directory.appendingPathComponent("outbox/latest.json")) == nil)
    }

    @Test func outboxKeepsOnlyTheLatestSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("outbox/latest.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = [MarvelSnapProEvent(time: 0, indicator: "Collection", json: "[]", uid: "account-1")]
        let latest = [MarvelSnapProEvent(time: 0, indicator: "Collection", json: "[{}]", uid: "account-1")]

        try SyncOutbox.save(first, to: url, now: Date(timeIntervalSince1970: 0))
        try SyncOutbox.save(latest, to: url, now: Date(timeIntervalSince1970: 1))

        #expect(try SyncOutbox.load(from: url) == latest)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try SyncOutbox.remove(at: url)
        #expect(try SyncOutbox.load(from: url) == nil)
    }

    @Test(.tags(.networking))
    func retriesTransientFailuresAndHonorsRetryAfter() async throws {
        let recorder = HTTPRecorder(stubs: [
            .failure(.timedOut),
            .response(
                status: 429,
                headers: ["Retry-After": "Thu, 01 Jan 1970 00:00:02 GMT"],
                body: [:]
            ),
            .response(status: 200, headers: [:], body: ["status": "OK"]),
        ])
        let client = MarvelSnapProClient(
            load: { try await recorder.load($0) },
            retryDelays: [.seconds(1), .seconds(3)],
            sleep: { await recorder.record(delay: $0) },
            now: { Date(timeIntervalSince1970: 0) }
        )

        #expect(try await client.validate(token: "secret") == "OK")
        let requests = await recorder.requests
        let delays = await recorder.delays
        #expect(requests.count == 3)
        #expect(delays == [.seconds(1), .seconds(2)])
    }

    @Test(.tags(.networking))
    func doesNotRetryAuthenticationFailure() async {
        let recorder = HTTPRecorder(stubs: [
            .response(status: 401, headers: [:], body: [:]),
            .response(status: 200, headers: [:], body: ["status": "OK"]),
        ])
        let client = MarvelSnapProClient(
            load: { try await recorder.load($0) },
            retryDelays: [.zero],
            sleep: { await recorder.record(delay: $0) }
        )

        do {
            _ = try await client.validate(token: "secret")
            Issue.record("Expected HTTP 401")
        } catch SnapSyncError.httpStatus(let status) {
            #expect(status == 401)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        let requests = await recorder.requests
        #expect(requests.count == 1)
    }

    @Test(.tags(.networking))
    func stopsRetryingWhenBackoffIsCancelled() async {
        let recorder = HTTPRecorder(stubs: [
            .failure(.timedOut),
            .response(status: 200, headers: [:], body: ["status": "OK"]),
        ])
        let client = MarvelSnapProClient(
            load: { try await recorder.load($0) },
            retryDelays: [.zero],
            sleep: { _ in throw CancellationError() }
        )

        await #expect(throws: CancellationError.self) {
            _ = try await client.validate(token: "secret")
        }
        let requests = await recorder.requests
        #expect(requests.count == 1)
    }

    @Test func directoryMonitorEmitsAChange() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let changes = try DirectoryMonitor.changes(at: directory)
        let observed = Task {
            for await _ in changes { return true }
            return false
        }
        defer { observed.cancel() }

        try Data("changed".utf8).write(to: directory.appendingPathComponent("CollectionState.json"))

        let didObserveChange = await observed.value
        #expect(didObserveChange)
    }

    @Test func debouncerRunsOnlyTheLatestPendingAction() async {
        let debouncer = ChangeDebouncer()
        let counter = Counter()
        let first = await debouncer.schedule(after: .seconds(60)) { await counter.increment() }
        let last = await debouncer.schedule(after: .zero) { await counter.increment() }

        await first.value
        await last.value
        let count = await counter.value
        #expect(count == 1)
    }

    @Test func stableReaderRetriesAfterAFileReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("CollectionState.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: url)
        var reads = 0

        let data = try StableFileReader.read(from: url, attempts: 2, retryDelay: 0) { attempt in
            reads += 1
            if attempt == 0 { try Data("updated".utf8).write(to: url, options: .atomic) }
        }

        #expect(data == Data("updated".utf8))
        #expect(reads == 2)
    }

    @Test func checkpointMatchesOnlyTheLastSuccessfulSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("checkpoint.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = [MarvelSnapProEvent(time: 0, indicator: "Collection", json: "[]", uid: "account-1")]
        let changed = [MarvelSnapProEvent(time: 0, indicator: "Collection", json: "[{}]", uid: "account-1")]

        #expect(try SyncCheckpoint.matches(original, at: url) == false)
        try SyncCheckpoint.save(original, to: url, now: Date(timeIntervalSince1970: 0))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(try SyncCheckpoint.matches(original, at: url))
        #expect(try SyncCheckpoint.matches(changed, at: url) == false)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try SyncCheckpoint.clear(at: url)
        #expect(try SyncCheckpoint.matches(original, at: url) == false)
    }

    @Test func discoversReadsAndExportsCurrentSchema() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let sourceURL = home.appendingPathComponent(
            "Library/Containers/snap/Data/Documents/Standalone/States/nvprod",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        for name in ["ProfileState", "CollectionState"] {
            let fixture = try #require(
                Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/V1")
            )
            try FileManager.default.copyItem(
                at: fixture,
                to: sourceURL.appendingPathComponent("\(name).json")
            )
        }

        let source = try #require(SnapSource.discover(home: home).first)
        let snapshot = try SnapshotIO.read(from: source, now: Date(timeIntervalSince1970: 0))
        let antMan = try #require(snapshot.collection.first { $0.definitionID == "AntMan" })

        #expect(snapshot.schemaVersion == SnapSchema.v1.rawValue)
        #expect(SnapSchema.v1.fingerprint == "CollectionState.ServerState.{Cards,Decks}")
        #expect(snapshot.account?.displayName == "Fixture Player")
        #expect(snapshot.collection.count == 2)
        #expect(antMan.variants.count == 2)
        #expect(antMan.boosters == 12)
        #expect(snapshot.decks.count == 1)
        #expect(snapshot.decks.first?.cardDefinitionIDs == ["AntMan", "Hulk"])
        #expect(snapshot.inventory.collectionLevel == 321)
        #expect(snapshot.inventory.credits == 1200)
        #expect(snapshot.inventory.gold == 300)
        #expect(snapshot.inventory.collectorsTokens == 700)
        #expect(snapshot.inventory.wildBoosters == 25)

        let output = home.appendingPathComponent("snapshot.json")
        try SnapshotIO.write(snapshot, to: output)
        #expect(FileManager.default.fileExists(atPath: output.path))

        let events = try MarvelSnapProPayload.events(from: source)
        let decks = try #require(events.first { $0.indicator == "Decks" })
        let collection = try #require(events.first { $0.indicator == "Collection" })
        #expect(MarvelSnapProPayload.uploadEndpoint() == "https://marvelsnap.pro/snap/donew2.php?cmd=cm_uploadpackfile&version=0.4.0m")
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.time == 0 && $0.uid == "fixture-account" })
        #expect(decks.json.contains(#""TimeUpdated":"2026-07-23T12:00:00Z""#))
        #expect(collection.json.contains(#""ArtVariantDefId":"Variant""#))
    }

    @Test func historyKeepsTheLastCollectionOrDeckChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let historyURL = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let inventory = SnapSnapshot.Inventory(
            collectionLevel: 10,
            credits: 100,
            gold: 20,
            collectorsTokens: 30,
            wildBoosters: 5
        )
        let account = SnapSnapshot.Account(id: "account-1", displayName: "Test Player")
        let baseline = SnapSnapshot(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 0),
            applicationVersion: "1.0",
            account: account,
            collection: [
                SnapSnapshot.OwnedCard(
                    definitionID: "AntMan",
                    variants: [SnapSnapshot.Variant(id: "card-1", variantID: "Base", rarityID: nil, borderID: nil)],
                    boosters: 10
                )
            ],
            decks: [
                SnapSnapshot.Deck(
                    id: "deck-1",
                    name: "Starter",
                    cardDefinitionIDs: ["AntMan"],
                    lastModifiedAt: nil
                )
            ],
            inventory: inventory
        )
        let changed = SnapSnapshot(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 1),
            applicationVersion: "1.0",
            account: account,
            collection: [
                SnapSnapshot.OwnedCard(
                    definitionID: "AntMan",
                    variants: [
                        SnapSnapshot.Variant(id: "card-1", variantID: "Base", rarityID: nil, borderID: nil),
                        SnapSnapshot.Variant(id: "card-2", variantID: "Variant", rarityID: nil, borderID: nil),
                    ],
                    boosters: 20
                ),
                SnapSnapshot.OwnedCard(
                    definitionID: "Hulk",
                    variants: [SnapSnapshot.Variant(id: "card-3", variantID: nil, rarityID: nil, borderID: nil)],
                    boosters: 5
                ),
            ],
            decks: [
                SnapSnapshot.Deck(
                    id: "deck-1",
                    name: "Starter",
                    cardDefinitionIDs: ["AntMan", "Hulk"],
                    lastModifiedAt: nil
                )
            ],
            inventory: inventory
        )

        #expect(try SnapshotHistoryStore.record(baseline, at: historyURL) == nil)
        let change = try #require(try SnapshotHistoryStore.record(changed, at: historyURL))
        #expect(change.newCards == 1)
        #expect(change.newVariants == 1)
        #expect(change.changedDecks == 1)

        let resourceOnlyChange = SnapSnapshot(
            schemaVersion: changed.schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 2),
            applicationVersion: changed.applicationVersion,
            account: changed.account,
            collection: changed.collection.map {
                SnapSnapshot.OwnedCard(
                    definitionID: $0.definitionID,
                    variants: $0.variants,
                    boosters: ($0.boosters ?? 0) + 10
                )
            },
            decks: changed.decks,
            inventory: SnapSnapshot.Inventory(
                collectionLevel: 11,
                credits: 90,
                gold: 20,
                collectorsTokens: 30,
                wildBoosters: 5
            )
        )
        #expect(try SnapshotHistoryStore.record(resourceOnlyChange, at: historyURL) == change)
        #expect(try SnapshotHistoryStore.lastChange(at: historyURL) == change)
        let attributes = try FileManager.default.attributesOfItem(atPath: historyURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try SnapshotHistoryStore.clear(at: historyURL)
        #expect(try SnapshotHistoryStore.lastChange(at: historyURL) == nil)
    }

    @Test func unknownSchemaBlocksUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"AccountId":"fixture-account"}"#.utf8)
            .write(to: directory.appendingPathComponent("ProfileState.json"))
        try Data(#"{"ServerState":{"CardsV2":[],"DecksV2":[]}}"#.utf8)
            .write(to: directory.appendingPathComponent("CollectionState.json"))

        do {
            _ = try MarvelSnapProPayload.events(from: SnapSource.inspect(at: directory))
            Issue.record("Expected an unsupported schema error")
        } catch SnapSyncError.unsupportedSchema(let file, let reason) {
            #expect(file == "CollectionState.json")
            #expect(reason.contains("fingerprint does not match V1"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func collectionQueryMatchesNamesWithSpaces() {
        let results = CollectionQuery.results(
            in: queryCards,
            searchText: "ant man",
            filter: .all,
            sort: .nameAscending
        )

        #expect(results.map(\.id) == ["AntMan"])
    }

    @Test func collectionQueryFiltersVariantsAndBoosters() {
        let variants = CollectionQuery.results(
            in: queryCards,
            searchText: "",
            filter: .withVariants,
            sort: .nameAscending
        )
        let withoutBoosters = CollectionQuery.results(
            in: queryCards,
            searchText: "",
            filter: .withoutBoosters,
            sort: .nameAscending
        )
        let withBoosters = CollectionQuery.results(
            in: queryCards,
            searchText: "",
            filter: .withBoosters,
            sort: .nameAscending
        )

        #expect(variants.map(\.id) == ["AntMan", "BlueMarvel"])
        #expect(withBoosters.map(\.id) == ["AntMan", "BlueMarvel"])
        #expect(withoutBoosters.map(\.id) == ["Hulk"])
    }

    @Test func collectionQuerySortsByVariantsAndBoosters() {
        let variants = CollectionQuery.results(
            in: queryCards,
            searchText: "",
            filter: .all,
            sort: .mostVariants
        )
        let boosters = CollectionQuery.results(
            in: queryCards,
            searchText: "",
            filter: .all,
            sort: .mostBoosters
        )
        let namesDescending = CollectionQuery.results(
            in: queryCards,
            searchText: "",
            filter: .all,
            sort: .nameDescending
        )

        #expect(variants.map(\.id) == ["BlueMarvel", "AntMan", "Hulk"])
        #expect(boosters.map(\.id) == ["AntMan", "BlueMarvel", "Hulk"])
        #expect(namesDescending.map(\.id) == ["Hulk", "BlueMarvel", "AntMan"])
    }

    @Test func collectionQueryFiltersOwnedAndMissingCards() {
        let cards = CollectionQuery.cards(
            owned: collectionCards,
            catalog: [
                CardCatalogEntry(id: "AntMan", name: "Ant Man"),
                CardCatalogEntry(id: "Galactus", name: "Galactus"),
            ]
        )
        let owned = CollectionQuery.results(
            in: cards,
            searchText: "",
            filter: .owned,
            sort: .nameAscending
        )
        let missing = CollectionQuery.results(
            in: cards,
            searchText: "",
            filter: .missing,
            sort: .nameAscending
        )

        #expect(owned.map(\.id) == ["AntMan", "BlueMarvel", "Hulk"])
        #expect(missing.map(\.id) == ["Galactus"])
    }

    @Test func matchStateParsesTurnCubesAndCardsIgnoringBOMAndNone() {
        let json = """
        {"RemoteGame":{"GameState":{"Turn":3,"TotalTurns":6,"CubeValue":2},\
        "ClientPlayerInfo":{"CardsPlayed":["Wong","Agony"],\
        "CardsDrawn":["Wong","None","Agony","None","BlackPanther"]}}}
        """
        var data = Data([0xEF, 0xBB, 0xBF]) // UTF-8 BOM prefix
        data.append(Data(json.utf8))

        let match = MatchState.parse(data)

        #expect(match?.turn == 3)
        #expect(match?.totalTurns == 6)
        #expect(match?.cubeValue == 2)
        #expect(match?.cardsPlayed == ["Wong", "Agony"])
        #expect(match?.cardsDrawn == ["Wong", "Agony", "BlackPanther"])
        #expect(MatchState.parse(Data("not json".utf8)) == nil)
    }

    @Test func deckPredictorRanksByCoverageAndListsRemaining() {
        let wongSurfer = MetaArchetype(name: "Wong Surfer", supertype: "Ongoing", decksCount: 40, cards: [
            .init(id: "Wong", weight: 1), .init(id: "Odin", weight: 1), .init(id: "SilverSurfer", weight: 0.9),
            .init(id: "Sera", weight: 0.8), .init(id: "Ironheart", weight: 0.5),
        ])
        let destroy = MetaArchetype(name: "Arnim Knull", supertype: "Destroy", decksCount: 300, cards: [
            .init(id: "ArnimZola", weight: 1), .init(id: "Knull", weight: 1), .init(id: "Wong", weight: 0.3),
        ])

        // "Token" isn't in any archetype and must be dropped from matching.
        let result = DeckPredictor.predict(
            revealed: ["Wong", "Odin", "Ironheart", "Token"],
            archetypes: [destroy, wongSurfer]
        )

        #expect(result.first?.archetype.name == "Wong Surfer")     // covers 3 vs 1
        #expect(result.first?.matched == ["Ironheart", "Odin", "Wong"])
        #expect(result.first?.remaining == ["SilverSurfer", "Sera"]) // unrevealed, weight desc
        #expect((result.first?.confidence ?? 0) > 0.8)              // dominates the evidence

        // One common card (Wong is in both archetypes) is less certain than three.
        let weak = DeckPredictor.predict(revealed: ["Wong"], archetypes: [destroy, wongSurfer])
        #expect((weak.first?.confidence ?? 1) < (result.first?.confidence ?? 0))
    }

    @Test func botIndexFlagsKnownNamesByExactMatch() {
        let index = BotIndex(lstm: ["RoboFoe"], human: ["FakeGuy"], marvel: ["IronDupe"], realPlayers: [])
        #expect(index.status(for: "RoboFoe") == .lstmBot)
        #expect(index.status(for: "FakeGuy") == .bot)
        #expect(index.status(for: "IronDupe") == .bot)
        #expect(index.status(for: "RealHuman") == .human)
        #expect(index.status(for: "ab") == .human) // names of 2 or fewer chars are ignored
    }

    @Test(.tags(.networking))
    func cardCatalogFiltersAndCachesThePublicCatalog() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cacheURL = directory.appendingPathComponent("catalog.json")
        let counter = Counter()
        defer { try? FileManager.default.removeItem(at: directory) }
        let response = Data(#"""
        [
            {"id":"AntMan","name":"Ant Man","collectible":"1","source":"Recruit Season"},
            {"id":"AdamantiumInfusion","name":"Adamantium Infusion","collectible":"1","source":"Pool 5"},
            {"id":"Token","name":"Token","collectible":"1","source":"None"},
            {"id":"Hulk","name":"Hulk","collectible":"0","source":"Starter Card"}
        ]
        """#.utf8)
        let catalog = CardCatalog(cacheURL: cacheURL) { request in
            await counter.increment()
            #expect(request.url?.host == "api.dotgg.gg")
            return response
        }
        let now = Date(timeIntervalSince1970: 100_000)

        let fetched = try await catalog.entries(now: now)
        let cached = try await catalog.entries(now: now.addingTimeInterval(3_600))
        let requestCount = await counter.value

        #expect(fetched.map(\.id) == ["AdamantiumInfusion", "AntMan"])
        #expect(cached == fetched)
        #expect(requestCount == 1)
    }

    @Test(.tags(.networking))
    func linksAccountWithoutLiveNetwork() async throws {
        let recorder = HTTPRecorder(responses: [
            ["mode": "needauth", "request": "request-1"],
            ["uid": "42", "token": "secret", "nick": "Test Pro"],
            ["status": "OK", "data": ""],
        ])
        let client = MarvelSnapProClient(load: { try await recorder.load($0) })
        let utc = try #require(TimeZone(secondsFromGMT: 0))

        let connection = try await client.connectAccount(
            screenName: "Test Player",
            accountID: "account-1",
            timeZone: utc
        ) { url in
            #expect(url.absoluteString == "https://marvelsnap.pro/sync/?request=request-1")
        }

        #expect(connection.credential == MarvelSnapProCredential(userID: "42", token: "secret", nickname: "Test Pro"))
        #expect(connection.status == "OK")

        let requests = await recorder.requests
        #expect(requests.count == 3)
        #expect(requests.compactMap(\.url?.query).contains("cmd=cm_tokenrequest&version=0.4.0m"))
        let association = try #require(requests.last?.httpBody)
        let body = try JSONDecoder().decode([String: String].self, from: association)
        #expect(body == ["snapId": "account-1", "snapNick": "Test Player", "token": "secret", "usertime": "0"])
    }

    @Test(.tags(.networking))
    func validatesAndUploadsGzipPayloadWithoutLiveNetwork() async throws {
        let recorder = HTTPRecorder(responses: [
            ["status": "OK", "data": ""],
            ["status": "DONE"],
        ])
        let client = MarvelSnapProClient(load: { try await recorder.load($0) })
        let event = MarvelSnapProEvent(time: 0, indicator: "Decks", json: "[]", uid: "account-1")
        let utc = try #require(TimeZone(secondsFromGMT: 0))

        #expect(try await client.validate(token: "secret", timeZone: utc) == "OK")
        #expect(try await client.upload([event]) == "DONE")

        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests.last?.url?.query == "cmd=cm_uploadpackfile&version=0.4.0m")
        let encodedBody = try #require(requests.last?.httpBody)
        let compressed = try #require(Data(base64Encoded: encodedBody))
        let decodedEvents = try JSONDecoder().decode([MarvelSnapProEvent].self, from: gunzip(compressed))
        #expect(decodedEvents == [event])
    }

    private var collectionCards: [SnapSnapshot.OwnedCard] {
        [
            ownedCard("AntMan", variants: 2, boosters: 12),
            ownedCard("BlueMarvel", variants: 3, boosters: 5),
            ownedCard("Hulk", variants: 1, boosters: nil),
        ]
    }

    private var queryCards: [CollectionCard] {
        CollectionQuery.cards(owned: collectionCards, catalog: [])
    }

    private func ownedCard(_ definitionID: String, variants: Int, boosters: Int?) -> SnapSnapshot.OwnedCard {
        SnapSnapshot.OwnedCard(
            definitionID: definitionID,
            variants: (0..<variants).map {
                SnapSnapshot.Variant(id: "\(definitionID)-\($0)", variantID: nil, rarityID: nil, borderID: nil)
            },
            boosters: boosters
        )
    }
}
