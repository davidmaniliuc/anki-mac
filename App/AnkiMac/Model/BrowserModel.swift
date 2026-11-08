import AnkiKit
import Foundation
import Observation

/// Whether the browser lists cards or notes. Each mode keeps its own columns
/// and sort order in the collection config, under desktop's keys, so both
/// apps open the browser the same way.
nonisolated enum BrowserMode: String, CaseIterable, Sendable {
    case cards, notes

    var title: String {
        switch self {
        case .cards: "Cards"
        case .notes: "Notes"
        }
    }

    fileprivate struct ConfigKeys {
        let columns: String
        let defaultColumns: [String]
        let sortColumn: String
        let sortReverse: String
    }

    fileprivate var keys: ConfigKeys {
        switch self {
        case .cards:
            ConfigKeys(
                columns: "activeCols", defaultColumns: ["noteFld", "template", "cardDue", "deck"],
                sortColumn: "sortType", sortReverse: "sortBackwards")
        case .notes:
            ConfigKeys(
                columns: "activeNoteCols", defaultColumns: ["noteFld", "note", "template", "noteTags"],
                sortColumn: "noteSortType", sortReverse: "browserNoteSortBackwards")
        }
    }
}

typealias BrowserColumn = Anki_Search_BrowserColumns.Column

extension BrowserColumn {
    nonisolated func label(_ mode: BrowserMode) -> String {
        mode == .cards ? cardsModeLabel : notesModeLabel
    }

    nonisolated func tooltip(_ mode: BrowserMode) -> String {
        mode == .cards ? cardsModeTooltip : notesModeTooltip
    }

    nonisolated func sorting(_ mode: BrowserMode) -> Anki_Search_BrowserColumns.Sorting {
        mode == .cards ? sortingCards : sortingNotes
    }
}

nonisolated struct BrowserSort: Equatable, Sendable {
    var column: String
    /// Descending.
    var reverse: Bool
}

/// The state of the card that the Cards menu toggles: desktop's "current
/// card", the row selected last (the first card of a note in notes mode).
nonisolated struct CommandCard: Equatable, Sendable {
    var flag: CardFlag
    var isMarked: Bool
    /// nil where the target doesn't offer suspending.
    var isSuspended: Bool?
}

/// One browser window: the search, the ids it found, and the visible rows.
///
/// Searches return every id at once and run off the main thread; rows are
/// fetched one at a time, on demand, as the table scrolls them into view.
@Observable
final class BrowserModel {
    let collection: CollectionModel

    private(set) var mode: BrowserMode = .cards
    var searchText = ""
    private(set) var searchError: String?
    private(set) var ids: [Int64] = []
    /// Bumped whenever `ids` is replaced; the table reloads and restores the
    /// selection by id.
    private(set) var idsVersion = 0
    /// Bumped when the rows' contents changed but the ids did not (after
    /// flagging or suspending, say); the table redraws without losing its place.
    private(set) var rowsVersion = 0
    private(set) var allColumns: [BrowserColumn] = []
    private(set) var columns: [BrowserColumn] = []
    private(set) var sort = BrowserSort(column: "noteFld", reverse: false)
    private(set) var sidebar: [SidebarSection] = []
    private(set) var selectedRows = IndexSet()
    private(set) var commandCard: CommandCard?
    private(set) var undoLabel = ""
    /// Notes waiting for the user to confirm deleting them.
    var notesToDelete: [Int64]?
    var errorMessage: String?

    /// Rows by id, for the current search only. nil marks an id whose card or
    /// note no longer exists.
    @ObservationIgnored private var rowCache: [Int64: Anki_Search_BrowserRow?] = [:]
    /// The search text the ids came from; sorting and undo search it again.
    @ObservationIgnored private var appliedSearch = ""
    /// Each search takes the next number; a result whose number is no longer
    /// the latest arrived after a newer search started and is dropped.
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var selectionToRestore: Set<Int64> = []
    @ObservationIgnored private var currentRow: Int?
    @ObservationIgnored private var opened = false
    /// Called after the rows for an `idsVersion` are on screen, with how many
    /// visible rows were laid out. Used by the bench driver.
    @ObservationIgnored var onRowsPainted: ((_ idsVersion: Int, _ laidOut: Int) -> Void)?

