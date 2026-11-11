import AppKit

/// The undo of whatever text is being typed in the key window, which the Edit
/// menu offers ahead of the collection's. As on desktop, typing in a field,
/// the search box or the card layout editor undoes the typing, not a change
/// to the collection.
@Observable
final class TextUndo {
    static let shared = TextUndo()

    /// Nil unless the key window's first responder is a text view with something to undo or redo.
    private(set) var state: State?

    struct State: Equatable {
        var undoTitle: String
        var redoTitle: String
        var canUndo: Bool
        var canRedo: Bool
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private var manager: UndoManager? {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager
    }

    private func refresh() {
        let next = manager.flatMap { manager -> State? in
            guard manager.canUndo || manager.canRedo else { return nil }
            return State(
                undoTitle: manager.undoMenuItemTitle, redoTitle: manager.redoMenuItemTitle,
                canUndo: manager.canUndo, canRedo: manager.canRedo)
        }
        if next != state { state = next }
    }

    func undo() { manager?.undo() }
    func redo() { manager?.redo() }
}
