import AnkiKit
import Foundation
import Observation

/// Desktop's Custom Study dialog: raise today's limits on the deck, or build
/// the "Custom Study Session" filtered deck from it.
@Observable
final class CustomStudyModel: Identifiable {
    enum Option: CaseIterable {
        case newLimit, reviewLimit, forgot, ahead, preview, cram

        var title: String {
            switch self {
            case .newLimit: Tr.customStudyIncreaseTodaysNewCardLimit
            case .reviewLimit: Tr.customStudyIncreaseTodaysReviewCardLimit
            case .forgot: Tr.customStudyReviewForgottenCards
            case .ahead: Tr.customStudyReviewAhead
            case .preview: Tr.customStudyPreviewNewCards
            case .cram: Tr.customStudyStudyByCardStateOrTag
            }
        }

        var range: ClosedRange<Int> {
            switch self {
            // A negative value takes back an earlier increase.
            case .newLimit, .reviewLimit: -Self.maxCards...Self.maxCards
            case .forgot: 1...30
            case .ahead, .preview, .cram: 1...Self.maxCards
            }
        }

        /// Desktop's DYN_MAX_SIZE.
        private static let maxCards = 99999
    }

    enum CramKind: CaseIterable {
        case new, due, review, all

        var title: String {
            switch self {
            case .new: Tr.customStudyNewCardsOnly
            case .due: Tr.customStudyDueCardsOnly
            case .review: Tr.customStudyAllReviewCardsInRandomOrder
            case .all: Tr.customStudyAllCardsInRandomOrderDont
            }
        }

        var proto: Anki_Scheduler_CustomStudyRequest.Cram.CramKind {
            switch self {
            case .new: .new
            case .due: .due
            case .review: .review
            case .all: .all
            }
        }
    }

    struct Tag: Identifiable {
        let name: String
        var include: Bool
        var exclude: Bool

        var id: String { name }
    }

    let id = UUID()
    let deckID: Int64
    private let backend: AnkiBackend
    private let defaults: Anki_Scheduler_CustomStudyDefaultsResponse
    /// Whether the deck has any cards; the session decks need some.
    private let hasCards: Bool

    var option: Option = .newLimit {
        didSet { if option != oldValue { value = defaultValue } }
    }
    var value: Int
    var cramKind: CramKind = .new
    /// Desktop's "Require one or more of these tags"; off means any tag.
    var requireTags: Bool
    var tags: [Tag]
    var error: String?
    private(set) var running = false

    private init(deckID: Int64, backend: AnkiBackend, defaults: Anki_Scheduler_CustomStudyDefaultsResponse, hasCards: Bool) {
        self.deckID = deckID
        self.backend = backend
        self.defaults = defaults
        self.hasCards = hasCards
        value = Int(defaults.extendNew)
        tags = defaults.tags.map { Tag(name: $0.name, include: $0.include, exclude: $0.exclude) }
        requireTags = defaults.tags.contains { $0.include }
    }

    static func load(deckID: Int64, backend: AnkiBackend) async throws -> CustomStudyModel {
        let (defaults, hasCards) = try await backend.perform { backend in
            var request = Anki_Scheduler_CustomStudyDefaultsRequest()
            request.deckID = deckID
            var deck = Anki_Decks_DeckId()
            deck.did = deckID
            let name = try backend.getDeck(deck).name
            var search = Anki_Search_SearchNode()
            search.deck = name.replacingOccurrences(of: "\u{1f}", with: "::")
            var cards = Anki_Search_SearchRequest()
            cards.search = try backend.buildSearchString(search).val
            return (try backend.customStudyDefaults(request), !(try backend.searchCards(cards).ids.isEmpty))
        }
        return CustomStudyModel(deckID: deckID, backend: backend, defaults: defaults, hasCards: hasCards)
    }

    private var defaultValue: Int {
        switch option {
        case .newLimit: Int(defaults.extendNew)
        case .reviewLimit: Int(defaults.extendReview)
        case .forgot, .ahead, .preview: 1
        case .cram: 100
        }
    }

    /// "Available new cards: 12 (3 in subdecks)" above the limit options.
    var available: String? {
        switch option {
        case .newLimit:
            Tr.customStudyAvailableNewCards2(
                countString: count(defaults.availableNew, children: defaults.availableNewInChildren))
        case .reviewLimit:
            Tr.customStudyAvailableReviewCards2(
                countString: count(defaults.availableReview, children: defaults.availableReviewInChildren))
        default: nil
        }
    }

    private func count(_ own: UInt32, children: UInt32) -> String {
        children > 0 ? "\(own) \(Tr.customStudyAvailableChildCount(count: String(children)))" : String(own)
    }

    /// The words before and after the number, as desktop's sentence reads.
    var valueLabels: (before: String, after: String) {
        switch option {
        case .newLimit: (Tr.customStudyIncreaseTodaysNewCardLimitBy, Tr.customStudyCards(count: value))
        case .reviewLimit: (Tr.customStudyIncreaseTodaysReviewLimitBy, Tr.customStudyCards(count: value))
        case .forgot: (Tr.customStudyReviewCardsForgottenInLast, Tr.customStudyDays(count: value))
        case .ahead: (Tr.customStudyReviewAheadBy, Tr.customStudyDays(count: value))
        case .preview: (Tr.customStudyPreviewNewCardsAddedInThe, Tr.customStudyDays(count: value))
        case .cram: (Tr.customStudySelect, Tr.customStudyCardsFromTheDeck(count: value))
        }
    }

    var canRun: Bool {
        !running && option.range.contains(value)
            && (option == .newLimit || option == .reviewLimit || hasCards)
    }

    /// Runs the request and returns the deck to show: this one after a limit
    /// change, otherwise the session deck. nil after an error, such as no
    /// cards matching, so the dialog stays open to change the criteria.
    func run() async -> Int64? {
        var request = Anki_Scheduler_CustomStudyRequest()
        request.deckID = self.deckID
        switch option {
        case .newLimit: request.newLimitDelta = Int32(value)
        case .reviewLimit: request.reviewLimitDelta = Int32(value)
        case .forgot: request.forgotDays = UInt32(value)
        case .ahead: request.reviewAheadDays = UInt32(value)
        case .preview: request.previewDays = UInt32(value)
        case .cram:
            var cram = Anki_Scheduler_CustomStudyRequest.Cram()
            cram.kind = cramKind.proto
            cram.cardLimit = UInt32(value)
            cram.tagsToInclude = requireTags ? tags.filter(\.include).map(\.name) : []
            cram.tagsToExclude = tags.filter(\.exclude).map(\.name)
            guard cram.tagsToInclude.count + cram.tagsToExclude.count <= 100 else {
                error = Tr.errors100TagsMax
                return nil
            }
            request.cram = cram
        }
        let isLimit = option == .newLimit || option == .reviewLimit
        let deckID = deckID
        let finished = request
        running = true
        defer { running = false }
        do {
            return try await backend.perform { backend in
                _ = try backend.customStudy(finished)
                guard !isLimit else { return deckID }
                // The backend names the session deck in its own language, English here.
                var name = Anki_Generic_String()
                name.val = Tr.customStudyCustomStudySession
                return try backend.getDeckIdByName(name).did
            }
        } catch {
            self.error = FilteredDeckModel.message(error)
            return nil
        }
    }
}
