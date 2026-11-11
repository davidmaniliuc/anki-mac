import AnkiKit
import Foundation
import Observation

/// The card on screen and what answering it would do.
nonisolated struct StudyCard: Sendable {
    let queued: Anki_Scheduler_QueuedCards.QueuedCard
    let rendered: RenderedCard
    /// Next intervals for Again, Hard, Good, Easy ("10m", "4d").
    let intervals: [String]
    let options: DeckOptions
    var flag: CardFlag
    /// The note carries the "marked" tag.
    var isMarked: Bool
}

/// The deck options the reviewer needs, from the card's home deck.
nonisolated struct DeckOptions: Sendable {
    let autoplay: Bool
    let maxAnswerMillis: UInt32

    init(_ config: Anki_DeckConfig_DeckConfig.Config) {
        autoplay = !config.disableAutoplay
        maxAnswerMillis = config.capAnswerTimeToSecs * 1000
    }
}

nonisolated enum Rating: Int, CaseIterable, Sendable {
    case again, hard, good, easy

    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    var proto: Anki_Scheduler_CardAnswer.Rating {
        switch self {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}

/// One review session on one deck: fetch, show question, show answer, answer.
@Observable
final class StudySession {
    enum Phase: Equatable {
        case loading
        case question
        case answer
        case finished
    }

    let deckID: Int64
    private(set) var phase: Phase = .loading
    private(set) var card: StudyCard?
    /// The card answered last, for Previous Card Info.
    private(set) var previousCardID: Int64?
    private(set) var counts = (new: 0, learn: 0, review: 0)
    private(set) var currentQueue: Anki_Scheduler_QueuedCards.Queue?
    private(set) var undoState = UndoState()
    var errorMessage: String?
    private(set) var audioPaused = false
    /// Called once a question, an answer or the end of the session is on
    /// screen. Used by the bench driver.
    var onDisplayed: ((Phase) -> Void)?

    private let backend: AnkiBackend
    private let reviewer: ReviewerWebController
    private let audio = AudioPlayer()
    private var shownAt = Date()
    private var busy = false
    /// The typed text is being compared; a second Return must not start another.
    private var revealing = false

    init(deckID: Int64, backend: AnkiBackend, reviewer: ReviewerWebController) {
        self.deckID = deckID
        self.backend = backend
        self.reviewer = reviewer
    }

    func start() async {
        BenchDriver.trace("session_start")
        reviewer.onCommand = { [weak self] command in self?.handle(command) }
        let deckID = deckID
        busy = true
        await loadNext { backend in
            var select = Anki_Decks_DeckId()
            select.did = deckID
            _ = try backend.setCurrentDeck(select)
        }
    }

    func stop() {
        audio.stop()
        reviewer.onCommand = nil
        reviewer.clear()
    }

    func showAnswer() {
        guard phase == .question, !revealing, let card else { return }
        guard let typeAnswer = card.rendered.typeAnswer else {
            display(card, answer: card.rendered.answer)
            return
        }
        revealing = true
        Task {
            let typed = await reviewer.typedAnswer()
            let html = await run { backend in
                try CardRenderer.answerHTML(
                    card.rendered.answer, typeAnswer: typeAnswer, typed: typed, backend: backend)
            }
            revealing = false
            // The session may have moved on (end session, undo) while the backend worked.
            guard phase == .question, self.card?.queued.card.id == card.queued.card.id else { return }
            display(card, answer: html ?? card.rendered.answer)
        }
    }

    private func display(_ card: StudyCard, answer: String) {
        phase = .answer
        reviewer.showAnswer(answer)
        notifyDisplayed(.answer)
        if card.options.autoplay, let folder = reviewer.mediaFolder {
            audio.play(card.rendered.answerAV, mediaFolder: folder)
        }
    }

    func answer(_ rating: Rating) {
        guard phase == .answer, let card, !busy else { return }
        audio.stop()
        previousCardID = card.queued.card.id
        let taken = min(
            UInt32(max(0, Date().timeIntervalSince(shownAt)) * 1000),
            card.options.maxAnswerMillis)
        busy = true
        Task {
            // Answering and fetching the next card share one trip off the main thread.
            await loadNext { backend in
                let states = card.queued.states
                var answer = Anki_Scheduler_CardAnswer()
                answer.cardID = card.queued.card.id
                answer.currentState = states.current
                answer.newState = switch rating {
                case .again: states.again
                case .hard: states.hard
                case .good: states.good
                case .easy: states.easy
                }
                answer.rating = rating.proto
                answer.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
                answer.millisecondsTaken = taken
                _ = try backend.answerCard(answer)
            }
        }
    }

    func undo() {
        guard undoState.canUndo else { return }
        replay { backend in _ = try backend.undo() }
    }

    func redo() {
        guard undoState.canRedo else { return }
        replay { backend in _ = try backend.redo() }
    }

    private func replay(_ change: @escaping @Sendable (AnkiBackend) throws -> Void) {
        guard !busy else { return }
        audio.stop()
        busy = true
        Task {
            await loadNext(after: change)
        }
    }

    /// Sets the card's flag, or clears it when it already has that flag, as desktop.
    func toggleFlag(_ flag: CardFlag) {
        guard let card, !busy else { return }
        let new: CardFlag = card.flag == flag ? .none : flag
        let cardID = card.queued.card.id
        edit(cardID) { backend in
            var request = Anki_Cards_SetFlagRequest()
            request.cardIds = [cardID]
            request.flag = UInt32(new.rawValue)
            _ = try backend.setFlag(request)
        } applied: { [self] in
            self.card?.flag = new
            reviewer.drawFlag(new)
        }
    }

    func toggleMark() {
        guard let card, !busy else { return }
        let marked = !card.isMarked
        let cardID = card.queued.card.id
        let noteID = card.queued.card.noteID
        edit(cardID) { backend in
            var request = Anki_Tags_NoteIdsAndTagsRequest()
            request.noteIds = [noteID]
            request.tags = Self.markedTag
            _ = marked ? try backend.addNoteTags(request) : try backend.removeNoteTags(request)
        } applied: { [self] in
            self.card?.isMarked = marked
            reviewer.drawMark(marked)
        }
    }

    /// Runs an undoable change to the card on screen, then refreshes the
    /// undo state. `applied` runs only if that card is still showing.
    private func edit(
        _ cardID: Int64, _ change: @escaping @Sendable (AnkiBackend) throws -> Void, applied: @escaping () -> Void
    ) {
        Task {
            let undoState = await run { backend in
                try change(backend)
                return try backend.undoState()
            }
            guard let undoState, card?.queued.card.id == cardID else { return }
            self.undoState = undoState
            applied()
        }
    }

    func replayAudio() {
        guard let card, let folder = reviewer.mediaFolder else { return }
        let tags = phase == .answer ? card.rendered.answerAV : card.rendered.questionAV
        audio.play(tags, mediaFolder: folder)
    }

    // MARK: Card actions, as desktop's reviewer offers them

    func suspendCurrentCard() { changeCard { try Self.suspend($0, backend: $1, note: false) } }
    func suspendCurrentNote() { changeCard { try Self.suspend($0, backend: $1, note: true) } }
    func buryCurrentCard() { changeCard { try Self.bury($0, backend: $1, note: false) } }
    func buryCurrentNote() { changeCard { try Self.bury($0, backend: $1, note: true) } }

    func deleteCurrentNote() {
        changeCard { card, backend in
            var request = Anki_Notes_RemoveNotesRequest()
            request.noteIds = [card.noteID]
            return Tr.browsingCardsDeleted(count: Int(try backend.removeNotes(request).count))
        }
    }

    /// Runs `change` on the card on screen, then shows the next one with
    /// the message it returns as feedback. Every such change is undoable.
    private func changeCard(
        _ change: @escaping @Sendable (Anki_Cards_Card, AnkiBackend) throws -> String
    ) {
        guard let card, !busy else { return }
        busy = true
        audio.stop()
        let ids = card.queued.card
        Task {
            let message = Box<String>()
            await loadNext { backend in message.value = try change(ids, backend) }
            if let text = message.value { showFeedback(text) }
        }
    }

    nonisolated private static func suspend(_ card: Anki_Cards_Card, backend: AnkiBackend, note: Bool) throws -> String {
        var request = Anki_Scheduler_BuryOrSuspendCardsRequest()
        request.mode = .suspend
        if note { request.noteIds = [card.noteID] } else { request.cardIds = [card.id] }
        _ = try backend.buryOrSuspendCards(request)
        return note ? Tr.studyingNoteSuspended : Tr.studyingCardSuspended
    }

    nonisolated private static func bury(_ card: Anki_Cards_Card, backend: AnkiBackend, note: Bool) throws -> String {
        var request = Anki_Scheduler_BuryOrSuspendCardsRequest()
        request.mode = .buryUser
        if note { request.noteIds = [card.noteID] } else { request.cardIds = [card.id] }
        return Tr.studyingCardsBuried(count: Int(try backend.buryOrSuspendCards(request).count))
    }

    func showCardInfo(in collection: CollectionModel) {
        guard let id = card?.queued.card.id else { return }
        CardInfoWindowController.show(cardID: id, kind: .reviewer, collection: collection)
    }

    func toggleAudioPause() {
        audioPaused.toggle()
        if audioPaused { audio.pause() } else { audio.resume() }
    }

    // MARK: Prompts: Set Due Date, Reset and Reposition

    /// The question being asked about the card on screen, shown as a sheet.
    enum Prompt: Identifiable {
        case setDueDate(days: String)
        case forget(restorePosition: Bool, resetCounts: Bool)
        case reposition(queueTop: Int, queueBottom: Int, randomize: Bool, shift: Bool)

        var id: String {
            switch self {
            case .setDueDate: "setDueDate"
            case .forget: "forget"
            case .reposition: "reposition"
            }
        }
    }

    var prompt: Prompt?

    var canScheduleCards: Bool { card != nil && !busy }

    func askSetDueDate() {
        guard canScheduleCards else { return }
        ask { backend in
            var key = Anki_Config_GetConfigStringRequest()
            key.key = .setDueReviewer
            return .setDueDate(days: try backend.getConfigString(key).val)
        }
    }

    func askForget() {
        guard canScheduleCards else { return }
        ask { backend in
            var request = Anki_Scheduler_ScheduleCardsAsNewDefaultsRequest()
            request.context = .reviewer
            let defaults = try backend.scheduleCardsAsNewDefaults(request)
            return .forget(restorePosition: defaults.restorePosition, resetCounts: defaults.resetCounts)
        }
    }

    /// Only new cards can move, so the item does nothing for the others.
    func askReposition() {
        guard canScheduleCards, currentQueue == .new else { return }
        ask { backend in
            let defaults = try backend.repositionDefaults()
            let query: [String: Any] = [
                "kind": "query", "sql": "select min(due), max(due) from cards where type = 0 and odid = 0",
                "args": [], "first_row_only": true,
            ]
            let reply = try backend.dbCommand(try JSONSerialization.data(withJSONObject: query))
            let row = (try JSONSerialization.jsonObject(with: reply) as? [[Any]])?.first ?? []
            return .reposition(
                queueTop: max(row.first as? Int ?? 0, 0), queueBottom: row.dropFirst().first as? Int ?? 0,
                randomize: defaults.random, shift: defaults.shift)
        }
    }

    private func ask(_ gather: @escaping @Sendable (AnkiBackend) throws -> Prompt) {
        Task { prompt = await run(gather) }
    }

    func setDueDate(days: String) {
        prompt = nil
        guard days.trimmingCharacters(in: .whitespaces).isEmpty == false else { return }
        changeCard { card, backend in
            var request = Anki_Scheduler_SetDueDateRequest()
            request.cardIds = [card.id]
            request.days = days
            request.configKey.key = .setDueReviewer
            _ = try backend.setDueDate(request)
            return Tr.schedulingSetDueDateDone(cards: 1)
        }
    }

    func forget(restorePosition: Bool, resetCounts: Bool) {
        prompt = nil
        changeCard { card, backend in
            var request = Anki_Scheduler_ScheduleCardsAsNewRequest()
            request.cardIds = [card.id]
            request.log = true
            request.restorePosition = restorePosition
            request.resetCounts = resetCounts
            request.context = .reviewer
            _ = try backend.scheduleCardsAsNew(request)
            return Tr.schedulingForgotCards(cards: 1)
        }
    }

    func reposition(start: Int, step: Int, randomize: Bool, shift: Bool) {
        prompt = nil
        changeCard { card, backend in
            var request = Anki_Scheduler_SortCardsRequest()
            request.cardIds = [card.id]
            request.startingFrom = UInt32(max(start, 0))
            request.stepSize = UInt32(max(step, 1))
            request.randomize = randomize
            request.shiftExisting = shift
            _ = try backend.sortCards(request)
            return Tr.actionsReposition
        }
    }

    // MARK: Editing the note

    /// The note editor sheet, while the current note is being edited.
    var editor: StudyEditModel?

    func editCurrentNote() {
        guard let card, editor == nil else { return }
        audio.stop()
        let noteID = card.queued.card.noteID
        let mediaFolder = reviewer.mediaFolder
        let backend = backend
        Task {
            let model = StudyEditModel(backend: backend, mediaFolder: mediaFolder)
            if await model.load(noteID: noteID) { editor = model }
        }
    }

    /// The editor closed: after Save, the card is rendered again from the changed note.
    func finishEditing(save: Bool) {
        guard let editor else { return }
        self.editor = nil
        guard save, !busy, let note = editor.changedNote() else { return }
        busy = true
        Task {
            await loadNext { backend in
                var request = Anki_Notes_UpdateNotesRequest()
                request.notes = [note]
                _ = try backend.updateNotes(request)
            }
        }
    }

    // MARK: Feedback

    /// A short message shown over the card for a moment, as desktop's tooltip.
    private(set) var feedback: String?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    func showFeedback(_ text: String) {
        feedback = text
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(for: Theme.Study.feedbackDuration)
            if !Task.isCancelled { feedback = nil }
        }
    }

    // MARK: -

    /// Runs `change` (answer, undo, pick deck), then fetches and renders the
    /// next card, in one background call. Callers set `busy` first, so a
    /// second key press can't answer the same card twice.
    private func loadNext(after change: @escaping @Sendable (AnkiBackend) throws -> Void) async {
        defer { busy = false }
        let configCache = self.configCache
        let next: (StudyCard?, Anki_Scheduler_QueuedCards, UndoState)? = await run { backend in
            try change(backend)
            var request = Anki_Scheduler_GetQueuedCardsRequest()
            request.fetchLimit = 1
            let queue = try backend.getQueuedCards(request)
            let undoState = try backend.undoState()
            guard let queued = queue.cards.first else { return (nil, queue, undoState) }

            var hideKey = Anki_Config_GetConfigBoolRequest()
            hideKey.key = .hideAudioPlayButtons
            let rendered = try CardRenderer.render(
                queued.card, hidePlayButtons: try backend.getConfigBool(hideKey).val, backend: backend)
            let intervals = try backend.describeNextStates(queued.states).vals
            let options = try Self.options(for: queued.card, cache: configCache, backend: backend)
            var noteID = Anki_Notes_NoteId()
            noteID.nid = queued.card.noteID
            let isMarked = try backend.getNote(noteID).tags.contains { $0.caseInsensitiveCompare(Self.markedTag) == .orderedSame }
            let studyCard = StudyCard(
                queued: queued, rendered: rendered, intervals: intervals, options: options,
                flag: CardFlag(cardFlags: queued.card.flags), isMarked: isMarked)
            return (studyCard, queue, undoState)
        }
        BenchDriver.trace("first_card_rendered")
        guard let (card, queue, undoState) = next else { return }
        self.undoState = undoState
        counts = (Int(queue.newCount), Int(queue.learningCount), Int(queue.reviewCount))
        self.card = card
        guard let card else {
            currentQueue = nil
            phase = .finished
            reviewer.clear()
            onDisplayed?(.finished)
            return
        }
        currentQueue = card.queued.queue
        phase = .question
        shownAt = Date()
        reviewer.showQuestion(card.rendered.question, answer: card.rendered.answer, bodyClass: card.rendered.bodyClass)
        reviewer.drawFlag(card.flag)
        reviewer.drawMark(card.isMarked)
        notifyDisplayed(.question)
        if card.options.autoplay, let folder = reviewer.mediaFolder {
            audio.play(card.rendered.questionAV, mediaFolder: folder)
        }
    }

    nonisolated private static let markedTag = "marked"

    /// The deck the current card belongs to, outside any filtered deck.
    var homeDeckID: Int64? {
        guard let card = card?.queued.card else { return nil }
        return card.originalDeckID != 0 ? card.originalDeckID : card.deckID
    }

    /// The options changed; the next card reads them again.
    func invalidateOptions() {
        configCache.removeAll()
    }

    private let configCache = DeckOptionsCache()

    /// Options come from the card's home deck, as desktop's `current_deck_id`.
    nonisolated private static func options(
        for card: Anki_Cards_Card, cache: DeckOptionsCache, backend: AnkiBackend
    ) throws -> DeckOptions {
        let homeDeck = card.originalDeckID != 0 ? card.originalDeckID : card.deckID
        if let cached = cache[homeDeck] { return cached }
        var deckID = Anki_Decks_DeckId()
        deckID.did = homeDeck
        var configID = Anki_DeckConfig_DeckConfigId()
        if case .normal(let normal) = try backend.getDeck(deckID).kind {
            configID.dcid = normal.configID
        } else {
            configID.dcid = 1
        }
        let options = DeckOptions(try backend.getDeckConfig(configID).config)
        cache[homeDeck] = options
        return options
    }

    private func notifyDisplayed(_ phase: Phase) {
        guard onDisplayed != nil else { return }
        reviewer.whenShown { [weak self] in self?.onDisplayed?(phase) }
    }

    private func handle(_ command: String) {
        if command == "ans" {
            showAnswer()
        } else if command.hasPrefix("play:"), let card, let folder = reviewer.mediaFolder {
            // "play:q:0": the first sound on the question side.
            let parts = command.split(separator: ":")
            guard parts.count == 3, let index = Int(parts[2]) else { return }
            let tags = parts[1] == "q" ? card.rendered.questionAV : card.rendered.answerAV
            guard tags.indices.contains(index) else { return }
            audio.play([tags[index]], mediaFolder: folder)
        }
    }

    /// Runs backend work off the main thread; errors land in `errorMessage`.
    @discardableResult
    private func run<T: Sendable>(_ work: @escaping @Sendable (AnkiBackend) throws -> T) async -> T? {
        do {
            return try await backend.perform(work)
        } catch {
            errorMessage = String(describing: error)
            return nil
        }
    }
}

/// Deck options by deck id, filled from the background thread that renders cards.
nonisolated final class DeckOptionsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var options: [Int64: DeckOptions] = [:]

    subscript(deckID: Int64) -> DeckOptions? {
        get { lock.withLock { options[deckID] } }
        set { lock.withLock { options[deckID] = newValue } }
    }

    func removeAll() {
        lock.withLock { options.removeAll() }
    }
}

/// A value the background work hands back to the main actor.
nonisolated final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
