import AnkiKit
import Foundation
import Observation

/// The Add window's state, ported from desktop's editor in add mode
/// (ts/routes/editor/NoteEditor.svelte): the note type and deck choosers, the
/// note being written, its tags, the checks before adding, sticky fields,
/// and the history of notes added.
@Observable
final class AddCardsModel {
    struct Choice: Identifiable, Hashable {
        let id: Int64
        let name: String
    }

    struct HistoryEntry: Identifiable {
        let id: Int64
        let text: String
    }

    enum Problem: Equatable {
        case duplicate, clozeOutsideNotetype, clozeOutsideField

        var hint: String {
            switch self {
            case .duplicate: ""
            case .clozeOutsideNotetype: Tr.addingClozeOutsideClozeNotetype
            case .clozeOutsideField: Tr.addingClozeOutsideClozeField
            }
        }
    }

    let editor: NoteEditorModel
    private(set) var notetypes: [Choice] = []
    private(set) var decks: [Choice] = []
    private(set) var notetypeID: Int64 = 0
    var deckID: Int64 = 0
    var tags: [String] = []
    private(set) var problem: Problem?
    /// Whether the fields as they stand would add: the first field filled
    /// (or a mask drawn) and no cloze where it can't go.
    private(set) var addable = false
    private(set) var history: [HistoryEntry] = []
    private(set) var notetype: Anki_Notetypes_Notetype?
    /// Shown briefly after adding, as desktop's toast.
    private(set) var addedMessage: String?
    var message: String?
    /// Asks whether to add a cloze note with no clozes.
    var confirmingMissingCloze = false

    private let backend: AnkiBackend
    private var note = Anki_Notes_Note()
    private var lastAdded: Anki_Notes_Note?
    private var checkTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?

    init(backend: AnkiBackend, mediaFolder: URL?) {
        self.backend = backend
        editor = NoteEditorModel(backend: backend, mediaFolder: mediaFolder)
        editor.onChange = { [weak self] in self?.scheduleCheck() }
    }

    /// Picks the note type and deck as desktop does: the current review
    /// card's deck, else the last ones used.
    func start(homeDeckID: Int64) async throws {
        let (notetypes, decks, defaults) = try await backend.perform { backend in
            var request = Anki_Decks_GetDeckNamesRequest()
            request.skipEmptyDefault = true
            request.includeFiltered = false
            var defaultsRequest = Anki_Notes_DefaultsForAddingRequest()
            defaultsRequest.homeDeckOfCurrentReviewCard = homeDeckID
            return (
                try backend.getNotetypeNames().entries.map { Choice(id: $0.id, name: $0.name) },
                try backend.getDeckNames(request).entries.map { Choice(id: $0.id, name: $0.name) },
                try backend.defaultsForAdding(defaultsRequest)
            )
        }
        self.notetypes = notetypes
        self.decks = decks
        deckID = defaults.deckID
        try await load(notetypeID: defaults.notetypeID)
    }

    /// Desktop's `set_note`, for Create Copy: the note's type, fields and
    /// tags, in the given deck.
    func setNote(_ original: Anki_Notes_Note, deckID: Int64) async throws {
        try await load(notetypeID: original.notetypeID, copying: original)
        self.deckID = deckID
        lastAdded = nil
    }

    // MARK: Note type

    /// Changing the note type keeps what was written: fields with the same
    /// name first, then the rest in order, and the tags. The deck follows
    /// the note type unless the collection adds to the current deck.
    func changeNotetype(to id: Int64) async {
        guard id != notetypeID else { return }
        do {
            let previous = currentNote
            let oldNames = notetype?.fields.map(\.name) ?? []
            try await load(notetypeID: id, copyFrom: (previous, oldNames))
            let toCurrentDeck = try await backend.perform { backend in
                var request = Anki_Config_GetConfigBoolRequest()
                request.key = .addingDefaultsToCurrentDeck
                return try backend.getConfigBool(request).val
            }
            if !toCurrentDeck {
                var notetypeID = Anki_Notetypes_NotetypeId()
                notetypeID.ntid = id
                deckID = try await backend.perform { [notetypeID] in try $0.defaultDeckForNotetype(notetypeID).did }
            }
            lastAdded = nil
        } catch {
            message = ActionFailure.reason(error)
        }
    }

