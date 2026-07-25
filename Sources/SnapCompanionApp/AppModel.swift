import AppKit
import Combine
import Foundation
import OSLog
import SnapSyncCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusText = String(localized: .statusLocatingSnap)
    @Published private(set) var accountName = "—"
    @Published private(set) var collection: [SnapSnapshot.OwnedCard] = []
    @Published private(set) var decks: [SnapSnapshot.Deck] = []
    @Published private(set) var cardCount = 0
    @Published private(set) var variantCount = 0
    @Published private(set) var deckCount = 0
    @Published private(set) var collectionLevel: Int?
    @Published private(set) var credits: Int?
    @Published private(set) var gold: Int?
    @Published private(set) var collectorsTokens: Int?
    @Published private(set) var wildBoosters: Int?
    @Published private(set) var boosterCount = 0
    @Published private(set) var lastChange: SnapshotHistoryStore.Change?
    @Published private(set) var sourcePath = "—"
    @Published private(set) var isConnecting = false
    @Published private(set) var isLinked = false
    @Published private(set) var isSyncing = false
    @Published private(set) var hasError = false
    @Published private(set) var match: MatchState?
    @Published private(set) var opponentCards: [String] = []
    @Published private(set) var opponentName = ""
    @Published private(set) var botStatus: BotStatus = .human
    @Published private(set) var matchTurn = 0
    @Published private(set) var matchTotalTurns = 0
    @Published private(set) var matchCubeValue = 0
    @Published private(set) var matchSnaps = 0
    @Published private(set) var locations: [String] = []
    @Published private(set) var deckPredictions: [DeckPrediction] = []
    @Published private(set) var isOverlayVisible = false
    private var archetypes: [MetaArchetype] = []
    private var botIndex: BotIndex?
    @Published var automaticSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticSyncEnabled, forKey: Self.automaticSyncKey)
            startAutomaticSync()
        }
    }

    var canConnect: Bool { source != nil }
    var canSync: Bool { source != nil && isLinked }

    private var source: SnapSource?
    private var scopedURL: URL?
    private var monitorTask: Task<Void, Never>?
    private var overlay: MatchOverlayController?
    private var matchTimer: Timer?
    let proxy = ProxyController()
    private var proxyObservation: AnyCancellable?
    private let synchronizer: SnapSynchronizer
    private static let automaticSyncKey = "automaticSyncEnabled"

    init(synchronizer: SnapSynchronizer = SnapSynchronizer()) {
        self.synchronizer = synchronizer
        automaticSyncEnabled = UserDefaults.standard.object(forKey: Self.automaticSyncKey) as? Bool ?? true
        // The menu observes AppModel; forward the nested proxy's changes so its
        // status label refreshes.
        proxyObservation = proxy.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func load() {
        isLinked = (try? KeychainTokenStore.load()) != nil

        if let bookmarkedURL = try? FolderBookmarkStore.restoreURL(),
           (try? loadSource(at: bookmarkedURL)) != nil {
            showReady()
            startAutomaticSync()
            return
        }

        do {
            guard let source = SnapSource.discover().first else {
                throw SnapSyncError.sourceNotFound
            }
            try loadSource(at: source.url)
            showReady()
            startAutomaticSync()
        } catch {
            show(error)
        }
    }

    func selectFolder(_ url: URL) {
        do {
            try loadSource(at: url, saveBookmark: true)
            showReady()
            startAutomaticSync()
        } catch {
            show(error)
        }
    }

    func synchronize() async {
        guard let source, isSyncing == false, isConnecting == false else { return }
        isSyncing = true
        statusText = String(localized: .statusSyncing)
        hasError = false
        defer { isSyncing = false }

        do {
            let refreshedSource = try SnapSource.inspect(at: source.url)
            let snapshot = try SnapshotIO.read(from: refreshedSource)
            update(snapshot, source: refreshedSource)
            switch try await synchronizer.synchronize(refreshedSource) {
            case .unchanged:
                statusText = String(localized: .statusUpToDate)
            case .synchronized:
                statusText = String(localized: .statusSyncedAt(Date.now.formatted(date: .omitted, time: .shortened)))
            }
        } catch is CancellationError {
            statusText = String(localized: .statusSyncCancelled)
        } catch {
            show(error)
        }
    }

    func connect() async {
        guard let source, isConnecting == false, isSyncing == false else { return }
        isConnecting = true
        statusText = String(localized: .statusConnecting)
        hasError = false
        defer { isConnecting = false }

        do {
            let snapshot = try SnapshotIO.read(from: source)
            guard let account = snapshot.account,
                  let screenName = account.displayName,
                  screenName.isEmpty == false else {
                throw SnapSyncError.unsupportedSchema(
                    file: "ProfileState.json",
                    reason: String(localized: .accountMissingReason)
                )
            }

            let connection = try await MarvelSnapProClient().connectAccount(
                screenName: screenName,
                accountID: account.id
            ) { url in
                try await self.openConfirmationPage(url)
            }
            try KeychainTokenStore.save(connection.credential.token)
            isLinked = true
            statusText = String(localized: .statusConnectedAs(connection.credential.nickname))
            startAutomaticSync()
        } catch is CancellationError {
            statusText = String(localized: .statusConnectionCancelled)
        } catch {
            show(error)
        }
    }

    func disconnect() {
        guard isConnecting == false, isSyncing == false else { return }
        do {
            try KeychainTokenStore.delete()
            isLinked = false
            startAutomaticSync()
            statusText = String(localized: .statusDisconnected)
            hasError = false
        } catch {
            show(error)
        }
    }

    func clearLocalData() {
        guard isConnecting == false, isSyncing == false else { return }
        monitorTask?.cancel()
        monitorTask = nil

        do {
            try FolderBookmarkStore.clear()
            try SyncCheckpoint.clear()
            try SyncOutbox.remove()
            try SnapshotHistoryStore.clear()
            try CardCatalog.clear()
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = nil
            source = nil
            accountName = "—"
            collection = []
            decks = []
            cardCount = 0
            variantCount = 0
            deckCount = 0
            collectionLevel = nil
            credits = nil
            gold = nil
            collectorsTokens = nil
            wildBoosters = nil
            boosterCount = 0
            lastChange = nil
            sourcePath = "—"
            statusText = String(localized: .statusLocalDataRemoved)
            hasError = false
        } catch {
            show(error)
            startAutomaticSync(synchronizeImmediately: false)
        }
    }

    private func update(_ snapshot: SnapSnapshot, source: SnapSource) {
        self.source = source
        accountName = snapshot.account?.displayName ?? String(localized: .unknownAccount)
        collection = snapshot.collection
        decks = snapshot.decks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cardCount = collection.count
        variantCount = collection.reduce(0) { $0 + $1.variants.count }
        deckCount = decks.count
        collectionLevel = snapshot.inventory.collectionLevel
        credits = snapshot.inventory.credits
        gold = snapshot.inventory.gold
        collectorsTokens = snapshot.inventory.collectorsTokens
        wildBoosters = snapshot.inventory.wildBoosters
        boosterCount = collection.compactMap(\.boosters).reduce(0, +)
        do {
            lastChange = try SnapshotHistoryStore.record(snapshot)
        } catch {
            Logger(subsystem: "com.snapsync", category: "history").error("History update failed")
        }
        sourcePath = source.url.path
    }

    private func loadSource(at url: URL, saveBookmark: Bool = false) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            let source = try SnapSource.inspect(at: url)
            let snapshot = try SnapshotIO.read(from: source)
            if saveBookmark { try FolderBookmarkStore.saveAccess(to: url) }
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = accessed ? url : nil
            update(snapshot, source: source)
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func showReady() {
        statusText = String(localized: isLinked ? .statusReady : .statusConnectAccount)
        hasError = false
    }

    private func startAutomaticSync(synchronizeImmediately: Bool = true) {
        monitorTask?.cancel()
        monitorTask = nil
        guard automaticSyncEnabled, isLinked, let source else { return }

        monitorTask = Task { [weak self] in
            do {
                let changes = try DirectoryMonitor.changes(at: source.url)
                let debouncer = ChangeDebouncer()
                if synchronizeImmediately {
                    await self?.synchronize()
                }

                for await _ in changes {
                    await debouncer.schedule { [weak self] in
                        await self?.synchronize()
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.show(error)
            }
        }
    }

    func toggleOverlay() {
        isOverlayVisible ? hideOverlay() : showOverlay()
    }

    private func showOverlay() {
        guard source != nil else { return }
        loadArchetypes()
        refreshMatch()
        let controller = MatchOverlayController(model: self)
        controller.show()
        overlay = controller
        isOverlayVisible = true
        matchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMatch() }
        }
    }

    private func hideOverlay() {
        matchTimer?.invalidate()
        matchTimer = nil
        overlay?.close()
        overlay = nil
        isOverlayVisible = false
    }

    private func refreshMatch() {
        if let source {
            let latest = MatchState.read(from: source)
            if latest != match { match = latest }
        }
        // Live match snapshot written by the proxy system extension.
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/snapcompanion-live-match.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        matchTurn = obj["turn"] as? Int ?? 0
        matchTotalTurns = obj["totalTurns"] as? Int ?? 0
        matchCubeValue = obj["cubeValue"] as? Int ?? 0
        matchSnaps = obj["snaps"] as? Int ?? 0
        locations = obj["locations"] as? [String] ?? []
        let name = obj["opponentName"] as? String ?? ""
        if name != opponentName {
            opponentName = name
            botStatus = botIndex?.status(for: name) ?? .human
        }
        let cards = obj["opponentCards"] as? [String] ?? []
        guard cards != opponentCards else { return }
        opponentCards = cards
        deckPredictions = archetypes.isEmpty ? [] : DeckPredictor.predict(revealed: cards, archetypes: archetypes)
    }

    private func loadArchetypes() {
        if archetypes.isEmpty {
            Task { [weak self] in
                let loaded = (try? await MetaArchetypes.shared.archetypes()) ?? []
                await MainActor.run { self?.archetypes = loaded }
            }
        }
        if botIndex == nil {
            Task { [weak self] in
                let index = try? await SnapBots.shared.index()
                await MainActor.run { self?.botIndex = index }
            }
        }
    }

    private func openConfirmationPage(_ url: URL) throws {
        statusText = String(localized: .statusConfirmBrowser)
        guard NSWorkspace.shared.open(url) else {
            throw SnapSyncError.invalidArguments(String(localized: .errorOpenConfirmation))
        }
    }

    private func show(_ error: Error) {
        statusText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        hasError = true
    }

    deinit {
        monitorTask?.cancel()
        scopedURL?.stopAccessingSecurityScopedResource()
    }
}
