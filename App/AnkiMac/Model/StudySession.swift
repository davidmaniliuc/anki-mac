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
    private(set) var counts = (new: 0, learn: 0, review: 0)
    private(set) var currentQueue: Anki_Scheduler_QueuedCards.Queue?
    private(set) var canUndo = false
    var errorMessage: String?
    /// Called once a question, an answer or the end of the session is on
    /// screen. Used by the bench driver.
    var onDisplayed: ((Phase) -> Void)?

    private let backend: AnkiBackend
    private let reviewer: ReviewerWebController
    private let audio = AudioPlayer()
    private var shownAt = Date()
    private var busy = false

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
        guard phase == .question, let card else { return }
        phase = .answer
        reviewer.showAnswer(card.rendered.answer)
        notifyDisplayed(.answer)
        if card.options.autoplay, let folder = reviewer.mediaFolder {
            audio.play(card.rendered.answerAV, mediaFolder: folder)
        }
    }

    func answer(_ rating: Rating) {
        guard phase == .answer, let card, !busy else { return }
        audio.stop()
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
        guard canUndo, !busy else { return }
        audio.stop()
        busy = true
        Task {
            await loadNext { backend in _ = try backend.undo() }
        }
    }

    func replayAudio() {
        guard let card, let folder = reviewer.mediaFolder else { return }
        let tags = phase == .answer ? card.rendered.answerAV : card.rendered.questionAV
        audio.play(tags, mediaFolder: folder)
    }

    // MARK: -

    /// Runs `change` (answer, undo, pick deck), then fetches and renders the
    /// next card, in one background call. Callers set `busy` first, so a
    /// second key press can't answer the same card twice.
    private func loadNext(after change: @escaping @Sendable (AnkiBackend) throws -> Void) async {
        defer { busy = false }
        let configCache = self.configCache
        let next: (StudyCard?, Anki_Scheduler_QueuedCards, Bool)? = await run { backend in
            try change(backend)
            var request = Anki_Scheduler_GetQueuedCardsRequest()
            request.fetchLimit = 1
            let queue = try backend.getQueuedCards(request)
            let canUndo = !(try backend.getUndoStatus().undo.isEmpty)
            guard let queued = queue.cards.first else { return (nil, queue, canUndo) }

            var hideKey = Anki_Config_GetConfigBoolRequest()
            hideKey.key = .hideAudioPlayButtons
            let rendered = try CardRenderer.render(
                queued.card, hidePlayButtons: try backend.getConfigBool(hideKey).val, backend: backend)
            let intervals = try backend.describeNextStates(queued.states).vals
            let options = try Self.options(for: queued.card, cache: configCache, backend: backend)
            return (StudyCard(queued: queued, rendered: rendered, intervals: intervals, options: options), queue, canUndo)
        }
        BenchDriver.trace("first_card_rendered")
        guard let (card, queue, canUndo) = next else { return }
        self.canUndo = canUndo
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
        reviewer.drawFlag(Int(card.queued.card.flags & 0b111))
        notifyDisplayed(.question)
        if card.options.autoplay, let folder = reviewer.mediaFolder {
            audio.play(card.rendered.questionAV, mediaFolder: folder)
        }
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
}
