import AnkiKit
import Foundation

/// A card's question and answer, ready for the reviewer page, and the audio
/// each side plays.
nonisolated struct RenderedCard: Sendable {
    let question: String
    let answer: String
    let questionAV: [Anki_CardRendering_AVTag]
    let answerAV: [Anki_CardRendering_AVTag]
    /// Classes for <body>, as desktop's `body_classes_for_card_ord`, minus the
    /// theme classes, which the page manages itself.
    let bodyClass: String
    /// nil when the card has no type-in-the-answer box.
    let typeAnswer: TypeAnswer?
}

/// What a card's `[[type:Field]]` box is compared against, found when the
/// question is rendered (desktop's `typeCorrect`, `_combining`, `typeFont`).
nonisolated struct TypeAnswer: Sendable {
    let fieldName: String
    /// The raw field, or for `type:cloze:` just the text of the cloze being asked.
    let expected: String
    /// False for `type:nc:Field`: accents and other combining marks must match.
    let combining: Bool
    let fontName: String
    let fontSize: UInt32
}

/// Does what pylib's `TemplateRenderContext.render` and aqt's
/// `prepare_card_text_for_display` do for an existing card.
nonisolated enum CardRenderer {
    /// `stripTypeBoxes` is the previewer's: a `[[type:Field]]` marker is
    /// dropped instead of becoming a box nobody can answer.
    static func render(
        _ card: Anki_Cards_Card, hidePlayButtons: Bool, stripTypeBoxes: Bool = false, backend: AnkiBackend
    ) throws -> RenderedCard {
        var request = Anki_CardRendering_RenderExistingCardRequest()
        request.cardID = card.id
        // Full render: there are no Python filter hooks to hand off to.
        request.partialRender = false
        let output = try backend.renderExistingCard(request)

        func side(_ nodes: [Anki_CardRendering_RenderedTemplateNode]) throws -> (text: String, av: [Anki_CardRendering_AVTag]) {
            var extract = Anki_CardRendering_ExtractAvTagsRequest()
            extract.text = nodes.map(\.text).joined()
            let extracted = try backend.extractAvTags(extract)
            return (extracted.text, extracted.avTags)
        }

        func finish(_ text: String) throws -> String {
            var encode = Anki_Generic_String()
            encode.val = text
            let html = playButtons(in: try backend.encodeIriPaths(encode).val, hide: hidePlayButtons)
            return "<style>\(output.css)</style>\(html)"
        }

        let questionSide = try side(output.questionNodes)
        let answerSide = try side(output.answerNodes)
        let box = stripTypeBoxes ? TypeBox.absent : try typeBox(in: questionSide.text, card: card, backend: backend)
        let typeAnswer: TypeAnswer?
        var questionText = questionSide.text
        var answerText = answerSide.text
        switch box {
        case .none:
            typeAnswer = nil
        case .absent:
            typeAnswer = nil
            questionText.replace(typeRef, with: "")
            answerText.replace(typeRef, with: "")
        case .message(let message):
            typeAnswer = nil
            questionText.replace(typeRef, with: message)
            answerText.replace(typeRef, with: "")
        case .input(let found):
            typeAnswer = found
            questionText.replace(typeRef, with: inputBox(found))
        }
        return RenderedCard(
            question: try finish(questionText), answer: try finish(answerText),
            questionAV: questionSide.av, answerAV: answerSide.av,
            bodyClass: "card card\(card.templateIdx + 1)", typeAnswer: typeAnswer)
    }

    // Regex is immutable but not marked Sendable.
    nonisolated(unsafe) private static let avRef = #/\[anki:(play:(.):(\d+))\]/#

    /// As aqt.sound.av_refs_to_play_icons; clicks come back as `play:q:0`.
    static func playButtons(in text: String, hide: Bool) -> String {
        text.replacing(avRef) { match in
            if hide { return "" }
            return """
                <a class="replay-button soundLink" href=# onclick="pycmd('\(match.output.1)'); return false;" draggable="false">
                    <svg class="playImage" viewBox="0 0 64 64" version="1.1">
                        <circle cx="32" cy="32" r="29" />
                        <path d="M56.502,32.301l-37.502,20.101l0.329,-40.804l37.173,20.703Z" />
                    </svg>
                </a>
                """
        }
    }

    nonisolated(unsafe) private static let typeRef = #/\[\[type:(.+?)\]\]/#

    private enum TypeBox {
        /// No `[[type:]]` on the card.
        case none
        /// A box: its page markup and what the typed text is compared to.
        case input(TypeAnswer)
        /// The field is empty, so the marker just disappears.
        case absent
        /// The marker can't be used (unknown field, cloze without a match).
        case message(String)
    }

    /// Desktop's `typeAnsQuestionFilter`, up to the point where it rewrites the text.
    private static func typeBox(in question: String, card: Anki_Cards_Card, backend: AnkiBackend) throws -> TypeBox {
        guard let match = question.firstMatch(of: typeRef) else { return .none }
        var name = String(match.output.1)
        var clozeOrdinal: UInt32?
        var combining = true
        // Mirrors desktop, including "cloze:nc:Text" naming the field "nc".
        if name.hasPrefix("cloze:") {
            clozeOrdinal = card.templateIdx + 1
            name = String(name.split(separator: ":", omittingEmptySubsequences: false)[1])
        }
        if name.hasPrefix("nc:") {
            combining = false
            name = String(name.split(separator: ":", omittingEmptySubsequences: false)[1])
        }

        var noteID = Anki_Notes_NoteId()
        noteID.nid = card.noteID
        let note = try backend.getNote(noteID)
        var notetypeID = Anki_Notetypes_NotetypeId()
        notetypeID.ntid = note.notetypeID
        let fields = try backend.getNotetype(notetypeID).fields
        guard let index = fields.firstIndex(where: { $0.name == name }), note.fields.indices.contains(index) else {
            return .message(clozeOrdinal != nil ? "Please run Tools>Empty Cards" : "Type answer: unknown field \(name)")
        }

        let field = fields[index]
        var expected = note.fields[index]
        if let clozeOrdinal {
            var request = Anki_CardRendering_ExtractClozeForTypingRequest()
            request.text = expected
            request.ordinal = clozeOrdinal
            expected = try backend.extractClozeForTyping(request).val
            if expected.isEmpty { return .message("Please run Tools>Empty Cards") }
        }
        if expected.isEmpty { return .absent }
        return .input(TypeAnswer(
            fieldName: name, expected: expected, combining: combining,
            fontName: field.config.fontName, fontSize: field.config.fontSize))
    }

    private static func inputBox(_ answer: TypeAnswer) -> String {
        """
        <center>
        <input type=text id=typeans onkeypress="_typeAnsPress();" autocorrect="off" autocapitalize="off" spellcheck="false"
           style="font-family: '\(answer.fontName)'; font-size: \(answer.fontSize)px;">
        </center>
        """
    }

    /// Desktop's `typeAnsAnswerFilter`: the comparison goes where the marker was.
    static func answerHTML(_ html: String, typeAnswer: TypeAnswer, typed: String, backend: AnkiBackend) throws -> String {
        var request = Anki_CardRendering_CompareAnswerRequest()
        request.expected = typeAnswer.expected
        request.provided = typed
        request.combining = typeAnswer.combining
        let comparison = try backend.compareAnswer(request).val

        let separator = "<hr id=answer>"
        let hadSeparator = html.contains(separator)
        let text = html.replacing(separator, with: "")
        // With {{FrontSide}} the marker sits above the separator; the
        // separator has to land in front of the comparison.
        if hadSeparator, text.firstMatch(of: typeRef) == nil { return html }
        let block = "<div style=\"font-family: '\(typeAnswer.fontName)'; font-size: \(typeAnswer.fontSize)px\">\(comparison)</div>"
        return text.replacing(typeRef) { _ in (hadSeparator ? separator : "") + block }
    }
}
