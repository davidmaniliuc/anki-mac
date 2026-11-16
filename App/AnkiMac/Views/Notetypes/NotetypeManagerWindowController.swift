import AppKit
import SwiftUI

/// Tools > Manage Note Types: one window per app, as desktop's, with Add's
/// chrome: the canvas from the top edge and the controls in a band under
/// the traffic lights.
final class NotetypeManagerWindowController: NSWindowController, NSWindowDelegate {
    private static var current: NotetypeManagerWindowController?

    private let model: NotetypeManager
    private let chrome = BandChrome()

    /// `selecting` picks the note type the list opens on.
    static func show(collection: CollectionModel, selecting id: Int64? = nil) {
        if let current {
            if let id { current.model.selectedID = id }
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard let backend = collection.backend else { return }
        let model = NotetypeManager(backend: backend)
        model.selectedID = id
        model.onChange = { Task { await collection.refreshDecks() } }
        let controller = NotetypeManagerWindowController(model: model, collection: collection)
        controller.window?.makeKeyAndOrderFront(nil)
        current = controller
    }

    private init(model: NotetypeManager, collection: CollectionModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Notetypes.managerSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        let host = NSHostingView(rootView: NotetypeManagerView(model: model, chrome: chrome, collection: collection))
        // The band starts at the window's top, under the traffic lights.
        host.safeAreaRegions = []
        host.sizingOptions = []
        // Inside a plain view, as Add's, so the hosting view never resizes the window.
        host.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(origin: .zero, size: Theme.Notetypes.managerSize))
        host.frame = content.bounds
        content.addSubview(host)
        window.contentView = content
        // The title names the window in the Window menu; the band shows it too.
        window.title = Tr.notetypesNoteTypes
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Clear, the view painting the canvas: the bar that comes down in
        // full screen is as opaque as the window's background colour.
        window.isOpaque = false
        window.backgroundColor = .clear
        // An empty toolbar, only so the traffic lights sit centred in the band.
        let toolbar = NSToolbar(identifier: "NotetypeManager")
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = Theme.Notetypes.managerMinSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("NotetypeManager")
        if !window.setFrameUsingName("NotetypeManager") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
