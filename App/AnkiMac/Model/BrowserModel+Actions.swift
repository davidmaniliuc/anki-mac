import AnkiKit
import Foundation

/// A deck the selection can move to.
nonisolated struct DeckChoice: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
}

/// A note type the selection can change to.
nonisolated struct NotetypeChoice: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
}

/// Where Find and Replace looks: every field, the tags, or one field by name.
nonisolated enum ReplaceTarget: Hashable, Sendable {
    case allFields, tags
    case field(String)
}

/// The question a browser action needs answered before it runs, shown as a
/// sheet on the browser window. Each carries the defaults desktop would show.
nonisolated enum BrowserPrompt: Identifiable, Sendable {
    case setDueDate(cards: Int, days: String)
    case forget(cards: Int, restorePosition: Bool, resetCounts: Bool)
    case reposition(cards: Int, queueTop: Int, queueBottom: Int, randomize: Bool, shift: Bool)
    case changeDeck(cards: Int, decks: [DeckChoice], current: Int64?)
    case tags(adding: Bool, notes: Int, known: [String])
    case findAndReplace(notes: Int, fields: [String])
    case changeNotetype(noteIDs: [Int64], notetypes: [NotetypeChoice], info: Anki_Notetypes_ChangeNotetypeInfo)

    var id: String {
        switch self {
        case .setDueDate: "setDueDate"
        case .forget: "forget"
        case .reposition: "reposition"
        case .changeDeck: "changeDeck"
        case .tags(let adding, _, _): adding ? "addTags" : "removeTags"
        case .findAndReplace: "findAndReplace"
        case .changeNotetype: "changeNotetype"
        }
    }
}

/// Desktop's Cards and Notes menu actions that ask something first, plus
/// bury. Each `ask…` gathers the prompt's defaults off the main thread; the
/// matching method without `ask` runs the change once the sheet is answered.
extension BrowserModel {
    // MARK: Bury

    func toggleBury() {
        guard let selection, let buried = commandCard?.isBuried else { return }
        change(failing: (buried ? "Couldn’t unbury the cards" : "Couldn’t bury the cards")) { backend in
            let cardIDs = try Self.cardIDs(selection, backend: backend)
            if buried {
                var request = Anki_Cards_CardIds()
                request.cids = cardIDs
                _ = try backend.restoreBuriedAndSuspendedCards(request)
            } else {
                var request = Anki_Scheduler_BuryOrSuspendCardsRequest()
                request.cardIds = cardIDs
                request.mode = .buryUser
                _ = try backend.buryOrSuspendCards(request)
            }
        }
    }

    // MARK: Card prompts

    func askSetDueDate() {
        ask(failing: "Couldn’t open Set Due Date") { selection, backend in
            var key = Anki_Config_GetConfigStringRequest()
            key.key = .setDueBrowser
            let days = try backend.getConfigString(key).val
            return .setDueDate(cards: try Self.cardIDs(selection, backend: backend).count, days: days)
        }
    }

    /// `days` as desktop takes it: "0" today, "1!" tomorrow and reset the
    /// interval, "3-7" a random day in the range. Remembered for next time.
    func setDueDate(days: String) {
        guard !days.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        answerPrompt { selection, backend in
            var request = Anki_Scheduler_SetDueDateRequest()
            request.cardIds = try Self.cardIDs(selection, backend: backend)
            request.days = days
            request.configKey.key = .setDueBrowser
            _ = try backend.setDueDate(request)
        }
    }

    func askForget() {
        ask(failing: "Couldn’t open Reset") { selection, backend in
            var request = Anki_Scheduler_ScheduleCardsAsNewDefaultsRequest()
            request.context = .browser
            let defaults = try backend.scheduleCardsAsNewDefaults(request)
            return .forget(
                cards: try Self.cardIDs(selection, backend: backend).count,
                restorePosition: defaults.restorePosition, resetCounts: defaults.resetCounts)
        }
    }

    /// Puts the cards back in the new queue. The backend saves both choices
    /// as the defaults for next time.
    func forget(restorePosition: Bool, resetCounts: Bool) {
        answerPrompt { selection, backend in
            var request = Anki_Scheduler_ScheduleCardsAsNewRequest()
            request.cardIds = try Self.cardIDs(selection, backend: backend)
            request.log = true
            request.restorePosition = restorePosition
            request.resetCounts = resetCounts
            request.context = .browser
            _ = try backend.scheduleCardsAsNew(request)
        }
    }