    private func load(
        notetypeID id: Int64, copyFrom: (Anki_Notes_Note, [String])? = nil, sticky: Anki_Notes_Note? = nil,
        copying original: Anki_Notes_Note? = nil
    ) async throws {
        let originalID = original?.id
        let (notetype, fresh, occlusion) = try await backend.perform { backend in
            var notetypeID = Anki_Notetypes_NotetypeId()
            notetypeID.ntid = id
            let notetype = try backend.getNotetype(notetypeID)
            return (
                notetype, try backend.newNote(notetypeID),
                // A copy starts from the original's masks, as desktop's
                // Create Copy reads them by the original's id.
                NoteEditorModel.occlusionSetup(notetype: notetype, noteID: originalID, backend: backend)
            )
        }
        var note = fresh
        let names = notetype.fields.map(\.name)
        if let (old, oldNames) = copyFrom {
            note.fields = Self.copyFields(old.fields, from: oldNames, to: names, into: note.fields)
            note.tags = old.tags
        }
        if let original {
            note.fields = original.fields
            note.tags = original.tags
        }
        if let sticky {
            for (index, field) in notetype.fields.enumerated()
            where field.config.sticky && index < sticky.fields.count && !sticky.fields[index].isEmpty {
                note.fields[index] = sticky.fields[index]
            }
            note.tags = sticky.tags
        }
        self.notetype = notetype
        notetypeID = id
        self.note = note
        tags = note.tags
        problem = nil
        addable = false
        editor.load(notetype: notetype, values: note.fields, occlusion: occlusion)
        // Sticky fields can make the new note addable already.
        checkTask?.cancel()
        checkTask = Task { await check() }
    }

    /// Desktop's rule: same-named non-empty fields, then the remaining
    /// non-empty ones by position.
    static func copyFields(_ old: [String], from oldNames: [String], to newNames: [String], into fields: [String])
        -> [String]
    {
        var fields = fields
        var copied = Set<String>()
        for (newIndex, name) in newNames.enumerated() {
            if let oldIndex = oldNames.firstIndex(of: name), oldIndex < old.count, !old[oldIndex].isEmpty {
                fields[newIndex] = old[oldIndex]
                copied.insert(name)
            }
        }
        var newIndex = 0
        for (oldIndex, oldName) in oldNames.enumerated() {
            while newIndex < newNames.count, copied.contains(newNames[newIndex]) { newIndex += 1 }
            guard newIndex < newNames.count else { break }
            if !copied.contains(oldName), oldIndex < old.count, !old[oldIndex].isEmpty {
                fields[newIndex] = old[oldIndex]
                newIndex += 1
            }
        }
        return fields
    }

    // MARK: Sticky fields

    func isSticky(_ index: Int) -> Bool {
        notetype.map { index < $0.fields.count && $0.fields[index].config.sticky } ?? false
    }

    /// Sticky fields keep their content after adding; the setting is saved
    /// in the note type, as desktop does.
    func toggleSticky(_ index: Int) {
        guard var notetype, index < notetype.fields.count else { return }
        notetype.fields[index].config.sticky.toggle()
        self.notetype = notetype
        let updated = notetype
        Task {
            do {
                _ = try await backend.perform { try $0.updateNotetype(updated) }
            } catch {
                message = ActionFailure.reason(error)
            }
        }
    }

    // MARK: Checks and adding

    var currentNote: Anki_Notes_Note {
        var note = self.note
        note.fields = editor.values
        note.tags = tags
        return note
    }

    /// Duplicate and cloze hints, checked shortly after typing stops.
    private func scheduleCheck() {
        checkTask?.cancel()
        checkTask = Task {
            try? await Task.sleep(for: Theme.AddCards.checkDelay)
            guard !Task.isCancelled else { return }
            await check()
        }
    }

