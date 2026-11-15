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
    /// Auto Advance: 0 seconds leaves that side to the user.
    let secondsToShowQuestion: Double
    let secondsToShowAnswer: Double
    let questionAction: Anki_DeckConfig_DeckConfig.Config.QuestionAction
    let answerAction: Anki_DeckConfig_DeckConfig.Config.AnswerAction
    let waitForAudio: Bool

    init(_ config: Anki_DeckConfig_DeckConfig.Config) {
        autoplay = !config.disableAutoplay
        maxAnswerMillis = config.capAnswerTimeToSecs * 1000
        secondsToShowQuestion = Double(config.secondsToShowQuestion)
        secondsToShowAnswer = Double(config.secondsToShowAnswer)
        questionAction = config.questionAction
        answerAction = config.answerAction
        waitForAudio = config.waitForAudio
    }
}

/// Desktop's reviewer keys from Preferences > Review, kept for every
/// profile, as desktop keeps them.
nonisolated enum AnswerKeys {
    /// The defaults key of "Spacebar (or enter) also answers card".
    static let spaceAnswersName = "spacebarRatesCard"
    static var spaceAnswers: Bool { UserDefaults.standard.object(forKey: spaceAnswersName) as? Bool ?? true }

    static func name(_ rating: Rating) -> String { "answerKey\(rating.rawValue + 1)" }
    static func defaultKey(_ rating: Rating) -> String { "\(rating.rawValue + 1)" }
    /// Empty when the rating has no key.
    static func key(_ rating: Rating) -> String {
        UserDefaults.standard.string(forKey: name(rating)) ?? defaultKey(rating)
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

/// Desktop's timebox: the time and the answers since the session started or
/// the last "Continue".
nonisolated struct Timebox {
    var startedAt = Date()
    var answers = 0

    /// The message when `limitSecs` (0 = no limit) has run out. Desktop names
    /// the limit, not the time actually taken.
    func messageIfReached(limitSecs: UInt32) -> String? {
        guard limitSecs > 0, Date().timeIntervalSince(startedAt) > Double(limitSecs) else { return nil }
        let minutes = Int((Double(limitSecs) / 60).rounded(.toNearestOrEven))
        return Tr.studyingCardStudiedInMinute(cards: answers, minutes: minutes)
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
    /// What failed and why, for the alert.
    var failure: ActionFailure?
    /// The time is up: the alert's text, until Continue or Finish.
    private(set) var timeboxMessage: String?
    /// Text on the card is selected, so the context menu offers Copy.
    private(set) var hasSelection = false
    /// Called once a question, an answer or the end of the session is on
    /// screen. Used by the bench driver.
    var onDisplayed: ((Phase) -> Void)?
    /// After each answer, undo or deck change, once the next card is up.
    var onCountsChanged: (() -> Void)?
    /// Cards answered this session, less the answers undone.
    private(set) var studied = 0
    let startedAt = Date()
    /// Set when the last card is answered; nil while cards remain.
    private(set) var finishedAt: Date?
    /// What desktop's congratulations screen shows, read once the deck is done.
    private(set) var congrats: Anki_Scheduler_CongratsInfoResponse?
    /// The deck's description for that screen, when its Markdown option is on.
    private(set) var congratsDescription: AttributedString?

    private let backend: AnkiBackend
    private let reviewer: ReviewerWebController
    private let audio = AudioPlayer()
    @ObservationIgnored private lazy var sounds = CardSounds(audio: audio, web: reviewer)
    private var shownAt = Date()
    private var timebox = Timebox()
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
        audio.onFinished = { [weak self] in self?.advanceIfDue() }
        let deckID = deckID
        busy = true
        await loadNext(failing: "Couldn’t load this deck’s cards") { backend in
            var select = Anki_Decks_DeckId()
            select.did = deckID
            _ = try backend.setCurrentDeck(select)
        }
    }

    func stop() {
        cancelAutoAdvance()
        audio.stop()
        recordedVoice?.cleanUp()
        recordedVoice = nil
        reviewer.onCommand = nil
        reviewer.clear()
    }

    func showAnswer() {
        guard phase == .question, !revealing, timeboxMessage == nil, let card else { return }
        guard let typeAnswer = card.rendered.typeAnswer else {
            display(card, answer: card.rendered.answer)
            return
        }
        revealing = true
        Task {
            let typed = await reviewer.typedAnswer()
            let html = await run(
                failing: "Couldn’t compare what you typed",
                recovery: "The answer is shown without the comparison."
            ) { backend in
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
        sounds.show(card.rendered)
        notifyDisplayed(.answer)
        if card.options.autoplay, let folder = reviewer.mediaFolder {
            audio.play(card.rendered.answerAV, mediaFolder: folder)
        }
        scheduleAutoAdvance()
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
            await loadNext(answered: true, failing: "Couldn’t save your answer") { backend in
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

    /// Desktop restarts the timer and goes on to the next card.
    func continueAfterTimebox() {
        timebox = Timebox()
        timeboxMessage = nil
        busy = false
        if phase == .question, let card, card.options.autoplay, let folder = reviewer.mediaFolder {
            audio.play(card.rendered.questionAV, mediaFolder: folder)
        }
        scheduleAutoAdvance()
    }

    func undo() {
        guard undoState.canUndo else { return }
        let undoesAnswer = undoState.undo == Tr.actionsAnswerCard
        replay(failing: "Couldn’t undo", undoesAnswer: undoesAnswer) { backend in _ = try backend.undo() }
    }

    func redo() {
        guard undoState.canRedo else { return }
        replay(failing: "Couldn’t redo") { backend in _ = try backend.redo() }
    }

    private func replay(
        failing title: String, undoesAnswer: Bool = false, _ change: @escaping @Sendable (AnkiBackend) throws -> Void
    ) {
        guard !busy else { return }
        audio.stop()
        busy = true
        Task {
            await loadNext(undoesAnswer: undoesAnswer, failing: title, after: change)
        }
    }

    /// Sets the card's flag, or clears it when it already has that flag, as desktop.
    func toggleFlag(_ flag: CardFlag) {
        guard let card, !busy else { return }
        let new: CardFlag = card.flag == flag ? .none : flag
        let cardID = card.queued.card.id
        edit(cardID, failing: "Couldn’t change this card’s flag") { backend in
            var request = Anki_Cards_SetFlagRequest()
            request.cardIds = [cardID]
            request.flag = UInt32(new.rawValue)
            _ = try backend.setFlag(request)
        } applied: { [self] in
            self.card?.flag = new
        }
    }

    func toggleMark() {
        guard let card, !busy else { return }
        let marked = !card.isMarked
        let cardID = card.queued.card.id
        let noteID = card.queued.card.noteID
        edit(cardID, failing: marked ? "Couldn’t mark this note" : "Couldn’t unmark this note") { backend in
            var request = Anki_Tags_NoteIdsAndTagsRequest()
            request.noteIds = [noteID]
            request.tags = Self.markedTag
            _ = marked ? try backend.addNoteTags(request) : try backend.removeNoteTags(request)
        } applied: { [self] in
            self.card?.isMarked = marked
        }
    }

    /// Runs an undoable change to the card on screen, then refreshes the
    /// undo state. `applied` runs only if that card is still showing.
    private func edit(
        _ cardID: Int64, failing title: String,
        _ change: @escaping @Sendable (AnkiBackend) throws -> Void, applied: @escaping () -> Void
    ) {
        Task {
            let undoState = await run(failing: title) { backend in
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
        failing title: String = "Couldn’t change this card",
        _ change: @escaping @Sendable (Anki_Cards_Card, AnkiBackend) throws -> String
    ) {
        guard let card, !busy else { return }
        busy = true
        audio.stop()
        let ids = card.queued.card
        Task {
            let message = Box<String>()
            await loadNext(failing: title) { backend in message.value = try change(ids, backend) }
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

    func copySelection() { reviewer.copySelection() }

    /// Desktop's `on_create_copy`: Add with this note's type, fields and tags,
    /// in the deck the card is in now.
    func createCopy(in collection: CollectionModel) {
        guard let card = card?.queued.card else { return }
        let deckID = card.originalDeckID != 0 ? card.originalDeckID : card.deckID
        Task {
            let note = await run(failing: "Couldn’t copy this note") { backend in
                var id = Anki_Notes_NoteId()
                id.nid = card.noteID
                return try backend.getNote(id)
            }
            guard let note else { return }
            AddCardsWindowController.show(collection: collection, copying: (note, deckID))
        }
    }

    func toggleAudioPause() {
        if audio.isPaused { audio.resume() } else { audio.pause() }
    }

    /// Desktop's 6 and 7 move by five seconds.
    func seekAudio(by seconds: Double) { audio.seek(by: seconds) }

    // MARK: Own voice

    /// The last Record Own Voice, which V plays again.
    @ObservationIgnored private var recordedVoice: AudioRecording?
    @ObservationIgnored private var isRecordingVoice = false

    /// Desktop's Shift+V: the recording sheet, then the recording played back.
    func recordVoice() {
        guard !isRecordingVoice, let window = reviewer.webView?.window else { return }
        isRecordingVoice = true
        audio.stop()
        Task { [weak self] in
            do {
                let recording = try await AudioRecording.start()
                RecordingSheet.present(recording, over: window) { [weak self] url in
                    guard let self else { return recording.cleanUp() }
                    isRecordingVoice = false
                    guard url != nil else { return }
                    recordedVoice?.cleanUp()
                    recordedVoice = recording
                    replayVoice()
                }
            } catch {
                self?.isRecordingVoice = false
                self?.failure = ActionFailure(
                    "Couldn’t record your voice", detail: Tr.qtMiscUnableToRecord(error: error.localizedDescription))
            }
        }
    }

    func replayVoice() {
        guard let url = recordedVoice?.url else { return showFeedback(Tr.studyingYouHaventRecordedYourVoiceYet) }
        audio.play(file: url)
    }

    // MARK: Auto Advance

    /// Desktop's Shift+A: after the deck options' seconds, the question
    /// shows its answer and the answer is acted on. Off in each new session.
    private(set) var autoAdvance = false
    @ObservationIgnored private var advanceTimer: Task<Void, Never>?
    /// The time ran out while the deck waits for audio still playing.
    @ObservationIgnored private var advanceDue = false

    func toggleAutoAdvance() {
        autoAdvance.toggle()
        showFeedback(autoAdvance ? Tr.actionsAutoAdvanceActivated : Tr.actionsAutoAdvanceDeactivated)
        scheduleAutoAdvance()
    }

    /// Starts the timer for the side on screen.
    private func scheduleAutoAdvance() {
        cancelAutoAdvance()
        guard autoAdvance, let options = card?.options else { return }
        let seconds = switch phase {
        case .question: options.secondsToShowQuestion
        case .answer: options.secondsToShowAnswer
        case .loading, .finished: 0.0
        }
        guard seconds > 0 else { return }
        advanceTimer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            advanceDue = true
            advanceIfDue()
        }
    }

    private func cancelAutoAdvance() {
        advanceTimer?.cancel()
        advanceTimer = nil
        advanceDue = false
    }

    /// The timer ran out, and any audio the deck waits for has ended.
    private func advanceIfDue() {
        guard advanceDue, let options = card?.options else { return }
        if options.waitForAudio, audio.isPlaying { return }
        advanceDue = false
        // As desktop, Auto Advance turns itself off when the study window has
        // lost focus: an editor, a dialog or another window is in front.
        guard reviewer.webView?.window?.isKeyWindow == true else {
            autoAdvance = false
            return
        }
        switch (phase, options.questionAction, options.answerAction) {
        case (.question, .showReminder, _):
            showFeedback(Tr.studyingQuestionTimeElapsed)
        case (.question, _, _):
            showAnswer()
        case (.answer, _, .answerAgain):
            answer(.again)
        case (.answer, _, .answerHard):
            answer(.hard)
        case (.answer, _, .answerGood):
            answer(.good)
        case (.answer, _, .showReminder):
            showFeedback(Tr.studyingAnswerTimeElapsed)
        case (.answer, _, _):
            buryCurrentCard()
        case (.loading, _, _), (.finished, _, _):
            break
        }
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
        Task { prompt = await run(failing: "Couldn’t load this action’s settings", gather) }
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
            await loadNext(
                failing: "Couldn’t save your changes to the note",
                recovery: "Open Edit again to retry; the card shows the note as it was."
            ) { backend in
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
    /// `answered` counts the change as a review for the timebox, whose alert
    /// then holds the session (`busy`) until Continue; `undoesAnswer` takes
    /// one back off the session's count.
    private func loadNext(
        answered: Bool = false, undoesAnswer: Bool = false, failing title: String, recovery: String? = nil,
        after change: @escaping @Sendable (AnkiBackend) throws -> Void
    ) async {
        cancelAutoAdvance()
        defer { busy = timeboxMessage != nil }
        let configCache = self.configCache
        let next: (StudyCard?, Anki_Scheduler_QueuedCards, UndoState, UInt32, Anki_Scheduler_CongratsInfoResponse?)? = await run(
            failing: title, recovery: recovery
        ) { backend in
            try change(backend)
            let timeLimitSecs = try answered ? backend.getPreferences().reviewing.timeLimitSecs : 0
            var request = Anki_Scheduler_GetQueuedCardsRequest()
            request.fetchLimit = 1
            let queue = try backend.getQueuedCards(request)
            let undoState = try backend.undoState()
            guard let queued = queue.cards.first else {
                return (nil, queue, undoState, timeLimitSecs, try backend.congratsInfo())
            }

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
            return (studyCard, queue, undoState, timeLimitSecs, nil)
        }
        BenchDriver.trace("first_card_rendered")
        guard let (card, queue, undoState, timeLimitSecs, congrats) = next else { return }
        self.undoState = undoState
        if undoesAnswer { studied = max(0, studied - 1) }
        if answered {
            studied += 1
            timebox.answers += 1
            timeboxMessage = timebox.messageIfReached(limitSecs: timeLimitSecs)
        }
        counts = (Int(queue.newCount), Int(queue.learningCount), Int(queue.reviewCount))
        self.card = card
        defer { onCountsChanged?() }
        guard let card else {
            currentQueue = nil
            finishedAt = Date()
            self.congrats = congrats
            congratsDescription = congrats.flatMap {
                $0.deckDescription.isEmpty ? nil : DeckDescription.attributed(html: $0.deckDescription)
            }
            phase = .finished
            reviewer.clear()
            onDisplayed?(.finished)
            return
        }
        currentQueue = card.queued.queue
        finishedAt = nil
        phase = .question
        shownAt = Date()
        reviewer.showQuestion(card.rendered.question, answer: card.rendered.answer, bodyClass: card.rendered.bodyClass)
        sounds.show(card.rendered)
        notifyDisplayed(.question)
        if card.options.autoplay, timeboxMessage == nil, let folder = reviewer.mediaFolder {
            audio.play(card.rendered.questionAV, mediaFolder: folder)
        }
        if timeboxMessage == nil { scheduleAutoAdvance() }
    }

    nonisolated static let markedTag = "marked"

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
    nonisolated static func options(
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
        if sounds.handle(command) {
            return
        } else if command == "ans" {
            showAnswer()
        } else if command.hasPrefix("_selection:") {
            hasSelection = command == "_selection:1"
        } else if command.hasPrefix("play:"), let card, let folder = reviewer.mediaFolder {
            // "play:q:0": the first sound on the question side.
            let parts = command.split(separator: ":")
            guard parts.count == 3, let index = Int(parts[2]) else { return }
            let tags = parts[1] == "q" ? card.rendered.questionAV : card.rendered.answerAV
            guard tags.indices.contains(index) else { return }
            audio.play([tags[index]], mediaFolder: folder)
        }
    }

    /// Runs backend work off the main thread. A failure lands in `failure`,
    /// titled with what didn't happen, then the backend's own reason, then
    /// `recovery` when what's left on screen needs saying.
    @discardableResult
    private func run<T: Sendable>(
        failing title: String, recovery: String? = nil,
        _ work: @escaping @Sendable (AnkiBackend) throws -> T
    ) async -> T? {
        do {
            return try await backend.perform(work)
        } catch {
            failure = ActionFailure(title, error: error, recovery: recovery)
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