    func askReposition() {
        ask(failing: "Couldn’t open Reposition") { selection, backend in
            let defaults = try backend.repositionDefaults()
            let (top, bottom) = try Self.newQueueBounds(backend)
            return .reposition(
                cards: try Self.cardIDs(selection, backend: backend).count, queueTop: top, queueBottom: bottom,
                randomize: defaults.random, shift: defaults.shift)
        }
    }

    /// Only new cards move; the backend leaves the rest of the selection alone.
    func reposition(start: Int, step: Int, randomize: Bool, shift: Bool) {
        answerPrompt(searchAgain: true) { selection, backend in
            var request = Anki_Scheduler_SortCardsRequest()
            request.cardIds = try Self.cardIDs(selection, backend: backend)
            request.startingFrom = UInt32(max(start, 0))
            request.stepSize = UInt32(max(step, 1))
            request.randomize = randomize
            request.shiftExisting = shift
            _ = try backend.sortCards(request)
        }
    }

    func askChangeDeck() {
        ask(failing: "Couldn’t open Change Deck") { selection, backend in
            var request = Anki_Decks_GetDeckNamesRequest()
            request.skipEmptyDefault = true
            request.includeFiltered = false
            let decks = try backend.getDeckNames(request).entries.map { DeckChoice(id: $0.id, name: $0.name) }
            let cardIDs = try Self.cardIDs(selection, backend: backend)
            var current: Int64?
            if let first = cardIDs.first {
                var card = Anki_Cards_CardId()
                card.cid = first
                current = try backend.getCard(card).deckID
            }
            return .changeDeck(cards: cardIDs.count, decks: decks, current: current)
        }
    }

    func changeDeck(to deckID: Int64) {
        guard let selection = answer() else { return }
        change(failing: "Couldn’t move the cards", searchAgain: true) { backend in
            var request = Anki_Cards_SetDeckRequest()
            request.cardIds = try Self.cardIDs(selection, backend: backend)
            request.deckID = deckID
            _ = try backend.setDeck(request)
        }
    }

    // MARK: Note prompts

    func askTags(adding: Bool) {
        ask(failing: (adding ? "Couldn’t open Add Tags" : "Couldn’t open Remove Tags")) { selection, backend in
            let notes = try Self.noteIDs(selection, backend: backend).count
            return .tags(adding: adding, notes: notes, known: try backend.allTags().vals)
        }
    }

    /// `tags` is space-separated, as typed.
    func changeTags(adding: Bool, tags: String) {
        guard let selection = answer() else { return }
        changeTags(of: selection, adding: adding, tags: tags)
    }

    func changeTags(of selection: Selection, adding: Bool, tags: String) {
        guard !tags.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        change(failing: (adding ? "Couldn’t add the tags" : "Couldn’t remove the tags"), searchAgain: true) { backend in
            var request = Anki_Tags_NoteIdsAndTagsRequest()
            request.noteIds = try Self.noteIDs(selection, backend: backend)
            request.tags = tags
            _ = adding ? try backend.addNoteTags(request) : try backend.removeNoteTags(request)
        }
    }

    func askFindAndReplace() {
        ask(failing: "Couldn’t open Find and Replace") { selection, backend in
            var request = Anki_Notes_FieldNamesForNotesRequest()
            request.nids = try Self.noteIDs(selection, backend: backend)
            return .findAndReplace(notes: request.nids.count, fields: try backend.fieldNamesForNotes(request).fields)
        }
    }

    /// Without `selectedOnly`, every note in the collection, as desktop.
    func findAndReplace(
        find: String, replacement: String, in target: ReplaceTarget, selectedOnly: Bool, regex: Bool, matchCase: Bool
    ) {
        guard let selection = answer() else { return }
        change(failing: "Couldn’t find and replace", searchAgain: true) { backend in
            let noteIDs = selectedOnly ? try Self.noteIDs(selection, backend: backend) : []
            if target == .tags {
                var request = Anki_Tags_FindAndReplaceTagRequest()
                request.noteIds = noteIDs
                request.search = find
                request.replacement = replacement
                request.regex = regex
                request.matchCase = matchCase
                _ = try backend.findAndReplaceTag(request)
            } else {
                var request = Anki_Search_FindAndReplaceRequest()
                request.nids = noteIDs
                request.search = find
                request.replacement = replacement
                request.regex = regex
                request.matchCase = matchCase
                if case .field(let name) = target { request.fieldName = name }
                _ = try backend.findAndReplace(request)
            }
        }
    }

