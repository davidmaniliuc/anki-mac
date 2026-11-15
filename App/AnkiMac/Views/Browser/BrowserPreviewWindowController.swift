import AppKit
import SwiftUI

/// The previewer window the browser opens, a separate window as on desktop.
/// The browser owns it and closes it with itself.
final class BrowserPreviewWindowController: NSWindowController, NSWindowDelegate {
    private let model: BrowserPreviewModel
    private let onClose: () -> Void
    private let chrome = BandChrome()
    private var keyMonitor: Any?
    private var isClosed = false

    init(browser: BrowserModel, onClose: @escaping () -> Void) {
        model = BrowserPreviewModel(browser: browser)
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Browser.previewSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)
        let host = NSHostingView(rootView: BrowserPreviewView(model: model, chrome: chrome))
        // The band starts at the window's top, under the traffic lights.
        host.safeAreaRegions = []
        host.sizingOptions = []
        // Inside a plain view, as Add's, so the hosting view never resizes the window.
        host.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(origin: .zero, size: Theme.Browser.previewSize))
        host.frame = content.bounds
        content.addSubview(host)
        window.contentView = content
        // The title names the window in the Window menu; the band has the controls.
        window.title = Tr.actionsPreview
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Clear, the view painting the canvas: the bar that comes down in
        // full screen is as opaque as the window's background colour.
        window.isOpaque = false
        window.backgroundColor = .clear
        // An empty toolbar, only so the traffic lights sit centred in the band.
        let toolbar = NSToolbar(identifier: "Preview")
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.contentMinSize = Theme.Browser.previewMinSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("Preview")
        if !window.setFrameUsingName("Preview") { window.center() }

        model.onSelectionLost = { [weak self] in self?.close() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
        track { [weak self] in
            guard let self, !isClosed else { return }
            model.browserChanged()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The web view takes plain keys before the menu bar sees them, so the
    /// previewer's keys are handled here, as the study screen's are.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, window.isKeyWindow else { return false }
        let responder = window.firstResponder
        if responder is NSText || (responder === model.web.webView && model.web.isEditingText) { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if modifiers == [.command, .shift], key == "p" {
            close()
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch (event.keyCode, key) {
        case (Self.leftArrow, _): model.back()
        case (Self.rightArrow, _), (Self.return, _), (Self.enter, _): model.forward()
        case (Self.escape, _): close()
        case (_, "r"): model.replayAudio()
        case (_, "b"): model.setBackSideOnly(!model.backSideOnly)
        default: return false
        }
        return true
    }

    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124
    private static let `return`: UInt16 = 36
    private static let enter: UInt16 = 76
    private static let escape: UInt16 = 53

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

    func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        model.close()
        onClose()
    }
}
