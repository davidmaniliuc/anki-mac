import AppKit
import SwiftUI

/// The profiles' own small window, as Photos' Choose Library: it is up
/// while a profile is picked, and the main window is out of sight until
/// one opens. Closing it quits, as desktop's profile manager does.
final class ProfilesWindowController: NSWindowController, NSWindowDelegate {
    private static var current: ProfilesWindowController?
    private var dismissing = false

    /// Shows the profiles in place of the main window, or the main window again.
    static func show(_ shown: Bool, collection: CollectionModel) {
        if shown {
            collection.mainWindow?.orderOut(nil)
            let controller = current ?? ProfilesWindowController(collection: collection)
            current = controller
            controller.window?.center()
            controller.window?.makeKeyAndOrderFront(nil)
        } else {
            if let current {
                current.dismissing = true
                current.close()
                Self.current = nil
            }
            if let window = collection.mainWindow {
                window.makeKeyAndOrderFront(nil)
            } else {
                collection.openMainWindow()
            }
        }
    }

    /// Brings the profiles forward, for a click on the Dock icon while one is picked.
    static func bringForward() {
        current?.window?.makeKeyAndOrderFront(nil)
    }

    private init(collection: CollectionModel) {
        let host = NSHostingController(rootView: ProfilesView().environment(collection))
        // The window takes the page's size, growing with the profiles.
        host.sizingOptions = .preferredContentSize
        // The title starts under the traffic lights, as Add's band does.
        host.safeAreaRegions = []
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // The title names the window in the Window menu; the page names itself.
        window.title = Tr.profilesProfiles
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func windowWillClose(_ notification: Notification) {
        guard !dismissing else { return }
        Self.current = nil
        NSApp.terminate(nil)
    }
}