    /// A selection of mixed note types is refused with the backend's message, as desktop does.
    func askChangeNotetype() {
        ask(failing: "Couldn’t open Change Notetype") { selection, backend in
            var notes = Anki_Notes_NoteIds()
            notes.noteIds = try Self.noteIDs(selection, backend: backend)
            let current = try backend.getSingleNotetypeOfNotes(notes).ntid
            var request = Anki_Notetypes_GetChangeNotetypeInfoRequest()
            request.oldNotetypeID = current
            request.newNotetypeID = current
            return .changeNotetype(
                noteIDs: notes.noteIds,
                notetypes: try backend.getNotetypeNames().entries.map { NotetypeChoice(id: $0.id, name: $0.name) },
                info: try backend.getChangeNotetypeInfo(request))
        }
    }

    /// Applies the sheet's mapping. The sheet stays up if the change fails.
    func changeNotetype(_ request: Anki_Notetypes_ChangeNotetypeRequest) async {
        guard await confirmSchemaChange(),
            await perform(failing: "Couldn’t change the note type", searchAgain: true, { backend in _ = try backend.changeNotetype(request) })
        else { return }
        cancelPrompt()
    }

    /// Desktop's `confirm_schema_modification`: asks unless a full sync is already due.
    private func confirmSchemaChange() async -> Bool {
        guard let backend = collection.backend,
            !((try? await backend.perform { $0.schemaAlreadyChanged() }) ?? false)
        else { return true }
        return await NotetypeAlerts.confirm(NotetypeAlerts.schemaChange)
    }

    // MARK: Plumbing

    /// Builds a prompt for the current selection off the main thread, then
    /// shows it. The selection is kept, so the answer acts on the same rows.
    private func ask(failing title: String, _ build: @escaping @Sendable (Selection, AnkiBackend) throws -> BrowserPrompt) {
        guard let selection, let backend = collection.backend, prompt == nil else { return }
        Task {
            do {
                let built = try await backend.perform { backend in try build(selection, backend) }
                promptSelection = selection
                prompt = built
            } catch {
                failure = ActionFailure(title, error: error)
            }
        }
    }

    /// Closes the prompt and hands back the rows it was asked about.
    private func answer() -> Selection? {
        defer { promptSelection = nil }
        prompt = nil
        return promptSelection
    }

    /// Runs a prompt's answer on the rows it was asked about. A failure, such
    /// as a due date that can't be read, stays on the sheet; once it's done
    /// the sheet closes.
    private func answerPrompt(
        searchAgain: Bool = false, _ work: @escaping @Sendable (Selection, AnkiBackend) throws -> Void
    ) {
        // Taken while the answer runs, so a second press waits for it.
        guard let selection = promptSelection else { return }
        promptSelection = nil
        promptError = nil
        Task {
            let done = await perform(
                failing: "", searchAgain: searchAgain, failed: { self.promptError = ActionFailure.reason($0) },
                { backend in try work(selection, backend) }, then: { _ in self.prompt = nil })
            if !done { promptSelection = selection }
        }
    }

    func cancelPrompt() {
        prompt = nil
        promptSelection = nil
    }

    /// Desktop's "Queue top" and "Queue bottom": the lowest and highest new
    /// positions outside filtered decks.
    private nonisolated static func newQueueBounds(_ backend: AnkiBackend) throws -> (Int, Int) {
        let query: [String: Any] = [
            "kind": "query", "sql": "select min(due), max(due) from cards where type = 0 and odid = 0",
            "args": [], "first_row_only": true,
        ]
        let reply = try backend.dbCommand(try JSONSerialization.data(withJSONObject: query))
        let row = (try JSONSerialization.jsonObject(with: reply) as? [[Any]])?.first ?? []
        let top = row.first as? Int ?? 0
        let bottom = row.dropFirst().first as? Int ?? 0
        return (max(top, 0), bottom)
    }
}
