import AppKit

/// A Card Info window: upstream's card-info page for one card.
///
/// There is one window per `Kind`, as on desktop: the browser's follows the
/// current row, the reviewer's the card on screen, and "previous" shows the
/// card answered last. Showing a kind that is open updates it in place.
final class CardInfoWindowController: NSWindowController, NSWindowDelegate {
    enum Kind: CaseIterable {
        case browser, reviewer, previousReviewer

        var title: String {
            switch self {
            case .browser: Tr.cardStatsCurrentCard(context: "Browse")
            case .reviewer: Tr.cardStatsCurrentCard(context: Tr.decksStudy)
            case .previousReviewer: Tr.cardStatsPreviousCard(context: Tr.decksStudy)
            }
        }

        var frameName: String {
            switch self {
            case .browser: "CardInfoBrowser"
            case .reviewer: "CardInfoReviewer"
            case .previousReviewer: "CardInfoPreviousReviewer"
            }
        }
    }

    private static var open: [Kind: CardInfoWindowController] = [:]

    private let kind: Kind
    private let page: UpstreamPage

    /// Opens (or updates and raises) the Card Info window for a card. This is
    /// what the reviewer's I key and Card Info menu item call.
    static func show(cardID: Int64, kind: Kind = .reviewer, collection: CollectionModel) {
        guard collection.isLoaded else { return }
        if let controller = open[kind] {
            controller.display(cardID)
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = CardInfoWindowController(kind: kind, collection: collection)
        open[kind] = controller
        controller.display(cardID)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Follows the card on screen: updates the window of `kind` if it is open, without raising it.
    static func update(cardID: Int64?, kind: Kind) {
        guard let controller = open[kind] else { return }
        controller.display(cardID)
    }

    private init(kind: Kind, collection: CollectionModel) {
        self.kind = kind
        page = UpstreamPage { [unowned collection] method, body in try collection.pageRequest(method, body) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Statistics.cardInfoSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.title = kind.title
        window.contentView = page.webView
        window.minSize = Theme.Statistics.cardInfoMinSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName(kind.frameName)
        if !window.setFrameUsingName(kind.frameName) { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var shownCardID: Int64?

    /// The page swaps cards itself (`anki.updateCard`) once it has loaded.
    private func display(_ cardID: Int64?) {
        let id = cardID.map(String.init) ?? "0"
        if shownCardID == nil || page.webView.isLoading {
            page.load("card-info/\(id)")
        } else if cardID != shownCardID {
            page.evaluate("anki.updateCard('\(id)');")
        }
        shownCardID = cardID ?? 0
    }

    func windowWillClose(_ notification: Notification) {
        Self.open[kind] = nil
    }
}
