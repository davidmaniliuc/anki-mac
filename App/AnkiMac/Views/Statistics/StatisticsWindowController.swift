import AnkiKit
import AppKit
import SwiftUI

/// The Statistics window: desktop's graphs for the current deck, drawn
/// natively. Its toolbar switches between the deck, the collection and a
/// search, and between a year and all of the review history.
final class StatisticsWindowController: NSWindowController, NSWindowDelegate {
    private static var current: StatisticsWindowController?

    private let model: StatisticsModel

    /// Shows the statistics of the selected deck, reloading an open window
    /// since the deck may have changed.
    static func show(collection: CollectionModel) {
        guard collection.isLoaded, let backend = collection.backend else { return }
        if let deckID = collection.selectedDeckID {
            var request = Anki_Decks_DeckId()
            request.did = deckID
            _ = try? backend.setCurrentDeck(request)
        }
        let controller = current ?? StatisticsWindowController(collection: collection, backend: backend)
        current = controller
        controller.model.load()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(collection: CollectionModel, backend: AnkiBackend) {
        model = StatisticsModel(backend: backend)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Statistics.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        let view = StatisticsView(model: model, savePDF: { [weak self] in self?.savePDF() }) { [unowned collection] search in
            BrowserWindowController.show(collection: collection)
            BrowserWindowController.current?.model.search(text: search)
        }
        let host = NSHostingController(rootView: view)
        host.sceneBridgingOptions = [.toolbars]
        // The window keeps its saved size rather than fitting the graphs.
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(Theme.Statistics.defaultSize)
        window.title = Tr.statisticsTitle
        window.minSize = Theme.Statistics.minSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("Statistics")
        if !window.setFrameUsingName("Statistics") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        Self.current = nil
    }

    /// Saves every graph, one per row, on a single tall page, as desktop's
    /// Save PDF button.
    private func savePDF() {
        guard let window, let data = model.data else { return }
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd@HH-mm-ss"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "anki-\(Tr.statisticsStats)-\(format.string(from: .now)).pdf"
        let content = StatisticsPrintView(model: model, data: data)
            .environment(\.colorScheme, .light)
            .background(Color.white)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let renderer = ImageRenderer(content: content)
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
                context.closePDF()
            }
        }
    }
}