    init(collection: CollectionModel) {
        self.collection = collection
    }

    var selectedIDs: [Int64] {
        selectedRows.compactMap { ids.indices.contains($0) ? ids[$0] : nil }
    }

    // MARK: Opening

    /// Loads the saved mode, columns and sort, then runs desktop's default
    /// search, all in one trip to the backend. The trip starts at once, on a
    /// background thread, so it overlaps building the window.
    func open() {
        guard !opened, let backend = collection.backend else { return }
        opened = true
        BenchDriver.browserOpened(self)
        PERF("open called")
        let loading = Task.detached(priority: .userInitiated) { try Self.load(backend) }
        Task {
            do {
                let opening = try await loading.value
                allColumns = opening.allColumns
                apply(opening.settings)
                searchText = opening.prompt
                appliedSearch = opening.search
                show(opening.ids)
                undoLabel = opening.undoLabel
            } catch {
                errorMessage = String(describing: error)
            }
            await loadSidebar()
        }
    }

    private nonisolated struct Opening: Sendable {
        let allColumns: [BrowserColumn]
        let settings: Settings
        let search: String
        let prompt: String
        let ids: [Int64]
        let undoLabel: String
    }

    private nonisolated struct Settings: Sendable {
        let mode: BrowserMode
        let columns: [BrowserColumn]
        let sort: BrowserSort
    }

    private nonisolated static func load(_ backend: AnkiBackend) throws -> Opening {
        PERF("load start")
        var notesMode = Anki_Config_GetConfigBoolRequest()
        notesMode.key = .browserTableShowNotesMode
        let mode: BrowserMode = try backend.getConfigBool(notesMode).val ? .notes : .cards
        let allColumns = try backend.allBrowserColumns().columns
        PERF("load columns")
        let settings = try settings(for: mode, allColumns: allColumns, backend: backend)
        PERF("load settings")

        var defaultKey = Anki_Config_GetConfigStringRequest()
        defaultKey.key = .defaultSearchText
        let saved = try backend.getConfigString(defaultKey).val
        let search: String
        let prompt: String
        if saved.trimmingCharacters(in: .whitespaces).isEmpty {
            var node = Anki_Search_SearchNode()
            node.deck = "current"
            search = try backend.buildSearchString(node).val
            prompt = ""
        } else {
            search = saved
            prompt = saved
        }
        PERF("load search built")
        let ids = try find(search, mode: mode, sort: settings.sort, backend: backend)
        PERF("load searched")
        return Opening(
            allColumns: allColumns, settings: settings, search: search, prompt: prompt, ids: ids,
            undoLabel: try backend.getUndoStatus().undo)
    }

    /// Reads a mode's columns and sort from the config and makes those
    /// columns the ones `browserRowForId` fills.
    private nonisolated static func settings(
        for mode: BrowserMode, allColumns: [BrowserColumn], backend: AnkiBackend
    ) throws -> Settings {
        let keys = mode.keys
        let byKey = Dictionary(allColumns.map { ($0.key, $0) }) { first, _ in first }
        let saved = backend.configJSON(keys.columns, as: [String].self) ?? keys.defaultColumns
        var columns = saved.compactMap { byKey[$0] }
        if columns.isEmpty { columns = keys.defaultColumns.compactMap { byKey[$0] } }
        try setActive(columns.map(\.key), backend: backend)

        // As desktop: an unknown or unsortable column falls back to creation time.
        var column = backend.configJSON(keys.sortColumn, as: String.self) ?? "noteCrt"
        if byKey[column].map({ $0.sorting(mode) == .none }) ?? true { column = "noteCrt" }
        let reverse = backend.configJSON(keys.sortReverse, as: Bool.self) ?? false
        return Settings(mode: mode, columns: columns, sort: BrowserSort(column: column, reverse: reverse))
    }

    private func apply(_ settings: Settings) {
        mode = settings.mode
        columns = settings.columns
        sort = settings.sort
    }

