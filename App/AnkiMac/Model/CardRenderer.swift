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
}

/// Does what pylib's `TemplateRenderContext.render` and aqt's
/// `prepare_card_text_for_display` do for an existing card.
nonisolated enum CardRenderer {
    static func render(_ card: Anki_Cards_Card, hidePlayButtons: Bool, backend: AnkiBackend) throws -> RenderedCard {
        var request = Anki_CardRendering_RenderExistingCardRequest()
        request.cardID = card.id
        // Full render: there are no Python filter hooks to hand off to.
        request.partialRender = false
        let output = try backend.renderExistingCard(request)

        func side(_ nodes: [Anki_CardRendering_RenderedTemplateNode], question: Bool) throws
            -> (String, [Anki_CardRendering_AVTag])
        {
            var extract = Anki_CardRendering_ExtractAvTagsRequest()
            extract.text = nodes.map(\.text).joined()
            extract.questionSide = question
            let extracted = try backend.extractAvTags(extract)
            var encode = Anki_Generic_String()
            encode.val = typeAnswerFilter(extracted.text, question: question)
            let html = playButtons(in: try backend.encodeIriPaths(encode).val, hide: hidePlayButtons)
            return ("<style>\(output.css)</style>\(html)", extracted.avTags)
        }

        let (question, questionAV) = try side(output.questionNodes, question: true)
        let (answer, answerAV) = try side(output.answerNodes, question: false)
        return RenderedCard(
            question: question, answer: answer, questionAV: questionAV, answerAV: answerAV,
            bodyClass: "card card\(card.templateIdx + 1)")
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

    /// Shows the typing box on the question. The answer-side comparison
    /// (desktop's typeAnsAnswerFilter) is not ported yet, so the marker is
    /// dropped there.
    static func typeAnswerFilter(_ text: String, question: Bool) -> String {
        text.replacing(typeRef) { _ in
            question
                ? #"<center><input type="text" id="typeans" onkeypress="_typeAnsPress();" autocorrect="off" autocapitalize="off" spellcheck="false"></center>"#
                : ""
        }
    }
}
