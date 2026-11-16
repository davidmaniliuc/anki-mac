import AnkiKit
import AppKit
import Observation
import SwiftUI

/// Desktop's Card Types window for one note type. A window of its own rather
/// than a sheet, so it can be resized to give the preview room, with Add's
/// chrome: the canvas from the top edge and the controls in a band under
/// the traffic lights. It asks before closing over unsaved changes.
final class CardTemplatesWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [Int64: CardTemplatesWindowController] = [:]
    private let model: CardTemplatesModel
    private let chrome = BandChrome()
    private var closing = false

    static func show(
        manager: NotetypeManager, notetype: Anki_Notetypes_Notetype, useCount: UInt32, mediaFolder: URL?,
        ord: Int = 0, note: Anki_Notes_Note? = nil
    ) {
        if let existing = open[notetype.id] {
            if let note { existing.model.preview(note: note, ord: ord) }
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let model = CardTemplatesModel(manager: manager, notetype: notetype, useCount: useCount, ord: ord, note: note)
        let controller = CardTemplatesWindowController(model: model, mediaFolder: mediaFolder)
        open[notetype.id] = controller
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Desktop's "Cards..." button in the editors: the note's own type,
    /// showing the template of the card the editor is on, previewed with the
    /// note as it stands (saved or not).
    static func show(collection: CollectionModel, note: Anki_Notes_Note, ord: Int) {
        guard let backend = collection.backend else { return }
        let manager = NotetypeManager(backend: backend)
        manager.onChange = { Task { await collection.refreshDecks() } }
        let mediaFolder = collection.paths?.mediaFolder
        Task {
            await manager.refresh(select: note.notetypeID)
            guard let useCount = manager.entries.first(where: { $0.id == note.notetypeID })?.useCount,
                  let notetype = try? await manager.notetype(note.notetypeID)
            else {
                collection.failure = manager.failure ?? ActionFailure("Couldn’t open the card types", detail: "")
                return
            }
            show(manager: manager, notetype: notetype, useCount: useCount, mediaFolder: mediaFolder, ord: ord, note: note)
        }
    }

    private init(model: CardTemplatesModel, mediaFolder: URL?) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Notetypes.cardsDefaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        let host = NSHostingView(rootView: CardTemplatesView(
            model: model, chrome: chrome, mediaFolder: mediaFolder,
            save: { [weak self] in self?.save() }, close: { [weak self] in self?.forceClose() }))
        // The band starts at the window's top, under the traffic lights.
        host.safeAreaRegions = []
        host.sizingOptions = []
        // Inside a plain view, as Add's, so the hosting view never resizes the window.
        host.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(origin: .zero, size: Theme.Notetypes.cardsDefaultSize))
        host.frame = content.bounds
        content.addSubview(host)
        window.contentView = content
        // The title names the window in the Window menu; the band shows it too.
        window.title = Tr.cardTemplatesCardTypesFor(val: model.original.name)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Clear, the view painting the canvas: the bar that comes down in
        // full screen is as opaque as the window's background colour.
        window.isOpaque = false
        window.backgroundColor = .clear
        // An empty toolbar, only so the traffic lights sit centred in the band.
        let toolbar = NSToolbar(identifier: "CardTemplates")
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = Theme.Notetypes.cardsMinSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("CardTemplates")
        if !window.setFrameUsingName("CardTemplates") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Saves, closing once the note type is written; a failure stays open.
    func save() {
        window?.makeFirstResponder(nil)
        Task { if await model.save() { forceClose() } }
    }

    private func forceClose() {
        closing = true
        window?.close()
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing, model.isEdited else { return true }
        Task {
            switch await NotetypeAlerts.discardChanges(in: sender, detail: sender.title) {
            case true?: forceClose()
            case false?: save()
            case nil: break
            }
        }
        return false
    }

    /// The toolbar hides with the menu bar in full screen, as Add's, and the
    /// band stays in reach.
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
        KeyCardTemplates.shared.controller = self
    }

    func windowDidResignKey(_ notification: Notification) {
        if KeyCardTemplates.shared.controller === self { KeyCardTemplates.shared.controller = nil }
    }

    func windowWillClose(_ notification: Notification) {
        if KeyCardTemplates.shared.controller === self { KeyCardTemplates.shared.controller = nil }
        Self.open[model.original.id] = nil
    }
}

/// The card types window that the File menu's Save acts on while it is key.
@Observable
final class KeyCardTemplates {
    static let shared = KeyCardTemplates()
    var controller: CardTemplatesWindowController?
}
