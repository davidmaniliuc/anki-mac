import AnkiKit
import Foundation
import Observation

/// One search of a filtered deck: what to pull in, how many, in what order.
struct FilteredSearch {
    var search: String
    var limit: Int
    var order: Anki_Decks_Deck.Filtered.SearchTerm.Order

    init(_ term: Anki_Decks_Deck.Filtered.SearchTerm) {
        search = term.search
        limit = Int(term.limit)
        order = term.order
    }

    var term: Anki_Decks_Deck.Filtered.SearchTerm {
        var term = Anki_Decks_Deck.Filtered.SearchTerm()
        term.search = search
        term.limit = UInt32(clamping: limit)
        term.order = order
        return term
    }
}

/// Desktop's filtered deck dialog: builds a new filtered deck, or changes
/// and rebuilds an existing one.
@Observable
final class FilteredDeckModel: Identifiable {
    let id = UUID()
    private var deck: Anki_Decks_FilteredDeckForUpdate
    private let backend: AnkiBackend

    var name: String
    var first: FilteredSearch
    var second: FilteredSearch
    var secondEnabled: Bool
    var reschedule: Bool
    var previewAgain: Int
    var previewHard: Int
    var previewGood: Int
    var allowEmpty: Bool
    /// The orders to offer, with their labels; the FSRS ones only when FSRS is on.
    let orders: [(order: Anki_Decks_Deck.Filtered.SearchTerm.Order, label: String)]
    var error: String?
    private(set) var building = false

    var isNew: Bool { deck.id == 0 }

    /// Loads an existing filtered deck, or with id 0 the defaults for a new
    /// one, which search the current deck.
    init(deckID: Int64, currentDeck: Int64?, backend: AnkiBackend) throws {
        self.backend = backend
        if deckID == 0, let currentDeck {
            var current = Anki_Decks_DeckId()
            current.did = currentDeck
            _ = try backend.setCurrentDeck(current)
        }
        var request = Anki_Decks_DeckId()
        request.did = deckID
        let deck = try backend.getOrCreateFilteredDeck(request)
        self.deck = deck

        let fsrsEnabled = backend.configJSON("fsrs", as: Bool.self) ?? false
        let labels = try backend.filteredDeckOrderLabels().vals
        let fsrsOnly: Set<Anki_Decks_Deck.Filtered.SearchTerm.Order> = [.retrievabilityAscending, .retrievabilityDescending]
        orders = labels.enumerated().compactMap { index, label in
            guard let order = Anki_Decks_Deck.Filtered.SearchTerm.Order(rawValue: index),
                fsrsEnabled || !fsrsOnly.contains(order)
            else { return nil }
            return (order, label)
        }

        let config = deck.config
        name = deck.name
        first = FilteredSearch(config.searchTerms.first ?? Anki_Decks_Deck.Filtered.SearchTerm())
        if config.searchTerms.count > 1 {
            second = FilteredSearch(config.searchTerms[1])
            secondEnabled = deck.id != 0
        } else {
            var term = Anki_Decks_Deck.Filtered.SearchTerm()
            term.order = .random
            term.limit = 20
            second = FilteredSearch(term)
            secondEnabled = false
        }
        reschedule = config.reschedule
        previewAgain = Int(config.previewAgainSecs)
        previewHard = Int(config.previewHardSecs)
        previewGood = Int(config.previewGoodSecs)
        allowEmpty = deck.allowEmpty
        // An order hidden because FSRS is off falls back to random, as desktop.
        let offered = Set(orders.map(\.order))
        if !offered.contains(first.order) { first.order = .random }
        if !offered.contains(second.order) { second.order = .random }
    }

    /// Builds or rebuilds the deck, and returns its id; nil after an error,
    /// such as no cards matching.
    func build() async -> Int64? {
        var deck = deck
        deck.name = name
        deck.allowEmpty = allowEmpty
        deck.config.reschedule = reschedule
        deck.config.delays = []
        deck.config.searchTerms = [first.term] + (secondEnabled ? [second.term] : [])
        deck.config.previewAgainSecs = UInt32(clamping: previewAgain)
        deck.config.previewHardSecs = UInt32(clamping: previewHard)
        deck.config.previewGoodSecs = UInt32(clamping: previewGood)
        building = true
        defer { building = false }
        do {
            let request = deck
            return try await backend.perform { try $0.addOrUpdateFilteredDeck(request).id }
        } catch {
            self.error = ActionFailure.reason(error)
            return nil
        }
    }

    /// The search behind desktop's "Show any excluded cards": cards the
    /// filters match that are suspended, buried or in another filtered deck.
    func excludedCardsSearch() throws -> String {
        func text(_ search: String) -> Anki_Search_SearchNode {
            var node = Anki_Search_SearchNode()
            node.parsableText = search
            return node
        }
        func group(_ nodes: [Anki_Search_SearchNode], _ joiner: Anki_Search_SearchNode.Group.Joiner) -> Anki_Search_SearchNode {
            var node = Anki_Search_SearchNode()
            node.group.nodes = nodes
            node.group.joiner = joiner
            return node
        }
        func state(_ state: Anki_Search_SearchNode.CardState) -> Anki_Search_SearchNode {
            var node = Anki_Search_SearchNode()
            node.cardState = state
            return node
        }
        var filtered = Anki_Search_SearchNode()
        filtered.deck = "filtered"
        if !isNew {
            var this = Anki_Search_SearchNode()
            this.deck = deck.name
            var other = Anki_Search_SearchNode()
            other.negated = this
            filtered = group([filtered, other], .and)
        }
        let manual = group([text(first.search)] + (secondEnabled ? [text(second.search)] : []), .or)
        let implicit = group([state(.suspended), state(.buried), filtered], .or)
        return try backend.buildSearchString(group([manual, implicit], .and)).val
    }

    /// A search, checked and normalised as desktop does before showing it in the browser.
    func normalisedSearch(_ search: String) throws -> String {
        var node = Anki_Search_SearchNode()
        node.parsableText = search
        return try backend.buildSearchString(node).val
    }
}
