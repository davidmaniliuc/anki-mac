import AnkiKit
import SwiftUI

struct DeckSidebar: View {
    @Environment(CollectionModel.self) private var model
    @State private var expanded: [Int64: Bool] = [:]

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedDeckID) {
            Section("Decks") {
                DeckRows(nodes: model.decks, expanded: $expanded)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if let id = ids.first, ids.count == 1, let deck = model.deck(id) {
                Button("Options…") { model.showOptions(deck) }
                if deck.filtered {
                    Button(Tr.actionsRebuild) { model.rebuildFilteredDeck(id) }
                    Button(Tr.studyingEmpty) { model.emptyFilteredDeck(id) }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: Theme.Sidebar.minWidth, ideal: Theme.Sidebar.idealWidth)
        .onChange(of: model.decks, initial: true) { _, decks in
            seedExpansion(decks)
        }
    }

    /// Starts from the collapsed state stored in the collection.
    private func seedExpansion(_ nodes: [DeckNode]) {
        for node in nodes where expanded[node.id] == nil {
            expanded[node.id] = !node.collapsed
            seedExpansion(node.children ?? [])
        }
    }
}

private struct DeckRows: View {
    @Environment(CollectionModel.self) private var model
    let nodes: [DeckNode]
    @Binding var expanded: [Int64: Bool]

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: expansion(node)) {
                    DeckRows(nodes: children, expanded: $expanded)
                } label: {
                    DeckRow(node: node)
                }
                .tag(node.id)
            } else {
                DeckRow(node: node).tag(node.id)
            }
        }
    }

    private func expansion(_ node: DeckNode) -> Binding<Bool> {
        Binding {
            expanded[node.id] ?? !node.collapsed
        } set: { isExpanded in
            expanded[node.id] = isExpanded
            model.setCollapsed(node.id, !isExpanded)
        }
    }
}

private struct DeckRow: View {
    let node: DeckNode

    var body: some View {
        Label {
            HStack(spacing: Theme.Spacing.small) {
                Text(node.name).lineLimit(1)
                Spacer(minLength: Theme.Spacing.small)
                DueCounts(new: node.newCount, learn: node.learnCount, review: node.reviewCount)
                    .font(Theme.Fonts.sidebarCount)
            }
        } icon: {
            Image(systemName: node.filtered ? "line.3.horizontal.decrease.circle" : "rectangle.stack")
        }
        .accessibilityElement(children: .combine)
    }
}

/// New, learning and review counts in Anki's colours.
struct DueCounts: View {
    let new: Int
    let learn: Int
    let review: Int
    var highlighted: Anki_Scheduler_QueuedCards.Queue? = nil
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            count(new, Theme.Colors.newCards, queue: .new)
            count(learn, Theme.Colors.learnCards, queue: .learning)
            count(review, Theme.Colors.reviewCards, queue: .review)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(new) new, \(learn) learning, \(review) to review")
    }

    private func count(_ value: Int, _ color: Color, queue: Anki_Scheduler_QueuedCards.Queue) -> some View {
        // On a selected row the accent fill would swallow the colours, so the
        // counts go plain, as badges do in Mail and Finder.
        Text(value, format: .number)
            .foregroundStyle(
                prominence == .increased ? AnyShapeStyle(.primary)
                    : value == 0 ? AnyShapeStyle(Theme.Colors.zeroCount) : AnyShapeStyle(color))
            .underline(highlighted == queue)
    }
}
