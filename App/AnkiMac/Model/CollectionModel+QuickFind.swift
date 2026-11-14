import AnkiKit
import Foundation

/// A note Quick Find turned up: its first field as one line of text, and
/// the deck its first card is in.
nonisolated struct QuickFindNote: Identifiable, Hashable, Sendable {
    let id: Int64
    let text: String
    let deckID: Int64
}

extension CollectionModel {
    /// The first notes matching what was typed, searched as the Browser
    /// would. Text the search can't parse finds nothing.
    func quickFindNotes(_ text: String, limit: Int) async -> [QuickFindNote] {
        guard let backend, !text.isEmpty else { return [] }
        return (try? await backend.perform { backend in
            var request = Anki_Search_SearchRequest()
            request.search = text
            request.order.none = Anki_Generic_Empty()
            return try backend.searchNotes(request).ids.prefix(limit).map { id in
                var noteID = Anki_Notes_NoteId()
                noteID.nid = id
                var line = Anki_CardRendering_HtmlToTextLineRequest()
                line.text = try backend.getNote(noteID).fields.first ?? ""
                var cards = Anki_Search_SearchRequest()
                cards.search = "nid:\(id)"
                cards.order.none = Anki_Generic_Empty()
                var cardID = Anki_Cards_CardId()
                cardID.cid = try backend.searchCards(cards).ids.first ?? 0
                return QuickFindNote(
                    id: id, text: try backend.htmlToTextLine(line).val, deckID: try backend.getCard(cardID).deckID)
            }
        }) ?? []
    }

    /// Leaves any session for Today, as picking it in the sidebar does.
    func showToday() {
        quickFindPresented = false
        if session != nil { stopStudying() }
        page = .today
    }

    /// Shows the note in the Browser, with its cards listed.
    func showInBrowser(note id: Int64) {
        quickFindPresented = false
        BrowserWindowController.show(collection: self)
        BrowserWindowController.current?.model.search(text: "nid:\(id)")
    }

    /// Quick Find's last row: the Browser, searching what was typed.
    func continueSearchInBrowser(_ text: String) {
        quickFindPresented = false
        BrowserWindowController.show(collection: self)
        BrowserWindowController.current?.model.search(text: text)
    }
}
