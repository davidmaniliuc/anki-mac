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

    /// This deck's id and its subdecks'.
    var subtreeIDs: Set<Int64> { (children ?? []).reduce([id]) { $0.union($1.subtreeIDs) } }

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
    /// same user default) opens that collection instead of a profile.
    static var commandLineCollection: URL? {
        UserDefaults.standard.string(forKey: "CollectionPath").map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
        }
    }

    /// A profile's collection, in the app's own data folder, separate from
    /// the official app's.
    static func profile(_ name: String) throws -> CollectionPaths {
        try resolve(try Profiles.folder(name).appending(path: "collection.anki2"))
    }

    static func resolve(_ collection: URL) throws -> CollectionPaths {
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
    /// Where the open collection's settings and login are kept.
    private(set) var scope: SettingsScope?
    /// The open profile; nil before one is open, or for a collection
    /// opened with `-CollectionPath`.
    private(set) var profileName: String?
    /// The main window shows the profiles instead of the decks.
    var choosingProfile = false
    private(set) var decks: [DeckNode] = []
    private(set) var isLoaded = false
    private(set) var lastRefresh = Date.distantPast
    private var rolloverTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    var backupTask: Task<Void, Never>?
    var selectedDeckID: Int64?
    private(set) var session: StudySession?
    var errorMessage: String?
    /// What Undo and Redo would act on in the main window, while not studying.
    private(set) var undoState = UndoState()
    /// The deck whose name is being edited in the sidebar.
    var renamingDeckID: Int64?
    /// The Custom Study dialog, while it's open.
    var customStudy: CustomStudyModel?
    /// The selected deck's buried cards, which the overview loads.
    var selectedBuried = BuriedCards()
    /// The selected deck's description, which the overview loads.
    var selectedDescription: DeckDescription?
    /// Whether the Study Deck picker is open.
    var studyDeckPresented = false
    /// The Description sheet's text, while it's open.
    var descriptionEdit: DeckDescription?
    /// The deck whose Unbury asks which kind, while it asks.
    var unburyPrompt: Int64?
    /// The filtered deck dialog, while it's open.
    var filteredDeck: FilteredDeckModel?
    /// Import and export (File menu, Finder, the Browser's Export Notes).
    var importResult: ImportResult?
    var importMessage: String?
    var packageImportURL: URL?
    var packageImportPresented = false
    var csvImport: CsvImportModel?
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
    var syncAuth: Anki_Sync_SyncAuth?
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
        get { scope?.bool("syncMedia", default: true) ?? true }
        set { scope?.set(newValue, for: "syncMedia") }
    }
    var autoSync: Bool {
        get { scope?.bool("autoSync", default: true) ?? true }
        set { scope?.set(newValue, for: "autoSync") }
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

    /// Opens the collection named on the command line, or the profile
    /// desktop would: the only one, or else the one opened last. Otherwise
    /// the profiles show, to pick one.
    func start() async {
        do {
            let backend = try await backendStartup.value
            self.backend = backend
            BenchDriver.trace("backend_init")
            if let collection = CollectionPaths.commandLineCollection {
                await open(try CollectionPaths.resolve(collection), scope: .collection(collection.path))
                return
            }
            Profiles.adoptAppSettings()
            let names = try Profiles.names()
            if names.count == 1 {
                await openProfile(names[0])
            } else if let last = Profiles.lastLoaded, names.contains(last) {
                await openProfile(last)
            } else {
                choosingProfile = true
            }
        } catch {
            errorMessage = "Could not open the collection: \(error)"
        }
    }

    /// Opens a profile; if it can't be, the profiles show again, as desktop does.
    func openProfile(_ name: String) async {
        do {
            let paths = try CollectionPaths.profile(name)
            choosingProfile = false
            profileName = name
            await open(paths, scope: .profile(name))
            if isLoaded {
                Profiles.lastLoaded = name
            } else {
                profileName = nil
                choosingProfile = true
            }
        } catch {
            errorMessage = "Could not open the collection: \(error)"
        }
    }

    private func open(_ paths: CollectionPaths, scope: SettingsScope) async {
        guard let backend else { return }
        self.scope = scope
        syncAuth = SyncKeychain.load(account: scope.key)
        syncUsername = scope.string("syncUsername") ?? ""
        do {
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
            if !reviewerReady { Task { await prepareReviewer() } }
            if autoSync, syncAuth != nil, !backupRestored {
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
        guard let (backend, closing) = beginClosing() else { return }
        Self.close(closing, backend: backend)
        paths = nil
    }

    /// Closes the profile and shows the profiles, as desktop's Switch
    /// Profile. The other windows close first; one that asks to keep its
    /// changes keeps the profile open.
    func switchProfile() async {
        guard isLoaded, !syncIsRunning, closeOtherWindows() else { return }
        guard let (backend, closing) = beginClosing() else { return }
        isLoaded = false
        try? await backend.perform { Self.close(closing, backend: $0) }
        paths = nil
        scope = nil
        profileName = nil
        decks = []
        selectedDeckID = nil
        session = nil
        undoState = UndoState()
        backupRestored = false
        syncAuth = nil
        syncUsername = ""
        syncStatus = .noChanges
        choosingProfile = true
    }

    /// The main window, which stays open across profiles.
    @ObservationIgnored weak var mainWindow: NSWindow?

    private func closeOtherWindows() -> Bool {
        let others = NSApp.windows.filter {
            $0 !== mainWindow && $0.isVisible && $0.styleMask.contains(.titled) && $0.sheetParent == nil
        }
        others.forEach { $0.performClose(nil) }
        return !others.contains(where: \.isVisible)
    }

    /// What closing needs, taken from the model before it's reset.
    private struct Closing: Sendable {
        let paths: CollectionPaths
        let scope: SettingsScope?
        let auth: Anki_Sync_SyncAuth?
        let syncMedia: Bool
        let backUp: Bool
    }

    private func beginClosing() -> (AnkiBackend, Closing)? {
        rolloverTask?.cancel()
        activationTask?.cancel()
        backupTask?.cancel()
        session?.stop()
        guard let paths, let backend else { return nil }
        return (
            backend,
            Closing(
                paths: paths, scope: scope, auth: !backupRestored && autoSync ? syncAuth : nil,
                syncMedia: syncMediaEnabled, backUp: !backupRestored)
        )
    }

    nonisolated private static func close(_ closing: Closing, backend: AnkiBackend) {
        // Desktop's unattended close sync only merges when it can do so safely.
        // A full-sync choice needs a person, so leave it for the next launch.
        if let auth = closing.auth {
            var request = Anki_Sync_SyncCollectionRequest()
            request.auth = auth
            if let response = try? backend.syncCollection(request) {
                if response.hasNewEndpoint, let scope = closing.scope {
                    var updated = auth
                    updated.endpoint = response.newEndpoint
                    SyncKeychain.save(updated, account: scope.key)
                }
                if response.required != .fullSync, closing.syncMedia {
                    try? backend.syncMedia(auth)
                    while (try? backend.mediaSyncStatus().active) == true {
                        Thread.sleep(forTimeInterval: 0.25)
                    }
                }
            }
        }
        if closing.backUp { _ = try? backend.backUp(.onClose, to: closing.paths.backups) }
        try? backend.closeCollection(Anki_Collection_CloseCollectionRequest())
    }

    /// Saves a login whose endpoint changed.
    private func saveAuth(_ auth: Anki_Sync_SyncAuth) {
        syncAuth = auth
        if let scope { SyncKeychain.save(auth, account: scope.key) }
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
                saveAuth(updated)
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
            saveAuth(auth)
            syncUsername = request.username
            scope?.set(request.username, for: "syncUsername")
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
        if let scope {
            SyncKeychain.delete(account: scope.key)
            scope.set(nil, for: "syncUsername")
        }
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
            syncUsername = scope?.string("syncUsername") ?? ""
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
                saveAuth(updated)
            }
            switch output.required {
            case .noChanges, .normalSync:
                session?.stop()
                session = nil
                await refreshDecks()
                BrowserWindowController.current?.model.refreshAfterExternalChange()
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
            BrowserWindowController.current?.model.refreshAfterExternalChange()
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
            let (tree, nextDayAt, undoState) = try await backend.perform { backend in
                var request = Anki_Decks_DeckTreeRequest()
                request.now = Int64(Date().timeIntervalSince1970)
                return (
                    try backend.deckTree(request), try backend.schedTimingToday().nextDayAt,
                    try backend.undoState())
            }
            decks = tree.children.map { DeckNode($0) }
            self.undoState = undoState
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

    /// Stops the study session when it is on one of these decks or inside one,
    /// since the session cannot go on once its deck is deleted. Call before
    /// the delete, while the tree still has the decks.
    func stopStudying(deleting deckIDs: [Int64]) {
        guard let studying = session?.deckID else { return }
        if deckIDs.contains(where: { deck($0)?.subtreeIDs.contains(studying) == true }) { stopStudying() }
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
