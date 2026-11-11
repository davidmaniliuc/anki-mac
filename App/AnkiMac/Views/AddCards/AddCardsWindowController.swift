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
                        collection.errorMessage = "Could not copy the note: \(error)"
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
                collection.errorMessage = "Could not open Add: \(error)"
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
        let host = NSHostingController(rootView: AddCardsView(model: model, actions: actions))
        host.sceneBridgingOptions = [.toolbars]
        window.contentViewController = host
        window.title = Tr.actionsAdd
        window.minSize = Theme.AddCards.minSize
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

/// The Add window that File > Add Note acts on while it is key.
@Observable
final class KeyAddCards {
    static let shared = KeyAddCards()
    var controller: AddCardsWindowController?
}
