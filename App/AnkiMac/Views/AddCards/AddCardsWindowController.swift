import AnkiKit
import AppKit
import Observation
import SwiftUI

/// The Add window: one per app, as desktop's. An AppKit window so it can
/// ask before closing over unsaved input.
final class AddCardsWindowController: NSWindowController, NSWindowDelegate {
    private static var current: AddCardsWindowController?

    let model: AddCardsModel
    private let collection: CollectionModel
    private let chrome = AddCardsChrome()
    private var closing = false

    /// Opens the window, or brings it forward. The deck of the card being
    /// studied, if any, picks the defaults, unless `deckID` names one.
    /// `copying` fills the window with a note's type, fields and tags, as
    /// desktop's Create Copy does.
    static func show(
        collection: CollectionModel, deckID: Int64? = nil,
        copying: (note: Anki_Notes_Note, deckID: Int64)? = nil
    ) {
        if let current {
            if let deckID { current.model.deckID = deckID }
            current.window?.makeKeyAndOrderFront(nil)
            if let copying {
                Task {
                    do { try await current.model.setNote(copying.note, deckID: copying.deckID) } catch {
                        collection.failure = ActionFailure("Couldn’t copy this note", error: error)
                    }
                }
            }
            return
        }
        guard let backend = collection.backend else { return }
        let model = AddCardsModel(backend: backend, mediaFolder: collection.paths?.mediaFolder)
        let homeDeck = collection.session?.homeDeckID ?? 0
        Task {
            do {
                try await model.start(homeDeckID: homeDeck)
                if let copying { try await model.setNote(copying.note, deckID: copying.deckID) }
                if let deckID { model.deckID = deckID }
                model.editor.pasteKeepsFormatting = model.pasteKeepsFormatting
                guard current == nil else { return }
                let controller = AddCardsWindowController(model: model, collection: collection)
                current = controller
                controller.window?.makeKeyAndOrderFront(nil)
            } catch {
                collection.failure = ActionFailure("Couldn’t open Add", error: error)
            }
        }
    }

    private init(model: AddCardsModel, collection: CollectionModel) {
        self.model = model
        self.collection = collection
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.AddCards.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        let actions = AddCardsActions(
            add: { [weak self] in self?.add() },
            showInBrowser: { [weak self] search in self?.showInBrowser(search) },
            cardLayout: { [weak self] in self?.showCardLayout() })
        let host = NSHostingView(rootView: AddCardsView(
            model: model, chrome: chrome, collection: collection, actions: actions))
        // The band starts at the window's top, under the traffic lights.
        host.safeAreaRegions = []
        host.sizingOptions = []
        // Inside a plain view, as the Browser's: a hosting view that is the
        // window's content view resizes the window to its own size after
        // every layout, so a window manager setting the frame (AeroSpace)
        // and the view would take turns, the window shaking.
        host.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(origin: .zero, size: Theme.AddCards.defaultSize))
        host.frame = content.bounds
        content.addSubview(host)
        window.contentView = content
        // The title names the window in the Window menu; the band has the controls.
        window.title = Tr.actionsAdd
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Clear, the view painting the canvas: the bar that comes down in
        // full screen is as opaque as the window's background colour.
        window.isOpaque = false
        window.backgroundColor = .clear
        // An empty toolbar, only so the traffic lights sit centred in the
        // band, as the Browser's.
        let toolbar = NSToolbar(identifier: "AddCards")
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = Theme.AddCards.minSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("AddCards")
        if !window.setFrameUsingName("AddCards") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func add(confirmedCloze: Bool = false) {
        // A field being edited as HTML commits on losing focus.
        Task {
            if await model.add(confirmedCloze: confirmedCloze) {
                await collection.refreshDecks()
            }
        }
    }

    private func showInBrowser(_ search: String) {
        BrowserWindowController.show(collection: collection)
        BrowserWindowController.current?.model.search(text: search)
    }

    private func showCardLayout() {
        CardTemplatesWindowController.show(collection: collection, note: model.currentNote, ord: 0)
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing, model.hasUnsavedInput else { return true }
        let alert = NSAlert()
        alert.messageText = Tr.addingDiscardCurrentInput
        alert.addButton(withTitle: Tr.addingKeepEditing)
        let discard = alert.addButton(withTitle: "Discard")
        discard.hasDestructiveAction = true
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self, response == .alertSecondButtonReturn else { return }
            closing = true
            close()
        }
        return false
    }

    /// The toolbar hides with the menu bar in full screen, as the Browser's,
    /// and the band stays in reach.
    func window(
        _ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []
    ) -> NSApplication.PresentationOptions {
        // AppKit raises unless the menu bar hides too.
        proposedOptions.contains(.autoHideMenuBar) ? proposedOptions.union(.autoHideToolbar) : proposedOptions
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        chrome.fullScreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        if let window { FullScreenTitlebar.dress(window, true) }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        chrome.fullScreen = false
        if let window { FullScreenTitlebar.dress(window, false) }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        KeyAddCards.shared.controller = self
    }

    func windowDidResignKey(_ notification: Notification) {
        if KeyAddCards.shared.controller === self { KeyAddCards.shared.controller = nil }
    }

    func windowWillClose(_ notification: Notification) {
        if KeyAddCards.shared.controller === self { KeyAddCards.shared.controller = nil }
        Self.current = nil
    }
}

struct AddCardsActions {
    let add: () -> Void
    let showInBrowser: (String) -> Void
    let cardLayout: () -> Void
}

/// Whether the window is in full screen, where the traffic lights leave
/// the band's leading edge.
@Observable
final class AddCardsChrome {
    var fullScreen = false
}

/// The Add window that File > Add Note acts on while it is key.
@Observable
final class KeyAddCards {
    static let shared = KeyAddCards()
    var controller: AddCardsWindowController?
}
