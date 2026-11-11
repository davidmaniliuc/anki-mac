import AnkiKit
import AppKit
import Foundation

/// What the overview shows under a deck's name: the stored text and its
/// Markdown flag, as the Description sheet edits them, and the text
/// rendered for display.
struct DeckDescription: Identifiable, Equatable {
    let id: Int64
    var text: String
    var markdown: Bool
    var body: AttributedString

    /// The text of a filtered deck, which has no description of its own.
    static var filteredNote: String {
        "\(Tr.studyingThisIsASpecialDeckFor) \(Tr.studyingCardsWillBeAutomaticallyReturnedTo) \(Tr.studyingDeletingThisDeckFromTheDeck)"
    }

    /// Tags that survive sanitizing, all plain text formatting. Every other
    /// tag is dropped and its text kept, so a description can't make the
    /// HTML importer fetch anything.
    private static let allowedTags: Set<String> = [
        "b", "i", "u", "em", "strong", "a", "br", "p", "div", "span", "ul", "ol", "li",
        "h1", "h2", "h3", "h4", "h5", "h6", "code", "pre", "blockquote",
    ]

    private static let tag = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)(?=[\s\/>])((?:"[^"]*"|'[^']*'|[^'">])*)>/
    private static let href = /\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/.ignoresCase()
    private static let comment = /<!--.*?-->/.dotMatchesNewlines()
    private static let rawText = /<(script|style|title|head|template|noscript)\b.*?<\/\1\s*>/
        .ignoresCase().dotMatchesNewlines()

    /// The HTML cut down to `allowedTags`, with no attributes but a web or
    /// mail `href` on links. A `<` that starts no kept tag is escaped.
    static func sanitized(html: String) -> String {
        let source = html.replacing(comment, with: "").replacing(rawText, with: "")
        var out = ""
        var rest = source[...]
        func text(_ part: Substring) { out += part.replacing("<", with: "&lt;") }
        while let match = rest.firstMatch(of: tag) {
            text(rest[rest.startIndex..<match.range.lowerBound])
            rest = rest[match.range.upperBound...]
            let name = match.2.lowercased()
            guard allowedTags.contains(name) else { continue }
            if !match.1.isEmpty {
                if name != "br" { out += "</\(name)>" }
            } else if name == "a", let link = match.3.firstMatch(of: href) {
                let url = String(link.1 ?? link.2 ?? link.3 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let safe = ["http://", "https://", "mailto:"].contains { url.lowercased().hasPrefix($0) }
                out += safe ? "<a href=\"\(url.replacing("\"", with: "&quot;"))\">" : "<a>"
            } else {
                out += "<\(name)>"
            }
        }
        text(rest)
        return out
    }

    /// Desktop shows the description as HTML in a web view. Here the HTML is
    /// sanitized, then converted to styled text in the system font and
    /// colours, so it follows dark mode, with links kept clickable. Images
    /// and every other resource are dropped: they would be fetched while
    /// converting, and collection media can't resolve here.
    static func attributed(html: String) -> AttributedString {
        let cleaned = sanitized(html: html)
        let styled = "<style>body { font-family: -apple-system; font-size: \(Int(NSFont.systemFontSize))px; }</style>"
            + cleaned
        guard let data = styled.data(using: .utf8),
            let text = try? NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil)
        else { return AttributedString(cleaned) }
        text.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: text.length))
        while text.length > 0, text.string.last?.isNewline == true {
            text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
        }
        return (try? AttributedString(text, including: \.appKit)) ?? AttributedString(text.string)
    }
}