    private func check() async {
        let note = currentNote
        guard let state = try? await backend.perform({ try $0.noteFieldsCheck(note).state }) else { return }
        addable = ![.empty, .notetypeNotCloze, .fieldNotCloze].contains(state)
        switch state {
        case .duplicate: problem = .duplicate
        case .notetypeNotCloze: problem = .clozeOutsideNotetype
        case .fieldNotCloze: problem = .clozeOutsideField
        default: problem = nil
        }
    }

    /// The search that shows notes duplicating the first field.
    var duplicateSearch: String {
        let first = editor.values.first ?? ""
        let escaped = first.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        return "\"dupe:\(notetypeID),\(escaped)\""
    }

    /// Adds the note, unless a check stops it. `confirmedCloze` is set once
    /// the user agreed to add a cloze note without clozes.
    func add(confirmedCloze: Bool = false) async -> Bool {
        editor.commitPendingEdits()
        let note = currentNote
        do {
            let state = try await backend.perform { try $0.noteFieldsCheck(note).state }
            switch state {
            case .empty:
                message = editor.occlusion == nil ? Tr.addingTheFirstFieldIsEmpty : Tr.notetypesNoOcclusionCreated2
                return false
            case .notetypeNotCloze:
                message = Tr.addingClozeOutsideClozeNotetype
                return false
            case .fieldNotCloze:
                message = Tr.addingClozeOutsideClozeField
                return false
            case .missingCloze where !confirmedCloze:
                confirmingMissingCloze = true
                return false
            default:
                break
            }
            var request = Anki_Notes_AddNoteRequest()
            request.note = note
            request.deckID = deckID
            let (response, text) = try await backend.perform { [request] backend in
                let response = try backend.addNote(request)
                var line = Anki_CardRendering_HtmlToTextLineRequest()
                line.text = note.fields.joined(separator: ", ")
                line.preserveMediaFilenames = true
                return (response, try backend.htmlToTextLine(line).val)
            }
            var added = note
            added.id = response.noteID
            history.append(HistoryEntry(id: response.noteID, text: text.count > 30 ? String(text.prefix(30)) + "..." : text))
            lastAdded = added
            showAdded(Int(response.changes.count))
            try await load(notetypeID: notetypeID, sticky: added)
            return true
        } catch {
            message = ActionFailure.reason(error)
            return false
        }
    }

    private func showAdded(_ count: Int) {
        addedMessage = Tr.importingCardsAdded(count: count)
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(for: Theme.AddCards.addedMessageDuration)
            guard !Task.isCancelled else { return }
            addedMessage = nil
        }
    }

    /// Whether closing would lose something typed: desktop ignores empty
    /// fields and sticky fields left as they were added.
    var hasUnsavedInput: Bool {
        let values = editor.values
        for (index, value) in values.enumerated() {
            let text = value.replacing(Self.lineBreak, with: "").trimmingCharacters(in: .whitespaces)
            var unchanged: Set<String> = ["", "<br>"]
            if let lastAdded, isSticky(index), index < lastAdded.fields.count {
                unchanged.insert(
                    lastAdded.fields[index].replacing(Self.lineBreak, with: "").trimmingCharacters(in: .whitespaces))
            }
            if !unchanged.contains(text) { return true }
        }
        return false
    }

    nonisolated(unsafe) private static let lineBreak = try! Regex(#"<br\s*/?>"#).ignoresCase()

    // MARK: Tags

    func completeTags(_ prefix: String) -> [String] {
        var request = Anki_Tags_CompleteTagRequest()
        request.input = prefix
        request.matchLimit = UInt32(Theme.AddCards.tagSuggestions)
        return (try? backend.completeTag(request).tags) ?? []
    }

    var pasteKeepsFormatting: Bool {
        var request = Anki_Config_GetConfigBoolRequest()
        request.key = .pasteStripsFormatting
        return !((try? backend.getConfigBool(request).val) ?? false)
    }
}
