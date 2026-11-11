import Foundation

/// What a sidebar row is, for choosing its context menu. The `…Root` kinds
/// are the section headers.
nonisolated enum SidebarKind: Sendable {
    case savedSearchRoot, savedSearch
    case cardStateRoot, cardState
    case flagRoot, flag
    case deckRoot, deck
    case notetypeRoot, notetype
    case tagRoot, tag

    /// The menu's groups in desktop's order (aqt/browser/sidebar/tree.py,
    /// `show_context_menu`), with a separator between groups. Which of them
    /// show for a given selection is `SidebarAction.isAvailable`.
    var actionGroups: [[SidebarAction]] {
        switch self {
        case .savedSearchRoot: [[.saveCurrentSearch]]
        case .savedSearch: [[.updateSavedSearch], [.delete, .rename], [.search]]
        case .cardState: [[.search]]
        case .flag: [[.rename], [.search]]
        case .deck: [[.addNotes, .delete, .rename, .renameWithParents], [.search]]
        case .notetypeRoot: [[.manageNotetypes]]
        case .notetype: [[.manageNotetypes], [.search]]
        case .tagRoot: [[.clearUnusedTags]]
        case .tag:
            [[.addToSelectedNotes, .removeFromSelectedNotes], [.delete, .rename, .renameWithParents], [.search]]
        case .cardStateRoot, .flagRoot, .deckRoot: []
        }
    }
}

nonisolated enum SidebarAction: Sendable {
    case search
    case rename, renameWithParents, delete
    case saveCurrentSearch, updateSavedSearch
    case clearUnusedTags
    case addToSelectedNotes, removeFromSelectedNotes
    case manageNotetypes
    case addNotes

    /// Whether the action applies to the rows the menu was opened on, which
    /// all have the kind whose table listed it, or are none (a header).
    func isAvailable(for items: [SidebarItem]) -> Bool {
        let sameKind = items.allSatisfy { $0.kind == items.first?.kind }
        switch self {
        case .search, .saveCurrentSearch, .clearUnusedTags: return true
        case .delete, .addToSelectedNotes, .removeFromSelectedNotes: return sameKind
        case .rename, .updateSavedSearch: return items.count == 1
        case .renameWithParents: return items.count == 1 && !items[0].namePrefix.isEmpty
        case .manageNotetypes, .addNotes: return items.count <= 1
        }
    }

    var title: String {
        switch self {
        case .search: Tr.actionsSearch
        case .rename: Tr.actionsRename
        case .renameWithParents: Tr.actionsRenameWithParents
        case .delete: Tr.actionsDelete
        case .saveCurrentSearch: Tr.browsingSidebarSaveCurrentSearch
        case .updateSavedSearch: Tr.browsingUpdateSavedSearch
        case .clearUnusedTags: Tr.browsingClearUnusedTags
        case .addToSelectedNotes: Tr.browsingAddToSelectedNotes
        case .removeFromSelectedNotes: Tr.browsingRemoveFromSelectedNotes
        case .manageNotetypes: Tr.browsingManageNoteTypes
        case .addNotes: Tr.browsingAddNotes
        }
    }
}