    // MARK: Searching

    /// Runs the text in the search field, as typed. The field then shows the
    /// backend's normalised form of it, as desktop.
    func search() {
        search(text: searchText)
    }

    func search(text: String) {
        var node = Anki_Search_SearchNode()
        node.parsableText = text.replacing(/\s/, with: " ")
        run(node, showInField: true)
    }

    func search(_ item: SidebarItem) {
        run(item.searchNode, showInField: true)
    }

    /// Searches the last search again, in the current mode and order.
    private func searchAgain() {
        var node = Anki_Search_SearchNode()
        node.parsableText = appliedSearch
        run(node, showInField: false)
    }

    private func run(_ node: Anki_Search_SearchNode, showInField: Bool) {
        guard let backend = collection.backend else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let mode = mode
        let sort = sort
        PERF("run start")
        Task {
            do {
                PERF("task start")
                let (search, ids) = try await backend.perform { backend in
                    PERF("bg start")
                    let search = try backend.buildSearchString(node).val
                    let r = (search, try Self.find(search, mode: mode, sort: sort, backend: backend))
                    PERF("bg end")
                    return r
                }
                PERF("main resumed")
                guard generation == searchGeneration else { return }
                appliedSearch = search
                // Observation notifies on every set, equal or not, and each
                // notification re-renders the toolbar.
                if showInField && !UserDefaults.standard.bool(forKey: "XNoField") && searchText != search {
                    searchText = search
                }
                if searchError != nil { searchError = nil }
                // The direction was flipped in memory while this search ran.
                show(sort.reverse == self.sort.reverse ? ids : ids.reversed())
                PERF("shown")
            } catch {
                guard generation == searchGeneration else { return }
                searchError = (error as? AnkiError)?.message ?? String(describing: error)
            }
        }
    }

    private func show(_ newIDs: [Int64], caller: String = #function, line: Int = #line) {
        PERF("show from \(caller):\(line) v\(idsVersion + 1) n\(newIDs.count)")
        selectionToRestore = Set(selectedIDs)
        rowCache.removeAll(keepingCapacity: true)
        ids = newIDs
        idsVersion += 1
    }

    private nonisolated static func find(
        _ search: String, mode: BrowserMode, sort: BrowserSort, backend: AnkiBackend
    ) throws -> [Int64] {
        var request = Anki_Search_SearchRequest()
        request.search = search
        var order = Anki_Search_SortOrder.Builtin()
        order.column = sort.column
        order.reverse = sort.reverse
        request.order.builtin = order
        return switch mode {
        case .cards: try backend.searchCards(request).ids
        case .notes: try backend.searchNotes(request).ids
        }
    }

    // MARK: Table

    /// The row at `index`, fetched from the backend the first time it is
    /// shown. About 0.03 ms a row, so the table asks on the main thread.
    func row(at index: Int) -> Anki_Search_BrowserRow? {
        guard ids.indices.contains(index), let backend = collection.backend else { return nil }
        let id = ids[index]
        if let cached = rowCache[id] { return cached }
        var request = Anki_Generic_Int64()
        request.val = id
        let row = try? backend.browserRowForId(request)
        rowCache[id] = row
        return row
    }

    /// The rows to select after the ids were replaced: those whose ids were
    /// selected before.
    func takeSelectionToRestore() -> IndexSet {
        defer { selectionToRestore = [] }
        guard !selectionToRestore.isEmpty else { return [] }
        return IndexSet(ids.indices.filter { selectionToRestore.contains(ids[$0]) })
    }

    /// `current` is the row selected last, which the Cards menu's toggles follow.
    func selectionChanged(_ rows: IndexSet, current: Int?) {
        if rows != selectedRows { selectedRows = rows }
        guard current != currentRow || commandCard == nil else { return }
        currentRow = current
        refreshCommandCard()
    }

    func sortRequested(column key: String, ascending: Bool) {
        guard let column = allColumns.first(where: { $0.key == key }), column.sorting(mode) != .none else { return }
        if key != sort.column {
            // A new column starts in its natural direction: newest first for dates, and so on.
            sort = BrowserSort(column: key, reverse: column.sorting(mode) == .descending)
            saveSort()
            searchAgain()
        } else if sort.reverse == ascending {
            sort.reverse = !ascending
            saveSort()
            show(ids.reversed())
        }
    }

