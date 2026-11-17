import AppKit
import SwiftUI

/// A Card Info window for one card, native SwiftUI over the backend's card stats.
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
    private let model: CardInfoModel

    /// Opens (or updates and raises) the Card Info window for a card. This is
    /// what the reviewer's I key and Card Info menu item call.
    static func show(cardID: Int64, kind: Kind = .reviewer, collection: CollectionModel) {
        guard collection.isLoaded, collection.backend != nil else { return }
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
        model = CardInfoModel(backend: collection.backend!)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.CardInfo.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        let host = NSHostingView(rootView: CardInfoView(
            model: model, title: kind.title, close: { [weak window] in window?.close() }))
        // The band starts at the window's top, under the traffic lights.
        host.safeAreaRegions = []
        host.sizingOptions = []
        // Inside a plain view, as Add's, so the hosting view never resizes the window.
        host.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(origin: .zero, size: Theme.CardInfo.size))
        host.frame = content.bounds
        content.addSubview(host)
        window.contentView = content
        // The title names the window in the Window menu; the band shows it too.
        window.title = kind.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.Palette.canvasNS
        // An empty toolbar, only so the traffic lights sit centred in the band.
        let toolbar = NSToolbar(identifier: "CardInfo")
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // It sits beside the study screen or the Browser, so it can join
        // their full-screen space, and its green button zooms.
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentMinSize = Theme.CardInfo.minSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName(kind.frameName)
        if !window.setFrameUsingName(kind.frameName) { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func display(_ cardID: Int64?) {
        model.show(cardID)
    }

    func windowWillClose(_ notification: Notification) {
        Self.open[kind] = nil
    }
}
