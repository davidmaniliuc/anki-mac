import SwiftUI

/// What the whole collection has due today, shown when no deck is picked:
/// the total and its three queues, then each deck with cards due, those with cards in
/// learning first since they come back within minutes.
struct TodayView: View {
    @Environment(CollectionModel.self) private var model

    private struct DueDeck: Identifiable {
        let deck: DeckNode
        let path: String
        var id: Int64 { deck.id }
    }

    /// Decks without subdecks that have cards due, with the path to them.
    private var dueDecks: [DueDeck] {
        func walk(_ nodes: [DeckNode], path: [String]) -> [DueDeck] {
            nodes.flatMap { node -> [DueDeck] in
                if let children = node.children { return walk(children, path: path + [node.name]) }
                return node.dueCount > 0 ? [DueDeck(deck: node, path: path.joined(separator: " › "))] : []
            }
        }
        return walk(model.decks, path: [])
            .sorted { ($0.deck.learnCount, $0.deck.dueCount) > ($1.deck.learnCount, $1.deck.dueCount) }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        Page {
            PageTitle(
                eyebrow: greeting + " · " + Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                title: "Today"
            ) {
                AnkiStar(size: 26).foregroundStyle(Theme.Palette.star)
            }

            let due = dueDecks
            if due.isEmpty {
                Text("Nothing is due. Come back tomorrow.")
                    .font(Theme.Fonts.lead)
                    .foregroundStyle(Theme.Palette.secondary)
            } else {
                DueSummary(
                    new: model.decks.reduce(0) { $0 + $1.newCount },
                    learn: model.decks.reduce(0) { $0 + $1.learnCount },
                    review: model.decks.reduce(0) { $0 + $1.reviewCount }
                ) { EmptyView() }
                PageSection("Due Today") {
                    ForEach(due) { DeckListRow(deck: $0.deck, path: $0.path) }
                }
            }
        }
    }
}
