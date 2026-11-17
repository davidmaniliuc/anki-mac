import AppKit

/// What a drag in the Browser carries, one pasteboard item per row: the
/// table's cards or notes ("cards:123"), or the sidebar's decks by id and tags
/// by full name. Only offered within the app.
enum BrowserDrag {
    static let row = NSPasteboard.PasteboardType("io.github.davidmaniliuc.AnkiMac.browser-row")
    static let deck = NSPasteboard.PasteboardType("io.github.davidmaniliuc.AnkiMac.browser-deck")
    static let tag = NSPasteboard.PasteboardType("io.github.davidmaniliuc.AnkiMac.browser-tag")

    static func item(_ mode: BrowserMode, id: Int64) -> NSPasteboardItem {
        item("\(mode.rawValue):\(id)", type: row)
    }

    static func item(_ text: String, type: NSPasteboard.PasteboardType) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(text, forType: type)
        return item
    }

    /// The dragged table rows, all of one mode.
    static func selection(_ pasteboard: NSPasteboard) -> BrowserModel.Selection? {
        let rows = strings(pasteboard, type: row).compactMap { text -> (BrowserMode, Int64)? in
            let parts = text.split(separator: ":")
            guard parts.count == 2, let mode = BrowserMode(rawValue: String(parts[0])), let id = Int64(parts[1])
            else { return nil }
            return (mode, id)
        }
        guard let mode = rows.first?.0, rows.allSatisfy({ $0.0 == mode }) else { return nil }
        return BrowserModel.Selection(mode: mode, ids: rows.map(\.1))
    }

    static func deckIDs(_ pasteboard: NSPasteboard) -> [Int64] {
        strings(pasteboard, type: deck).compactMap { Int64($0) }
    }

    static func tags(_ pasteboard: NSPasteboard) -> [String] {
        strings(pasteboard, type: tag)
    }

    private static func strings(_ pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> [String] {
        (pasteboard.pasteboardItems ?? []).compactMap { $0.string(forType: type) }
    }
}