    private func saveSort() {
        guard let backend = collection.backend else { return }
        let keys = mode.keys
        try? backend.setConfigJSON(keys.sortColumn, sort.column)
        try? backend.setConfigJSON(keys.sortReverse, sort.reverse)
    }

    func toggleColumn(_ key: String) {
        guard let backend = collection.backend else { return }
        var keys = columns.map(\.key)
        if let index = keys.firstIndex(of: key) {
            guard keys.count > 1 else { return }
            keys.remove(at: index)
        } else {
            keys.append(key)
        }
        do {
            try backend.setConfigJSON(mode.keys.columns, keys)
            try Self.setActive(keys, backend: backend)
        } catch {
            errorMessage = String(describing: error)
            return
        }
        columns = keys.compactMap { key in allColumns.first { $0.key == key } }
        rowCache.removeAll(keepingCapacity: true)
        rowsVersion += 1
    }

    func setMode(_ newMode: BrowserMode) {
        guard newMode != mode, let backend = collection.backend else { return }
        do {
            var request = Anki_Config_SetConfigBoolRequest()
            request.key = .browserTableShowNotesMode
            request.value = newMode == .notes
            _ = try backend.setConfigBool(request)
            apply(try Self.settings(for: newMode, allColumns: allColumns, backend: backend))
        } catch {
            errorMessage = String(describing: error)
            return
        }
        // Card ids mean nothing in notes mode; clear the table until the new ids arrive.
        selectedRows = []
        show([])
        searchAgain()
    }

    // MARK: Sidebar

    func loadSidebar() async {
        guard let backend = collection.backend else { return }
        if let sections = try? await backend.perform({ backend in try SidebarSection.load(backend) }) {
            sidebar = sections
        }
    }

    // MARK: Card commands

    private nonisolated struct Selection: Sendable {
        let mode: BrowserMode
        let ids: [Int64]
    }

    private var selection: Selection? {
        let ids = selectedIDs
        return ids.isEmpty ? nil : Selection(mode: mode, ids: ids)
    }

    private func refreshCommandCard() {
        guard let backend = collection.backend, let currentRow, ids.indices.contains(currentRow) else {
            commandCard = nil
            return
        }
        let current = Selection(mode: mode, ids: [ids[currentRow]])
        Task {
            commandCard = try? await backend.perform { backend in
                guard let cardID = try Self.cardIDs(current, backend: backend).first else { return nil }
                var request = Anki_Cards_CardId()
                request.cid = cardID
                let card = try backend.getCard(request)
                var noteID = Anki_Notes_NoteId()
                noteID.nid = card.noteID
                let tags = try backend.getNote(noteID).tags
                return CommandCard(
                    flag: CardFlag(cardFlags: card.flags),
                    isMarked: tags.contains { $0.caseInsensitiveCompare(Self.markedTag) == .orderedSame },
                    isSuspended: card.queue == Self.suspendedQueue)
            }
        }
    }

    /// As desktop: the current card decides whether the whole selection gets
    /// the flag or loses it.
    func toggleFlag(_ flag: CardFlag) {
        guard let selection, let commandCard else { return }
        let new = commandCard.flag == flag ? CardFlag.none : flag
        change { backend in
            var request = Anki_Cards_SetFlagRequest()
            request.cardIds = try Self.cardIDs(selection, backend: backend)
            request.flag = UInt32(new.rawValue)
            _ = try backend.setFlag(request)
        }
    }

    func toggleMark() {
        guard let selection, let commandCard else { return }
        let marked = commandCard.isMarked
        change { backend in
            var request = Anki_Tags_NoteIdsAndTagsRequest()
            request.noteIds = try Self.noteIDs(selection, backend: backend)
            request.tags = Self.markedTag
            _ = marked ? try backend.removeNoteTags(request) : try backend.addNoteTags(request)
        }
    }

