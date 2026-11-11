import AnkiKit
import AppKit

/// The Statistics window: upstream's graphs page for the current deck. The
/// page's own Deck / Collection / Custom Search toggle takes it from there.
final class StatisticsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static var current: StatisticsWindowController?

    private let page: UpstreamPage
    private let collection: CollectionModel

    /// Shows the statistics of the selected deck, reloading an open window
    /// since the deck may have changed.
    static func show(collection: CollectionModel) {
        guard collection.isLoaded, let backend = collection.backend else { return }
        if let deckID = collection.selectedDeckID {
            var request = Anki_Decks_DeckId()
            request.did = deckID
            _ = try? backend.setCurrentDeck(request)
        }
        let controller = current ?? StatisticsWindowController(collection: collection)
        current = controller
        controller.page.load("graphs")
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(collection: CollectionModel) {
        self.collection = collection
        page = UpstreamPage { [unowned collection] method, body in try collection.pageRequest(method, body) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Statistics.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.title = Tr.statisticsTitle
        window.contentView = page.webView
        window.minSize = Theme.Statistics.minSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("Statistics")
        if !window.setFrameUsingName("Statistics") { window.center() }

        let toolbar = NSToolbar(identifier: "Statistics")
        toolbar.delegate = self
        window.toolbar = toolbar

        page.onBridgeCommand = { [weak self] command in
            // A click on a graph bar: "browserSearch: <search>".
            guard let self, command.hasPrefix("browserSearch:") else { return }
            let search = command.dropFirst("browserSearch:".count).trimmingCharacters(in: .whitespaces)
            BrowserWindowController.show(collection: self.collection)
            BrowserWindowController.current?.model.search(text: search)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func savePDF(_ sender: Any?) {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd@HH-mm-ss"
        let stamp = format.string(from: .now)
        page.savePDF(named: "anki-\(Tr.statisticsStats)-\(stamp).pdf", in: window)
    }

    func windowWillClose(_ notification: Notification) {
        Self.current = nil
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .savePDF]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard identifier == .savePDF else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = Tr.statisticsSavePdf
        item.toolTip = Tr.statisticsSavePdf
        item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: Tr.statisticsSavePdf)
        item.target = self
        item.action = #selector(savePDF)
        return item
    }
}

private extension NSToolbarItem.Identifier {
    static let savePDF = Self("savePDF")
}
