import AnkiKit
import AppKit
import Observation
import SwiftUI

/// The Deck Options window: a SwiftUI page in an AppKit window, which can
/// refuse to close while there are unsaved changes, as desktop's does.
final class DeckOptionsWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [Int64: DeckOptionsWindowController] = [:]

    let model: DeckOptionsModel
    private let collection: CollectionModel
    private let chrome = BandChrome()
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
        let host = NSHostingView(rootView: DeckOptionsView(model: model, chrome: chrome, actions: actions))
        // The band starts at the window's top, under the traffic lights.
        host.safeAreaRegions = []
        host.sizingOptions = []
        // Inside a plain view, as Add's, so a window manager setting the
        // frame and the hosting view don't take turns resizing the window.
        host.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(origin: .zero, size: Theme.DeckOptions.defaultSize))
        host.frame = content.bounds
        content.addSubview(host)
        window.contentView = content
        // The title names the window in the Window menu; the band shows the deck.
        window.title = Tr.actionsOptionsFor(val: model.deckName)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Clear, the view painting the canvas: the bar that comes down in
        // full screen is as opaque as the window's background colour.
        window.isOpaque = false
        window.backgroundColor = .clear
        // An empty toolbar, only so the traffic lights sit centred in the band.
        let toolbar = NSToolbar(identifier: "DeckOptions")
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = Theme.DeckOptions.minSize
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
        // Desktop's question, with the Mac's three answers.
        alert.messageText = Tr.cardTemplatesDiscardChanges
        alert.informativeText = Tr.actionsOptionsFor(val: model.deckName)
        alert.addButton(withTitle: Tr.deckConfigSaveButton)
        alert.addButton(withTitle: Tr.actionsCancel)
        let discard = alert.addButton(withTitle: Tr.actionsDiscard)
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

    /// The toolbar hides with the menu bar in full screen, as Add's, and
    /// the band stays in reach.
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
