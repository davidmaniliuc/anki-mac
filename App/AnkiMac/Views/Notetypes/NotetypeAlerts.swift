import AppKit

/// Desktop's yes/no questions as sheets on the front window.
enum NotetypeAlerts {
    /// Asks, answering true for the confirming button.
    @MainActor
    static func confirm(
        _ message: String, confirm title: String = "OK", destructive: Bool = false, cancel: String = "Cancel"
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        let ok = alert.addButton(withTitle: title)
        ok.hasDestructiveAction = destructive
        alert.addButton(withTitle: cancel)
        if let window = NSApp.keyWindow {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0 == .alertFirstButtonReturn) }
            }
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    static func inform(_ message: String) async {
        let alert = NSAlert()
        alert.messageText = message
        if let window = NSApp.keyWindow {
            await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { _ in continuation.resume() }
            }
        } else {
            alert.runModal()
        }
    }

    /// Desktop's `qt-misc-the-requested-change-will-require-a`, asked before
    /// a change to the schema unless one is already waiting for the next sync.
    static let schemaChange = "The requested change will require a full upload of the database when you next synchronize your collection. If you have reviews or other changes waiting on another device that haven't been synchronized here yet, they will be lost. Continue?"
}
