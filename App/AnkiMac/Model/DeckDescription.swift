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

    /// Desktop shows the description as HTML in a web view. Here the HTML is
    /// converted to styled text in the system font and colours, so it follows
    /// dark mode, with links kept clickable. Images are dropped: they would
    /// be fetched while converting, and collection media can't resolve here.
    static func attributed(html: String) -> AttributedString {
        let cleaned = html.replacing(/<img\b[^>]*>/.ignoresCase(), with: "")
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
