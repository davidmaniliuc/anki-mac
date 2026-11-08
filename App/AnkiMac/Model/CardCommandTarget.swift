import SwiftUI

/// What the Cards menu and Undo act on in the key window: the card being
/// studied in the main window, or the rows selected in the browser. One set
/// of menu items, so a shortcut never reaches the other window.
protocol CardCommandTarget: AnyObject {
    /// The card whose state the menu's checkmarks show; nil when there is none.
    var commandCard: CommandCard? { get }
    /// What Undo would undo, as the backend names it; empty when nothing.
    var undoLabel: String { get }
    var canDeleteNotes: Bool { get }
    func toggleFlag(_ flag: CardFlag)
    func toggleMark()
    func toggleSuspend()
    func deleteNotes()
    func undo()
}

extension FocusedValues {
    @Entry var cardTarget: (any CardCommandTarget)?
}

extension BrowserModel: CardCommandTarget {
    var canDeleteNotes: Bool { !selectedRows.isEmpty }
}

extension StudySession: CardCommandTarget {
    var commandCard: CommandCard? {
        card.map { CommandCard(flag: $0.flag, isMarked: $0.isMarked, isSuspended: nil) }
    }

    var canDeleteNotes: Bool { false }
    func toggleSuspend() {}
    func deleteNotes() {}
}
