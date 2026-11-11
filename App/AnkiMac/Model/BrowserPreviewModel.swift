import AnkiKit
import Foundation
import Observation

/// Which card the previewer shows and which side of it, as desktop's
/// `_state`, with the "Back Side Only" switch that pins it to the answer.
nonisolated struct PreviewPosition: Equatable, Sendable {
    enum Side: Sendable { case question, answer }

    private(set) var cardID: Int64?
    private(set) var side: Side
    private(set) var backSideOnly: Bool

    init(backSideOnly: Bool) {
        self.backSideOnly = backSideOnly
        side = backSideOnly ? .answer : .question
    }

    /// The browser's selection is on `id`; a different card starts on its question.
    mutating func follow(_ id: Int64) {
        guard id != cardID else { return }
        cardID = id
        side = backSideOnly ? .answer : .question
    }

    mutating func setBackSideOnly(_ on: Bool) {
        backSideOnly = on
        side = on ? .answer : .question
    }

    var canStepBackWithinCard: Bool { side == .answer && !backSideOnly }
    var canStepForwardWithinCard: Bool { side == .question }

    /// False when the card is already on its first side: the browser goes to the previous card.
    mutating func stepBackWithinCard() -> Bool {
        guard canStepBackWithinCard else { return false }
        side = .question
        return true
    }

    /// False when the card is already on its last side: the browser goes to the next card.
    mutating func stepForwardWithinCard() -> Bool {
        guard canStepForwardWithinCard else { return false }
        side = .answer
        return true
    }
}

/// What a card looked like when it was last drawn; the previewer draws again only when this changes.
nonisolated private struct PreviewStamp: Equatable, Sendable {
    let cardID: Int64
    let side: PreviewPosition.Side
    let noteMod: UInt32
}

nonisolated private struct PreviewedCard: Sendable {
    let stamp: PreviewStamp
    let rendered: RenderedCard
    let autoplay: Bool
}

/// The flag and mark are drawn every time; the card itself only when it changed.
nonisolated private struct PreviewLoad: Sendable {
    let flag: CardFlag
    let isMarked: Bool
    let changed: PreviewedCard?
}

/// Desktop's `BrowserPreviewer`: shows the browser's selected card, question
/// then answer, in the same web view the study screen uses, and follows the
/// browser's selection.
@Observable
final class BrowserPreviewModel {
    let web = ReviewerWebController()
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var flag = CardFlag.none
    private(set) var isMarked = false
    private(set) var backSideOnly: Bool
    /// Called when the browser no longer has exactly one card selected.
    @ObservationIgnored var onSelectionLost: (() -> Void)?

    private let browser: BrowserModel
    private let audio = AudioPlayer()
    @ObservationIgnored private var position: PreviewPosition
    @ObservationIgnored private var shown: PreviewedCard?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var lastRender: ContinuousClock.Instant?

    /// Desktop avoids drawing in quick succession, as when arrowing through rows.
    private static let minRenderInterval = Duration.milliseconds(300)

    init(browser: BrowserModel) {
        self.browser = browser
        var request = Anki_Config_GetConfigBoolRequest()
        request.key = .previewBothSides
        let backOnly = (try? browser.collection.backend?.getConfigBool(request).val) ?? false
        backSideOnly = backOnly
        position = PreviewPosition(backSideOnly: backOnly)
        web.mediaFolder = browser.collection.paths?.mediaFolder
        web.prepare()
        web.onCommand = { [weak self] command in self?.handle(command) }
    }

    /// Reads the browser's selection. Run inside `track`: it must read only
    /// the browser's state, so nothing it sets on this model starts it again.
    func browserChanged() {
        guard browser.singleSelectedRow != nil else {
            onSelectionLost?()
            return
        }
        _ = browser.rowsVersion
        _ = browser.idsVersion
        guard let id = browser.currentCardID else {
            refreshButtons()
            return
        }
        position.follow(id)
        refreshButtons()
        render()
    }

    func back() {
        if position.stepBackWithinCard() {
            refreshButtons()
            render()
        } else {
            browser.moveSelection(by: -1)
        }
    }

    func forward() {
        if position.stepForwardWithinCard() {
            refreshButtons()
            render()
        } else {
            browser.moveSelection(by: 1)
        }
    }

