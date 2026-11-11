import AppKit
import SwiftUI

/// Tools > Manage Note Types: one window per app, as desktop's.
final class NotetypeManagerWindowController: NSWindowController, NSWindowDelegate {
    private static var current: NotetypeManagerWindowController?

    private var model: NotetypeManager?

    /// `selecting` picks the note type the list opens on.
    static func show(collection: CollectionModel, selecting id: Int64? = nil) {
        if let current {
            if let id { current.model?.selectedID = id }
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let backend = collection.backend else { return }
        let model = NotetypeManager(backend: backend)
        model.selectedID = id
        model.onChange = { Task { await collection.refreshDecks() } }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Notetypes.managerSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        let controller = NotetypeManagerWindowController(window: window)
        controller.model = model
        window.title = Tr.notetypesNoteTypes
        window.contentViewController = NSHostingController(
            rootView: NotetypeManagerView(model: model, collection: collection))
        window.contentMinSize = Theme.Notetypes.managerMinSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = controller
        window.setFrameAutosaveName("NotetypeManager")
        if !window.setFrameUsingName("NotetypeManager") { window.center() }
        window.makeKeyAndOrderFront(nil)
        current = controller
    }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
