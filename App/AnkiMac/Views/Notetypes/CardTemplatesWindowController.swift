import AnkiKit
import AppKit
import SwiftUI

/// Desktop's Card Types window for one note type. A window of its own rather
/// than a sheet, so it can be resized to give the preview room.
final class CardTemplatesWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [Int64: CardTemplatesWindowController] = [:]
    private let model: CardTemplatesModel
    private var closing = false

    static func show(manager: NotetypeManager, notetype: Anki_Notetypes_Notetype, useCount: UInt32, mediaFolder: URL?) {
        if let existing = open[notetype.id] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let model = CardTemplatesModel(manager: manager, notetype: notetype, useCount: useCount)
        let controller = CardTemplatesWindowController(model: model, mediaFolder: mediaFolder)
        open[notetype.id] = controller
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(model: CardTemplatesModel, mediaFolder: URL?) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Notetypes.cardsDefaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        let host = NSHostingController(rootView: CardTemplatesView(
            model: model, mediaFolder: mediaFolder, close: { [weak self] in self?.forceClose() }))
        window.contentViewController = host
        window.title = Tr.cardTemplatesCardTypesFor(val: model.original.name)
        window.contentMinSize = Theme.Notetypes.cardsMinSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("CardTemplates")
        if !window.setFrameUsingName("CardTemplates") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func forceClose() {
        closing = true
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing, model.isEdited else { return true }
        Task {
            if await NotetypeAlerts.confirm(Tr.cardTemplatesDiscardChanges, confirm: "Discard", destructive: true) { forceClose() }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        Self.open[model.original.id] = nil
    }
}
