import AnkiKit
import AppKit
import Foundation
import Observation
import Security

/// One deck in the sidebar, flattened from the backend's `DeckTreeNode`.
nonisolated struct DeckNode: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    /// With its parents ("Spanish::Verbs"), as rename and search need it.
    let fullName: String
    let newCount: Int
    let learnCount: Int
    let reviewCount: Int
    let collapsed: Bool
    let filtered: Bool
    /// nil for a leaf, so `List` shows no disclosure triangle.
    let children: [DeckNode]?

    var dueCount: Int { newCount + learnCount + reviewCount }

    init(_ node: Anki_Decks_DeckTreeNode, parent: String? = nil) {
        id = node.deckID
        name = node.name
        fullName = parent.map { "\($0)::\(node.name)" } ?? node.name
        newCount = Int(node.newCount)
        learnCount = Int(node.learnCount)
        reviewCount = Int(node.reviewCount)
        collapsed = node.collapsed
        filtered = node.filtered
        let fullName = fullName
        children = node.children.isEmpty ? nil : node.children.map { DeckNode($0, parent: fullName) }
    }
}

nonisolated struct CollectionPaths: Sendable {
    let collection: URL
    let mediaFolder: URL
    let mediaDB: URL
    let backups: URL

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
        let backups = folder.appending(path: "backups")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        return CollectionPaths(
            collection: collection,
            mediaFolder: media,
            mediaDB: folder.appending(path: "collection.media.db2"),
            backups: backups)
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
    var backupTask: Task<Void, Never>?
    var selectedDeckID: Int64?
    private(set) var session: StudySession?
    var errorMessage: String?
    /// What Undo would undo in the main window, while not studying.
    private(set) var undoLabel = ""
    /// The deck whose name is being edited in the sidebar.
    var renamingDeckID: Int64?
    /// The Custom Study dialog, while it's open.
    var customStudy: CustomStudyModel?
    /// The selected deck's buried cards, which the overview loads.
    var selectedBuried = BuriedCards()
    /// The deck whose Unbury asks which kind, while it asks.
    var unburyPrompt: Int64?
    /// The filtered deck dialog, while it's open.
    var filteredDeck: FilteredDeckModel?
    /// Import and export (File menu, Finder, the Browser's Export Notes).
    var importResult: ImportResult?
    var importMessage: String?
    var packageImportURL: URL?
    var packageImportPresented = false
    var exportSheetPresented = false
    var selectedExportNoteIDs: [Int64]?
    var exportDeckID: Int64?
    var packageOperationInProgress = false
    /// True while the backend has the collection closed for a package export or replacement.
    var collectionClosed = false
    /// A backup was restored, so for the rest of the session there are no
    /// periodic or close backups and no sync on close, as on desktop.
    var backupRestored = false
    /// The outcome of File > Create Backup and Revert to Backup.
    var backupMessage: String?

    var maintenanceTool: MaintenanceTool?

    // Sync account and progress. SyncAuth is kept in the login Keychain item.
    var syncAuth: Anki_Sync_SyncAuth? = SyncKeychain.load()
    var syncStatus: Anki_Sync_SyncStatusResponse.Required = .noChanges
    var syncIsRunning = false
    var syncMediaProgress = ""
    var syncLoginPresented = false
    var syncUsername = ""
    var syncConflictPresented = false
    var syncConflict: Anki_Sync_SyncCollectionResponse.ChangesRequired = .noChanges
    var syncServerUsn: Int32 = 0
    var syncAlert: String?
    var syncMediaEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "syncMedia") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "syncMedia") }
    }

    /// Started at launch, off the main thread, while SwiftUI builds the window.
    private let backendStartup = Task.detached(priority: .userInitiated) { try AnkiBackend() }

    init() {
        BenchDriver.trace("model_init")
    }

    var selectedDeck: DeckNode? {
        guard let id = selectedDeckID else { return nil }
        return Self.find(id, in: decks)
    }

    func deck(_ id: Int64) -> DeckNode? {
        Self.find(id, in: decks)
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
            startPeriodicBackups()
            Task { await prepareReviewer() }
            if UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true, syncAuth != nil {
                await synchronize()
            } else {
                await updateSyncStatus()
            }
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
        backupTask?.cancel()
        session?.stop()
        guard let paths, let backend else { return }
        // Desktop's unattended close sync only merges when it can do so safely.
        // A full-sync choice needs a person, so leave it for the next launch.
        if !backupRestored, UserDefaults.standard.object(forKey: "autoSync") as? Bool ?? true, let auth = syncAuth {
            var request = Anki_Sync_SyncCollectionRequest()
            request.auth = auth
            if let response = try? backend.syncCollection(request) {
                if response.hasNewEndpoint {
                    var updated = auth
                    updated.endpoint = response.newEndpoint
                    syncAuth = updated
                    SyncKeychain.save(updated)
                }
                if response.required != .fullSync, syncMediaEnabled {
                    try? backend.syncMedia(auth)
                    while (try? backend.mediaSyncStatus().active) == true {
                        Thread.sleep(forTimeInterval: 0.25)
                    }
                }
            }
        }
        if !backupRestored { _ = try? backend.backUp(.onClose, to: paths.backups) }
        try? backend.closeCollection(Anki_Collection_CloseCollectionRequest())
        self.paths = nil
    }

    func updateSyncStatus() async {
        guard let backend, let auth = syncAuth else {
            syncStatus = .noChanges
            return
        }
        do {
            let status = try await backend.perform { try $0.syncStatus(auth) }
            syncStatus = status.required
            if status.hasNewEndpoint {
                var updated = auth
                updated.endpoint = status.newEndpoint
                syncAuth = updated
                SyncKeychain.save(updated)
            }
        } catch {
            // Status checks are background hints; explicit sync shows errors.
        }
    }

    func login(username: String, password: String) async {
        guard let backend else { return }
        do {
            var request = Anki_Sync_SyncLoginRequest()
            request.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            request.password = password
            let loginRequest = request
            let auth = try await backend.perform { try $0.syncLogin(loginRequest) }
            syncAuth = auth
            syncUsername = request.username
            SyncKeychain.save(auth)
            UserDefaults.standard.set(request.username, forKey: "syncUsername")
            syncLoginPresented = false
            await synchronize()
        } catch {
            syncAlert = String(describing: error)
        }
    }

    func logOut() {
        syncAuth = nil
        syncUsername = ""
        syncStatus = .noChanges
        SyncKeychain.delete()
        UserDefaults.standard.removeObject(forKey: "syncUsername")
    }

    func cancelSync() {
        guard let backend else { return }
        Task {
            try? await backend.perform { backend in
                try backend.abortSync()
                try backend.abortMediaSync()
            }
        }
    }

    func synchronize() async {
        guard let backend else { return }
        guard let auth = syncAuth else {
            syncUsername = UserDefaults.standard.string(forKey: "syncUsername") ?? ""
            syncLoginPresented = true
            return
        }
        guard !syncIsRunning else { return }
        syncIsRunning = true
        defer { syncIsRunning = false }
        do {
            var request = Anki_Sync_SyncCollectionRequest()
            request.auth = auth
            request.syncMedia = syncMediaEnabled
            let syncRequest = request
            let output = try await backend.perform { try $0.syncCollection(syncRequest) }
            syncServerUsn = output.serverMediaUsn
            if output.hasNewEndpoint {
                var updated = auth
                updated.endpoint = output.newEndpoint
                syncAuth = updated
                SyncKeychain.save(updated)
            }
            switch output.required {
            case .noChanges, .normalSync:
                session?.stop()
                session = nil
                await refreshDecks()
                BrowserWindowController.current?.model.refreshAfterSync()
                if !output.serverMessage.isEmpty { syncAlert = output.serverMessage }
                if syncMediaEnabled { await monitorMediaSync(backend) }
            case .fullUpload, .fullDownload, .fullSync:
                syncConflict = output.required
                syncConflictPresented = true
            case .UNRECOGNIZED:
                syncAlert = "AnkiWeb returned an unsupported sync status."
            }
            await updateSyncStatus()
        } catch {
            if let ankiError = error as? AnkiError, ankiError.backend?.kind == .syncAuthError {
                logOut()
            }
            syncAlert = String(describing: error)
        }
    }

    func resolveSyncConflict(upload: Bool?) async {
        guard let backend, let auth = syncAuth else { return }
        syncConflictPresented = false
        guard let upload else { return }
        syncIsRunning = true
        defer { syncIsRunning = false }
        do {
            var request = Anki_Sync_FullUploadOrDownloadRequest()
            request.auth = auth
            request.upload = upload
            if syncMediaEnabled { request.serverUsn = syncServerUsn }
            let fullSyncRequest = request
            try await backend.perform { try $0.fullUploadOrDownload(fullSyncRequest) }
            session?.stop()
            session = nil
            await refreshDecks()
            BrowserWindowController.current?.model.refreshAfterSync()
            if syncMediaEnabled { await monitorMediaSync(backend) }
            await updateSyncStatus()
        } catch {
            syncAlert = String(describing: error)
        }
    }

    private func monitorMediaSync(_ backend: AnkiBackend) async {
        do {
            guard let auth = syncAuth else { return }
            try await backend.perform { try $0.syncMedia(auth) }
            while true {
                let status = try await backend.perform { try $0.mediaSyncStatus() }
                if status.hasProgress {
                    let progress = status.progress
                    syncMediaProgress = "Added: \(progress.added) · Removed: \(progress.removed) · Checked: \(progress.checked)"
                }
                if !status.active { break }
                try await Task.sleep(for: .milliseconds(250))
            }
            syncMediaProgress = Tr.syncMediaComplete
        } catch {
            syncMediaProgress = Tr.syncMediaFailed
            syncAlert = String(describing: error)
        }
    }

    func refreshDecks() async {
        guard !collectionClosed else { return }
        guard let backend else { return }
        do {
            let (tree, nextDayAt, undo) = try await backend.perform { backend in
                var request = Anki_Decks_DeckTreeRequest()
                request.now = Int64(Date().timeIntervalSince1970)
                return (
                    try backend.deckTree(request), try backend.schedTimingToday().nextDayAt,
                    try backend.getUndoStatus().undo)
            }
            decks = tree.children.map { DeckNode($0) }
            undoLabel = undo
            if let id = selectedDeckID, deck(id) == nil {
                selectedDeckID = nil
            }
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
                await updateSyncStatus()
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

    /// Answers a trusted upstream page's backend call (see `PageBackendRPC`).
    func pageRequest(_ method: String, _ body: Data) throws -> Data {
        guard let backend else { throw PageRPCError(message: "Collection is not open") }
        return try PageBackendRPC.run(method, body: body, backend: backend)
    }

    func startStudying() {
        guard let deckID = selectedDeckID, let backend else { return }
        session?.stop()
        let session = StudySession(deckID: deckID, backend: backend, reviewer: reviewer)
        self.session = session
        // The sidebar stays on screen while studying, so its counts follow each answer.
        session.onCountsChanged = { [weak self] in Task { await self?.refreshDecks() } }
        Task { await session.start() }
    }

    func stopStudying() {
        session?.stop()
        session = nil
        Task { await refreshDecks() }
    }

    /// After the options window saved: the counts follow the new limits,
    /// and the session reads the options again.
    func deckOptionsChanged() {
        session?.invalidateOptions()
        Task { await refreshDecks() }
    }

    // MARK: Filtered decks

    /// A filtered deck's options are its dialog; a normal deck's are the
    /// Deck Options window.
    func showOptions(_ deck: DeckNode) {
        if deck.filtered {
            editFilteredDeck(deck.id)
        } else {
            DeckOptionsWindowController.show(deckID: deck.id, collection: self)
        }
    }

    /// Opens the dialog for a filtered deck, or with id 0 for a new one
    /// built from the selected deck.
    func editFilteredDeck(_ deckID: Int64 = 0) {
        guard let backend, filteredDeck == nil else { return }
        do {
            filteredDeck = try FilteredDeckModel(deckID: deckID, currentDeck: selectedDeckID, backend: backend)
        } catch {
            errorMessage = FilteredDeckModel.message(error)
        }
    }

    /// After Build: the new deck is shown, ready to study.
    func filteredDeckBuilt(_ deckID: Int64) {
        filteredDeck = nil
        if session != nil { stopStudying() }
        Task {
            await refreshDecks()
            selectedDeckID = deckID
        }
    }

    func rebuildFilteredDeck(_ deckID: Int64) {
        filteredDeckOp { backend in
            var request = Anki_Decks_DeckId()
            request.did = deckID
            _ = try backend.rebuildFilteredDeck(request)
        }
    }

    /// Returns the deck's cards to their home decks.
    func emptyFilteredDeck(_ deckID: Int64) {
        filteredDeckOp { backend in
            var request = Anki_Decks_DeckId()
            request.did = deckID
            _ = try backend.emptyFilteredDeck(request)
        }
    }

    private func filteredDeckOp(_ op: @escaping @Sendable (AnkiBackend) throws -> Void) {
        guard let backend else { return }
        if session != nil { stopStudying() }
        Task {
            do {
                try await backend.perform(op)
            } catch {
                errorMessage = FilteredDeckModel.message(error)
            }
            await refreshDecks()
        }
    }

    private static func find(_ id: Int64, in nodes: [DeckNode]) -> DeckNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = find(id, in: node.children ?? []) { return found }
        }
        return nil
    }
}
