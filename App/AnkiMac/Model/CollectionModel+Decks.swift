import AnkiKit
import Foundation

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

    /// Things' New List: adds "New Deck" at the top level, selected and
    /// with its name ready to type over.
    func createDeck() {
        guard isLoaded else { return }
        let taken = Set(decks.map(\.name))
        let name = sequence(first: 1) { $0 + 1 }
            .lazy.map { $0 == 1 ? "New Deck" : "New Deck \($0)" }
            .first { !taken.contains($0) }!
        deckOp { backend in
            var deck = try backend.newDeck()
            deck.name = name
            return try backend.addDeck(deck).id
        } then: { id in
            self.selectedDeckID = id
            self.renamingDeckID = id
        }
    }

    /// Starts editing the deck's name in the sidebar, as a double-click does.
    func beginRenaming(_ deckID: Int64) {
        guard deck(deckID) != nil else { return }
        selectedDeckID = deckID
        renamingDeckID = deckID
    }

    /// Ends the sidebar edit. The name replaces the last part of the deck's
    /// full name; "::" in it nests the deck further, as on desktop.
    func finishRenaming(_ deckID: Int64, to newName: String?) {
        guard renamingDeckID == deckID else { return }
        renamingDeckID = nil
        let name = newName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let deck = deck(deckID), !name.isEmpty, name != deck.name else { return }
        let fullName = String(deck.fullName.dropLast(deck.name.count)) + name
        deckOp { backend in
            var request = Anki_Decks_RenameDeckRequest()
            request.deckID = deckID
            request.newName = fullName
            _ = try backend.renameDeck(request)
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

    // MARK: Study Deck

    /// Every deck, filtered ones included, by full name, for the Study Deck picker.
    func studyDeckChoices() async -> [DeckChoice] {
        guard let backend else { return [] }
        return (try? await backend.perform { backend in
            var request = Anki_Decks_GetDeckNamesRequest()
            request.skipEmptyDefault = true
            request.includeFiltered = true
            return try backend.getDeckNames(request).entries.map { DeckChoice(id: $0.id, name: $0.name) }
        }) ?? []
    }

    /// Desktop's Study Deck choice: leaves any session and shows the deck's overview.
    func showOverview(of deckID: Int64) {
        studyDeckPresented = false
        if session != nil { stopStudying() }
        selectedDeckID = deckID
    }

    /// The picker's Add: creates the deck and shows its overview.
    func addDeckAndShow(named name: String) {
        deckOp { backend in
            var deck = try backend.newDeck()
            deck.name = name
            return try backend.addDeck(deck).id
        } then: { id in
            self.showOverview(of: id)
        }
    }

    // MARK: Description

    /// The deck's description, rendered from Markdown by the backend when the
    /// deck's flag says so, as desktop's overview does.
    func description(of deckID: Int64) async -> DeckDescription? {
        guard let backend else { return nil }
        do {
            let (text, markdown, html) = try await backend.perform { backend in
                var request = Anki_Decks_DeckId()
                request.did = deckID
                let normal = try backend.getDeck(request).normal
                guard normal.markdownDescription, !normal.description_p.isEmpty else {
                    return (normal.description_p, false, normal.description_p)
                }
                var render = Anki_CardRendering_RenderMarkdownRequest()
                render.markdown = normal.description_p
                render.sanitize = true
                return (normal.description_p, true, try backend.renderMarkdown(render).val)
            }
            return DeckDescription(
                id: deckID, text: text, markdown: markdown, body: DeckDescription.attributed(html: html))
        } catch {
            errorMessage = FilteredDeckModel.message(error)
            return nil
        }
    }

    /// Opens the Description sheet on the deck's stored text. Filtered decks
    /// have none.
    func editDescription(_ deckID: Int64) {
        guard deck(deckID)?.filtered == false, let backend else { return }
        Task {
            do {
                descriptionEdit = try await backend.perform { backend in
                    var request = Anki_Decks_DeckId()
                    request.did = deckID
                    let normal = try backend.getDeck(request).normal
                    return DeckDescription(
                        id: deckID, text: normal.description_p, markdown: normal.markdownDescription,
                        body: AttributedString())
                }
            } catch {
                errorMessage = FilteredDeckModel.message(error)
            }
        }
    }

    func saveDescription(_ edit: DeckDescription) {
        descriptionEdit = nil
        deckOp { backend in
            var request = Anki_Decks_DeckId()
            request.did = edit.id
            var deck = try backend.getDeck(request)
            guard case .normal(var normal)? = deck.kind else { return }
            normal.description_p = edit.text
            normal.markdownDescription = edit.markdown
            deck.kind = .normal(normal)
            _ = try backend.updateDeck(deck)
        } then: {
            if self.selectedDeckID == edit.id {
                Task { self.selectedDescription = await self.description(of: edit.id) }
            }
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
