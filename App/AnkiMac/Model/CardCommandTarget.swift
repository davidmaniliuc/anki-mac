import SwiftUI

/// What the Cards menu, Undo and Redo act on in the key window: the card being
/// studied in the main window, or the rows selected in the browser. One set
/// of menu items, so a shortcut never reaches the other window.
protocol CardCommandTarget: AnyObject {
    /// The card whose state the menu's checkmarks show; nil when there is none.
    var commandCard: CommandCard? { get }
    var undoState: UndoState { get }
    var canDeleteNotes: Bool { get }
    func toggleFlag(_ flag: CardFlag)
    func toggleMark()
    func toggleSuspend()
    func deleteNotes()
    func undo()
    func redo()
    /// Whether Set Due Date, Reset and Reposition have a card to act on.
    var canScheduleCards: Bool { get }
    func toggleBury()
    func askSetDueDate()
    func askForget()
    func askReposition()
}

extension CardCommandTarget {
    var canScheduleCards: Bool { false }
    func toggleBury() {}
    func askSetDueDate() {}
    func askForget() {}
    func askReposition() {}
}

extension FocusedValues {
    @Entry var cardTarget: (any CardCommandTarget)?
}

extension BrowserModel: CardCommandTarget {
    var canDeleteNotes: Bool { !selectedRows.isEmpty }
    var canScheduleCards: Bool { !selectedRows.isEmpty }
}

extension StudySession: CardCommandTarget {
    var commandCard: CommandCard? {
        card.map { CommandCard(flag: $0.flag, isMarked: $0.isMarked, isSuspended: false, isBuried: false) }
    }

    /// The card leaves the queue either way, so these only ever suspend, bury or delete.
    var canDeleteNotes: Bool { card != nil }
    func toggleSuspend() { suspendCurrentCard() }
    func toggleBury() { buryCurrentCard() }
    func deleteNotes() { deleteCurrentNote() }
}
