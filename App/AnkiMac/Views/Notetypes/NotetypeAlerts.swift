import AnkiKit
import AppKit

/// Desktop's questions about note types, as Mac alerts on the window
/// asking: the question as the alert's title, what it costs under it, and
/// buttons named for what they do, a destructive one in red.
enum NotetypeAlerts {
    /// Asks, answering true for the confirming button.
    @MainActor
    static func confirm(
        _ message: String, detail: String = "", confirm title: String, destructive: Bool = false
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: title).hasDestructiveAction = destructive
        alert.addButton(withTitle: Tr.actionsCancel)
        return await run(alert) == .alertFirstButtonReturn
    }

    /// Says something that needs no answer.
    @MainActor
    static func inform(_ message: String, detail: String = "") async {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        _ = await run(alert)
    }

    /// Desktop's question before closing an editor over changes, with the
    /// Mac's three answers, as Deck Options asks it. Nil is Cancel.
    @MainActor
    static func discardChanges(in window: NSWindow?, detail: String) async -> Bool? {
        let alert = NSAlert()
        alert.messageText = Tr.cardTemplatesDiscardChanges
        alert.informativeText = detail
        alert.addButton(withTitle: Tr.actionsSave)
        alert.addButton(withTitle: Tr.actionsCancel)
        alert.addButton(withTitle: Tr.actionsDiscard).hasDestructiveAction = true
        switch await run(alert, on: window) {
        case .alertFirstButtonReturn: return false
        case .alertThirdButtonReturn: return true
        default: return nil
        }
    }

    /// Desktop's `confirm_schema_modification`: asks before a change that
    /// forces a full upload at the next sync, unless one is already due.
    @MainActor
    static func confirmSchemaChange(_ backend: AnkiBackend) async -> Bool {
        if (try? await backend.perform { $0.schemaAlreadyChanged() }) ?? false { return true }
        return await confirm(Tr.qtMiscTheRequestedChangeWillRequireA, confirm: Tr.studyingContinue)
    }

    /// What a deletion costs at the next sync, said under its question so
    /// it is asked once, unless a full upload is already due.
    @MainActor
    static func schemaCost(_ backend: AnkiBackend) async -> String {
        (try? await backend.perform { $0.schemaAlreadyChanged() }) ?? false ? "" : Tr.deckConfigWillRequireFullSync
    }

    @MainActor
    private static func run(_ alert: NSAlert, on window: NSWindow? = nil) async -> NSApplication.ModalResponse {
        guard let window = window ?? NSApp.keyWindow else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }
}
