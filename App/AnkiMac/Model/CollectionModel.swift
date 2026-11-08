import AnkiKit
import AppKit
import Foundation
import Observation

/// One deck in the sidebar, flattened from the backend's `DeckTreeNode`.
nonisolated struct DeckNode: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let newCount: Int
    let learnCount: Int
    let reviewCount: Int
    let collapsed: Bool
    let filtered: Bool
    /// nil for a leaf, so `List` shows no disclosure triangle.
    let children: [DeckNode]?

    var dueCount: Int { newCount + learnCount + reviewCount }

    init(_ node: Anki_Decks_DeckTreeNode) {
        id = node.deckID
        name = node.name
        newCount = Int(node.newCount)
        learnCount = Int(node.learnCount)
        reviewCount = Int(node.reviewCount)
        collapsed = node.collapsed
        filtered = node.filtered
        children = node.children.isEmpty ? nil : node.children.map(DeckNode.init)
    }
}

nonisolated struct CollectionPaths: Sendable {
    let collection: URL
    let mediaFolder: URL
    let mediaDB: URL

    /// `-CollectionPath /path/to/collection.anki2` on the command line (or the
    /// same user default) picks the collection; otherwise the app keeps its
    /// own profile, separate from the official app's.
    static func resolve() throws -> CollectionPaths {
        let collection: URL
        if let path = UserDefaults.standard.string(forKey: "CollectionPath") {
            collection = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            collection = support.appending(path: "AnkiMac/User 1/collection.anki2")
        }
        let folder = collection.deletingLastPathComponent()
        let media = folder.appending(path: "collection.media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        return CollectionPaths(
            collection: collection,
            mediaFolder: media,
            mediaDB: folder.appending(path: "collection.media.db2"))
    }
}

/// The open collection and the app-wide state built on it. One per app.
@Observable
final class CollectionModel {
    /// nil until the backend has started; `open` waits for it.
    private(set) var backend: AnkiBackend?
    let reviewer = ReviewerWebController()
    /// The card web view exists and is in the window, hidden until studying.
    private(set) var reviewerReady = false

    private(set) var paths: CollectionPaths?
    private(set) var decks: [DeckNode] = []
    private(set) var isLoaded = false
    private var lastRefresh = Date.distantPast
    private var rolloverTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    var selectedDeckID: Int64?
    private(set) var session: StudySession?
    var errorMessage: String?

    /// Started at launch, off the main thread, while SwiftUI builds the window.
    private let backendStartup = Task.detached(priority: .userInitiated) { try AnkiBackend() }

    init() {
        BenchDriver.trace("model_init")
    }

    var selectedDeck: DeckNode? {
        guard let id = selectedDeckID else { return nil }
        return Self.find(id, in: decks)
    }

    func open() async {
        do {
            let backend = try await backendStartup.value
            self.backend = backend
            BenchDriver.trace("backend_init")
            let paths = try CollectionPaths.resolve()
            try await backend.perform { backend in
                var request = Anki_Collection_OpenCollectionRequest()
                request.collectionPath = paths.collection.path
                request.mediaFolderPath = paths.mediaFolder.path
                request.mediaDbPath = paths.mediaDB.path
                try backend.openCollection(request)
            }
            BenchDriver.trace("collection_open")
            self.paths = paths
            reviewer.mediaFolder = paths.mediaFolder
            await refreshDecks()
            if selectedDeckID == nil {
                selectedDeckID = decks.max { $0.dueCount < $1.dueCount }?.id
            }
            isLoaded = true
            refreshWhenActivated()
            Task { await prepareReviewer() }
        } catch {
            errorMessage = "Could not open the collection: \(error)"
        }
    }

    /// Creates the card web view once the deck list is up, rather than at
    /// launch, where it would delay the first frame. It then stays in the
    /// window, so starting a session doesn't pay to attach it.
    private func prepareReviewer() async {
        // Let the deck list reach the screen first.
        await Task.yield()
        reviewer.prepare()
        reviewerReady = true
    }

    /// Called on quit. Closing flushes the WAL and releases the file lock.
    func close() {
        rolloverTask?.cancel()
        activationTask?.cancel()
        session?.stop()
        guard paths != nil, let backend else { return }
        try? backend.closeCollection(Anki_Collection_CloseCollectionRequest())
        paths = nil
    }

    func refreshDecks() async {
        guard let backend else { return }
        do {
            let (tree, nextDayAt) = try await backend.perform { backend in
                var request = Anki_Decks_DeckTreeRequest()
                request.now = Int64(Date().timeIntervalSince1970)
                return (try backend.deckTree(request), try backend.schedTimingToday().nextDayAt)
            }
            decks = tree.children.map(DeckNode.init)
            lastRefresh = Date()
            scheduleRollover(at: nextDayAt)
            BenchDriver.trace("deck_tree")
        } catch {
            errorMessage = "Could not load decks: \(error)"
        }
    }

    /// The counts are per scheduler day, so they go stale when the day rolls
    /// over, and when another app (or a sync) changed the collection while
    /// this one was in the background.
    private func scheduleRollover(at nextDayAt: Int64) {
        rolloverTask?.cancel()
        let delay = max(1, Double(nextDayAt) - Date().timeIntervalSince1970)
        rolloverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refreshDecks()
        }
    }

    private func refreshWhenActivated() {
        activationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                // Launch activates the app right after the first load.
                guard let self, session == nil, Date().timeIntervalSince(lastRefresh) > 2 else { continue }
                await refreshDecks()
            }
        }
    }

    func setCollapsed(_ deckID: Int64, _ collapsed: Bool) {
        guard let backend else { return }
        Task {
            _ = try? await backend.perform { backend in
                var request = Anki_Decks_SetDeckCollapsedRequest()
                request.deckID = deckID
                request.collapsed = collapsed
                request.scope = .reviewer
                return try backend.setDeckCollapsed(request)
            }
        }
    }

    // MARK: Studying

    func startStudying() {
        guard let deckID = selectedDeckID, let backend else { return }
        session?.stop()
        let session = StudySession(deckID: deckID, backend: backend, reviewer: reviewer)
        self.session = session
        Task { await session.start() }
    }

    func stopStudying() {
        session?.stop()
        session = nil
        Task { await refreshDecks() }
    }

    private static func find(_ id: Int64, in nodes: [DeckNode]) -> DeckNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = find(id, in: node.children ?? []) { return found }
        }
        return nil
    }
}
