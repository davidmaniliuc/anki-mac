import AnkiKit
import Foundation

/// What the sidebar's context menus change, as desktop's `rename_*`,
/// `remove_*` and saved search methods in aqt/browser/sidebar/tree.py do.
/// Deck and tag changes are undoable collection ops; saved searches and flag
/// names are config values, which desktop does not make undoable either.
extension BrowserModel {
    private nonisolated static let savedSearchesKey = "savedFilters"
    private nonisolated static let flagLabelsKey = "flagLabels"

    // MARK: Decks and tags

    func renameDeck(_ deckID: Int64, to fullName: String) {
        change(failing: "Couldn’t rename the deck", sidebar: SidebarChange(reveal: .deck(deckID))) { backend in
            var request = Anki_Decks_RenameDeckRequest()
            request.deckID = deckID
            request.newName = fullName
            _ = try backend.renameDeck(request)
        }
    }

    func deleteDecks(_ deckIDs: [Int64]) {
        collection.stopStudying(deleting: deckIDs)
        change(failing: (deckIDs.count == 1 ? "Couldn’t delete the deck" : "Couldn’t delete the decks"), searchAgain: true, sidebar: SidebarChange()) { backend in
            var request = Anki_Decks_DeckIds()
            request.dids = deckIDs
            _ = try backend.removeDecks(request)
        }
    }

    /// Renames the tag and its children. A tag no note uses cannot be renamed.
    func renameTag(_ name: String, to newName: String) {
        let change = SidebarChange(reveal: .tag(newName), tagRename: (name, newName))
        self.change(failing: "Couldn’t rename the tag", sidebar: change) { backend in
            var request = Anki_Tags_RenameTagsRequest()
            request.currentPrefix = name
            request.newPrefix = newName
            return Int(try backend.renameTags(request).count)
        } then: { count in
            self.showToast(count == 0 ? Tr.browsingTagRenameWarningEmpty : Tr.browsingNotesUpdated(count: count))
        }
    }

    func removeTags(_ names: [String]) {
        change(failing: (names.count == 1 ? "Couldn’t remove the tag" : "Couldn’t remove the tags"), sidebar: SidebarChange()) { backend in
            var request = Anki_Generic_String()
            request.val = names.joined(separator: " ")
            return Int(try backend.removeTags(request).count)
        } then: { count in
            self.showToast(Tr.browsingNotesUpdated(count: count))
        }
    }

    func clearUnusedTags() {
        change(failing: "Couldn’t clear unused tags", sidebar: SidebarChange()) { backend in
            Int(try backend.clearUnusedTags().count)
        } then: { count in
            self.showToast(Tr.browsingRemovedUnusedTagsCount(count: count))
        }
    }

    // MARK: Saved searches

    func savedSearch(named name: String) -> String? {
        for section in sidebar where section.kind == .savedSearchRoot {
            for node in section.nodes {
                if case .savedSearch(name, let search) = node.item { return search }
            }
        }
        return nil
    }

    /// Saves the search field's text under `name`. `update` replaces the
    /// saved search without asking; otherwise a different search under an
    /// existing name needs `confirmOverwrite`.
    func saveCurrentSearch(as name: String, update: Bool, confirmOverwrite: @escaping (String) -> Bool) {
        guard let backend = collection.backend else { return }
        let text = searchText
        let title = "Couldn’t save the search"
        Task {
            do {
                let search = try await backend.perform { backend in
                    var node = Anki_Search_SearchNode()
                    node.parsableText = text
                    return try backend.buildSearchString(node).val
                }
                if !update, let existing = savedSearch(named: name) {
                    if existing == search || !confirmOverwrite(name) { return }
                }
                editConfig(failing: title, Self.savedSearchesKey, reveal: .savedSearch(name)) { $0[name] = search }
            } catch {
                failure = ActionFailure(title, error: error)
            }
        }
    }

    func renameSavedSearch(_ name: String, to newName: String, confirmOverwrite: (String) -> Bool) {
        if savedSearch(named: newName) != nil && !confirmOverwrite(newName) { return }
        editConfig(failing: "Couldn’t rename the saved search", Self.savedSearchesKey, reveal: .savedSearch(newName)) { searches in
            guard let search = searches.removeValue(forKey: name) else { return }
            searches[newName] = search
        }
    }

    func deleteSavedSearches(_ names: [String]) {
        editConfig(failing: (names.count == 1 ? "Couldn’t delete the saved search" : "Couldn’t delete the saved searches"), Self.savedSearchesKey) { searches in names.forEach { searches[$0] = nil } }
    }

    // MARK: Flags

    /// An empty name brings back the flag's default one.
    func renameFlag(_ flag: CardFlag, to name: String) {
        editConfig(failing: "Couldn’t rename the flag", Self.flagLabelsKey) { labels in
            labels[String(flag.rawValue)] = name.isEmpty ? nil : name
        }
    }

    private func editConfig(
        failing title: String, _ key: String, reveal: SidebarItem.ID? = nil, _ edit: @escaping @Sendable (inout [String: String]) -> Void
    ) {
        guard let backend = collection.backend else { return }
        Task {
            do {
                try await backend.perform { try $0.editConfigStrings(key, edit) }
                await loadSidebar(SidebarChange(reveal: reveal))
            } catch {
                failure = ActionFailure(title, error: error)
            }
        }
    }
}