    func toggleSuspend() {
        guard let selection, let suspended = commandCard?.isSuspended else { return }
        change { backend in
            let cardIDs = try Self.cardIDs(selection, backend: backend)
            if suspended {
                var request = Anki_Cards_CardIds()
                request.cids = cardIDs
                _ = try backend.restoreBuriedAndSuspendedCards(request)
            } else {
                var request = Anki_Scheduler_BuryOrSuspendCardsRequest()
                request.cardIds = cardIDs
                request.mode = .suspend
                _ = try backend.buryOrSuspendCards(request)
            }
        }
    }

    /// Asks for confirmation; `confirmDelete` does the deleting.
    func deleteNotes() {
        guard let selection, let backend = collection.backend else { return }
        Task {
            notesToDelete = try? await backend.perform { backend in try Self.noteIDs(selection, backend: backend) }
        }
    }

    func confirmDelete() {
        guard let noteIDs = notesToDelete else { return }
        notesToDelete = nil
        change(searchAgain: true) { backend in
            var request = Anki_Notes_RemoveNotesRequest()
            request.noteIds = noteIDs
            _ = try backend.removeNotes(request)
        }
    }

    func undo() {
        guard !undoLabel.isEmpty else { return }
        change(searchAgain: true) { backend in _ = try backend.undo() }
    }

    /// Runs an undoable change, then redraws the rows (or searches again when
    /// rows may have appeared or gone) and refreshes the main window's decks.
    private func change(searchAgain: Bool = false, _ work: @escaping @Sendable (AnkiBackend) throws -> Void) {
        guard let backend = collection.backend else { return }
        Task {
            do {
                undoLabel = try await backend.perform { backend in
                    try work(backend)
                    return try backend.getUndoStatus().undo
                }
            } catch {
                errorMessage = (error as? AnkiError)?.message ?? String(describing: error)
            }
            if searchAgain {
                self.searchAgain()
            } else {
                rowCache.removeAll(keepingCapacity: true)
                rowsVersion += 1
            }
            refreshCommandCard()
            await collection.refreshDecks()
        }
    }

    /// Called when the window comes to the front: the main window may have
    /// studied or undone something meanwhile.
    func refreshUndo() {
        guard let backend = collection.backend else { return }
        Task {
            if let label = try? await backend.perform({ backend in try backend.getUndoStatus().undo }) {
                undoLabel = label
            }
        }
    }

    // MARK: Backend helpers

    nonisolated private static let markedTag = "marked"
    nonisolated private static let suspendedQueue: Int32 = -1

    private nonisolated static func cardIDs(_ selection: Selection, backend: AnkiBackend) throws -> [Int64] {
        guard selection.mode == .notes else { return selection.ids }
        var node = Anki_Search_SearchNode()
        node.nids.ids = selection.ids
        var request = Anki_Search_SearchRequest()
        request.search = try backend.buildSearchString(node).val
        request.order.none = Anki_Generic_Empty()
        return try backend.searchCards(request).ids
    }

    private nonisolated static func noteIDs(_ selection: Selection, backend: AnkiBackend) throws -> [Int64] {
        guard selection.mode == .cards else { return selection.ids }
        var request = Anki_Search_SearchRequest()
        request.search = "cid:" + selection.ids.map(String.init).joined(separator: ",")
        request.order.none = Anki_Generic_Empty()
        return try backend.searchNotes(request).ids
    }

    private nonisolated static func setActive(_ keys: [String], backend: AnkiBackend) throws {
        var list = Anki_Generic_StringList()
        list.vals = keys
        try backend.setActiveBrowserColumns(list)
    }
}

nonisolated func PERF(_ s: String) {
    let line = Data(String(format: "PERF %.3f %@\n", Date().timeIntervalSince1970 * 1000, s).utf8)
    if let handle = perfHandle { handle.write(line) } else { FileHandle.standardError.write(line) }
}
nonisolated(unsafe) let perfHandle: FileHandle? = UserDefaults.standard.string(forKey: "PerfLog").flatMap {
    FileManager.default.createFile(atPath: $0, contents: nil); return FileHandle(forWritingAtPath: $0)
}