    func setBackSideOnly(_ on: Bool) {
        position.setBackSideOnly(on)
        backSideOnly = on
        if let backend = browser.collection.backend {
            var request = Anki_Config_SetConfigBoolRequest()
            request.key = .previewBothSides
            request.value = on
            _ = try? backend.setConfigBool(request)
        }
        refreshButtons()
        render()
    }

    func replayAudio() {
        guard let shown, let folder = web.mediaFolder else { return }
        audio.play(shown.stamp.side == .answer ? shown.rendered.answerAV : shown.rendered.questionAV, mediaFolder: folder)
    }

    func close() {
        renderTask?.cancel()
        audio.stop()
        web.onCommand = nil
    }

    private func refreshButtons() {
        canGoBack = position.canStepBackWithinCard || browser.hasPreviousRow
        canGoForward = position.canStepForwardWithinCard || browser.hasNextRow
    }

    // MARK: Drawing

    private func render() {
        renderTask?.cancel()
        let wait = lastRender.map { max(.zero, Self.minRenderInterval - $0.duration(to: .now)) } ?? .zero
        guard let backend = browser.collection.backend else { return }
        renderTask = Task {
            if wait > .zero { try? await Task.sleep(for: wait) }
            guard !Task.isCancelled, let cardID = position.cardID else { return }
            lastRender = .now
            let side = position.side
            let previous = shown?.stamp
            let loaded = try? await backend.perform { backend in
                try Self.load(cardID, side: side, unlessStamp: previous, backend: backend)
            }
            guard !Task.isCancelled, let loaded else { return }
            flag = loaded.flag
            isMarked = loaded.isMarked
            if let card = loaded.changed { display(card) }
        }
    }

    private func display(_ card: PreviewedCard) {
        shown = card
        let rendered = card.rendered
        let side = card.stamp.side
        if side == .question {
            web.showQuestion(rendered.question, answer: rendered.answer, bodyClass: rendered.bodyClass)
        } else {
            web.showAnswer(rendered.answer, bodyClass: rendered.bodyClass)
        }
        let tags: [Anki_CardRendering_AVTag]
        if !card.autoplay {
            tags = []
        } else if backSideOnly {
            // The answer is on screen at once, so the question's audio plays first and isn't repeated.
            tags = rendered.questionAV + rendered.answerAV.filter { !rendered.questionAV.contains($0) }
        } else {
            tags = side == .question ? rendered.questionAV : rendered.answerAV
        }
        if let folder = web.mediaFolder {
            audio.play(tags, mediaFolder: folder)
        }
    }

    /// Renders nothing when the card is drawn already as `unlessStamp` says.
    nonisolated private static func load(
        _ cardID: Int64, side: PreviewPosition.Side, unlessStamp: PreviewStamp?, backend: AnkiBackend
    ) throws -> PreviewLoad {
        var cardRequest = Anki_Cards_CardId()
        cardRequest.cid = cardID
        let card = try backend.getCard(cardRequest)
        var noteRequest = Anki_Notes_NoteId()
        noteRequest.nid = card.noteID
        let note = try backend.getNote(noteRequest)
        let stamp = PreviewStamp(cardID: cardID, side: side, noteMod: note.mtimeSecs)
        let flag = CardFlag(cardFlags: card.flags)
        let isMarked = note.tags.contains { $0.caseInsensitiveCompare(StudySession.markedTag) == .orderedSame }
        if stamp == unlessStamp { return PreviewLoad(flag: flag, isMarked: isMarked, changed: nil) }

        var hideKey = Anki_Config_GetConfigBoolRequest()
        hideKey.key = .hideAudioPlayButtons
        let rendered = try CardRenderer.render(
            card, hidePlayButtons: try backend.getConfigBool(hideKey).val, stripTypeBoxes: true, backend: backend)
        let options = try StudySession.options(for: card, cache: DeckOptionsCache(), backend: backend)
        return PreviewLoad(
            flag: flag, isMarked: isMarked,
            changed: PreviewedCard(stamp: stamp, rendered: rendered, autoplay: options.autoplay))
    }

    /// A click on a play button: "play:q:0" is the first sound on the question.
    private func handle(_ command: String) {
        guard command.hasPrefix("play:"), let shown, let folder = web.mediaFolder else { return }
        let parts = command.split(separator: ":")
        guard parts.count == 3, let index = Int(parts[2]) else { return }
        let tags = parts[1] == "q" ? shown.rendered.questionAV : shown.rendered.answerAV
        guard tags.indices.contains(index) else { return }
        audio.play([tags[index]], mediaFolder: folder)
    }
}
