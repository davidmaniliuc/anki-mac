import AnkiKit
import AppKit
import Observation
import SwiftUI

/// The Deck Options window: a SwiftUI form in an AppKit window, which can
/// refuse to close while there are unsaved changes, as desktop's does.
final class DeckOptionsWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [Int64: DeckOptionsWindowController] = [:]

    let model: DeckOptionsModel
    private let collection: CollectionModel
    private var closeAfterSave = false

    /// Shows the options of a deck, bringing its window forward if open.
    static func show(deckID: Int64, collection: CollectionModel) {
        if let controller = open[deckID] {
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let backend = collection.backend else { return }
        Task {
            do {
                let model = try await DeckOptionsModel.load(deckID: deckID, backend: backend)
                guard open[deckID] == nil else { return }
                let controller = DeckOptionsWindowController(model: model, collection: collection)
                open[deckID] = controller
                controller.window?.makeKeyAndOrderFront(nil)
            } catch {
                collection.failure = ActionFailure("Couldn’t open the deck options", error: error)
            }
        }
    }

    private init(model: DeckOptionsModel, collection: CollectionModel) {
        self.model = model
        self.collection = collection
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.DeckOptions.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        let actions = DeckOptionsActions(
            save: { [weak self] mode in self?.save(mode: mode) },
            close: { [weak self] in self?.closeSaved() },
            showError: { [weak self] failure in self?.showError(failure) })
        let host = NSHostingController(rootView: DeckOptionsView(model: model, actions: actions))
        host.sceneBridgingOptions = [.toolbars]
        window.contentViewController = host
        window.title = Tr.actionsOptionsFor(val: model.deckName)
        window.minSize = Theme.DeckOptions.minSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("DeckOptions")
        if !window.setFrameUsingName("DeckOptions") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Actions

    /// Saves and closes, as desktop does.
    func save(mode: Anki_DeckConfig_UpdateDeckConfigsMode = .normal) {
        // A text field being edited commits its value when it loses focus.
        window?.makeFirstResponder(nil)
        Task {
            do {
                try await model.save(mode: mode)
                closeSaved()
            } catch {
                showError(ActionFailure("Couldn’t save the deck options", error: error))
            }
        }
    }

    private func closeSaved() {
        collection.deckOptionsChanged()
        closeAfterSave = true
        close()
    }

    func showError(_ failure: ActionFailure) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = failure.title
        alert.informativeText = failure.detail
        alert.beginSheetModal(for: window)
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
        guard !closeAfterSave, model.isModified else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to the options for \(model.deckName)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: Tr.deckConfigSaveButton)
        alert.addButton(withTitle: "Cancel")
        let discard = alert.addButton(withTitle: "Don't Save")
        discard.hasDestructiveAction = true
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn: save()
            case .alertThirdButtonReturn:
                closeAfterSave = true
                close()
            default: break
            }
        }
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        KeyDeckOptions.shared.controller = self
    }

    func windowDidResignKey(_ notification: Notification) {
        if KeyDeckOptions.shared.controller === self { KeyDeckOptions.shared.controller = nil }
    }

    func windowWillClose(_ notification: Notification) {
        if KeyDeckOptions.shared.controller === self { KeyDeckOptions.shared.controller = nil }
        model.cancelBackgroundWork()
        Self.open[model.deckID] = nil
    }
}

/// What the form asks of its window. Closures, so the view doesn't keep the
/// controller alive.
struct DeckOptionsActions {
    let save: (Anki_DeckConfig_UpdateDeckConfigsMode) -> Void
    /// Closes once the form saved by itself (Optimize All Presets).
    let close: () -> Void
    let showError: (ActionFailure) -> Void
}

/// The options window that the File menu's Save acts on while it is key.
@Observable
final class KeyDeckOptions {
    static let shared = KeyDeckOptions()
    var controller: DeckOptionsWindowController?
}
