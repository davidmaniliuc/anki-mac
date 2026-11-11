import AnkiKit

/// What the backend can undo and redo right now, named as it names them;
/// an empty label means there is nothing to undo or redo.
struct UndoState: Equatable, Sendable {
    var undo = ""
    var redo = ""

    var canUndo: Bool { !undo.isEmpty }
    var canRedo: Bool { !redo.isEmpty }
    /// The Edit menu's text, "Undo Answer Card" or plain "Undo", as desktop.
    var undoTitle: String { canUndo ? Tr.undoUndoAction(val: undo) : Tr.undoUndo }
    var redoTitle: String { canRedo ? Tr.undoRedoAction(action: redo) : Tr.undoRedo }
}

extension AnkiBackend {
    nonisolated func undoState() throws -> UndoState {
        let status = try getUndoStatus()
        return UndoState(undo: status.undo, redo: status.redo)
    }
}
