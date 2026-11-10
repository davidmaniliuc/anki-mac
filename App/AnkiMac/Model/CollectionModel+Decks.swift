import AnkiKit
import Foundation

/// The name prompt behind Create Deck and Rename.
struct DeckNamePrompt {
    enum Kind {
        case create
        case rename(Int64)
    }

    let kind: Kind
    var name: String

    var title: String {
        switch kind {
        case .create: Tr.decksCreateDeck
        case .rename: Tr.actionsRenameDeck
        }
    }

    var confirmTitle: String {
        switch kind {
        case .create: "Create"
        case .rename: Tr.actionsRename
        }
    }
}

/// Which buried cards a deck holds, for Unbury.
struct BuriedCards: Equatable {
    var manually = false
    var siblings = false

    var any: Bool { manually || siblings }
}

/// Desktop's deck browser actions: create, rename, delete and drag decks,
/// plus the overview's Custom Study and Unbury. All of them are undoable.
extension CollectionModel {
    // MARK: Create and rename

    func askCreateDeck() {
        guard isLoaded else { return }
        deckNamePrompt = DeckNamePrompt(kind: .create, name: "")
    }

    func askRenameDeck(_ deckID: Int64) {
        guard let deck = deck(deckID) else { return }
        deckNamePrompt = DeckNamePrompt(kind: .rename(deckID), name: deck.fullName)
    }

    /// Runs the prompt's action. "::" in the name nests the deck, as on desktop.
    func commitDeckName(_ prompt: DeckNamePrompt) {
        let name = prompt.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch prompt.kind {
        case .create:
            deckOp { backend in
                var deck = try backend.newDeck()
                deck.name = name
                return try backend.addDeck(deck).id
            } then: { id in
                self.selectedDeckID = id
            }
        case .rename(let deckID):
            guard name != deck(deckID)?.fullName else { return }
            deckOp { backend in
                var request = Anki_Decks_RenameDeckRequest()
                request.deckID = deckID
                request.newName = name
                _ = try backend.renameDeck(request)
            }
        }
    }

    // MARK: Delete and move

    /// Deletes the deck, its subdecks and their cards without asking, as
    /// desktop does; Undo brings them back.
    func deleteDeck(_ deckID: Int64) {
        if session?.deckID == deckID { stopStudying() }
        deckOp { backend in
            var request = Anki_Decks_DeckIds()
            request.dids = [deckID]
            _ = try backend.removeDecks(request)
        }
    }

    /// Moves decks under another, or to the top level with parent 0.
    func moveDecks(_ deckIDs: [Int64], to parentID: Int64) {
        let moving = deckIDs.filter { $0 != parentID }
        guard !moving.isEmpty else { return }
        deckOp { backend in
            var request = Anki_Decks_ReparentDecksRequest()
            request.deckIds = moving
            request.newParent = parentID
            _ = try backend.reparentDecks(request)
        }
    }

    // MARK: Unbury and Custom Study

    func buriedCards(in deck: DeckNode) async -> BuriedCards {
        guard let backend else { return BuriedCards() }
        let name = deck.fullName
        return (try? await backend.perform { backend in
            func any(_ state: String) throws -> Bool {
                var request = Anki_Search_SearchRequest()
                var search = Anki_Search_SearchNode()
                search.deck = name
                var buried = Anki_Search_SearchNode()
                buried.parsableText = "is:\(state)"
                var node = Anki_Search_SearchNode()
                node.group.nodes = [search, buried]
                node.group.joiner = .and
                request.search = try backend.buildSearchString(node).val
                return !(try backend.searchCards(request).ids.isEmpty)
            }
            return BuriedCards(manually: try any("buried-manually"), siblings: try any("buried-sibling"))
        }) ?? BuriedCards()
    }

    /// Desktop's Unbury: asks which kind when the deck has both.
    func askUnbury(_ deckID: Int64) {
        guard selectedDeckID == deckID, selectedBuried.any else { return }
        if selectedBuried.manually && selectedBuried.siblings {
            unburyPrompt = deckID
        } else {
            unbury(deckID)
        }
    }

    func unbury(_ deckID: Int64, mode: Anki_Scheduler_UnburyDeckRequest.Mode = .all) {
        deckOp { backend in
            var request = Anki_Scheduler_UnburyDeckRequest()
            request.deckID = deckID
            request.mode = mode
            _ = try backend.unburyDeck(request)
        } then: {
            // The counts may not change, so the overview wouldn't reload these.
            if mode != .schedOnly { self.selectedBuried.manually = false }
            if mode != .userOnly { self.selectedBuried.siblings = false }
        }
    }

    func showCustomStudy(_ deckID: Int64) {
        guard let backend, customStudy == nil, deck(deckID)?.filtered == false else { return }
        Task {
            do {
                customStudy = try await CustomStudyModel.load(deckID: deckID, backend: backend)
            } catch {
                errorMessage = FilteredDeckModel.message(error)
            }
        }
    }

    /// After Custom Study: a session deck is selected, ready to study, as
    /// desktop shows its overview; a raised limit shows in the counts.
    func customStudyDone(selecting deckID: Int64) {
        customStudy = nil
        if session != nil { stopStudying() }
        Task {
            await refreshDecks()
            selectedDeckID = deckID
        }
    }

    // MARK: Undo

    /// Undoes the last change, from the main window while not studying.
    func undoLast() {
        guard let backend, !undoLabel.isEmpty else { return }
        Task {
            do {
                _ = try await backend.perform { try $0.undo() }
            } catch {
                errorMessage = FilteredDeckModel.message(error)
            }
            await refreshDecks()
        }
    }

    // MARK: Helpers

    private func deckOp<T: Sendable>(
        _ op: @escaping @Sendable (AnkiBackend) throws -> T, then: @escaping (T) -> Void = { _ in }
    ) {
        guard let backend else { return }
        Task {
            do {
                then(try await backend.perform(op))
            } catch {
                errorMessage = FilteredDeckModel.message(error)
            }
            await refreshDecks()
        }
    }
}

/// The main window's Undo while no card is being studied.
extension CollectionModel: CardCommandTarget {
    var commandCard: CommandCard? { nil }
    var canDeleteNotes: Bool { false }
    func toggleFlag(_ flag: CardFlag) {}
    func toggleMark() {}
    func toggleSuspend() {}
    func deleteNotes() {}
    func undo() { undoLast() }
}
