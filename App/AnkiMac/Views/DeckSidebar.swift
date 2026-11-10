import AnkiKit
import SwiftUI

struct DeckSidebar: View {
    @Environment(CollectionModel.self) private var model
    @State private var expanded: [Int64: Bool] = [:]

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedDeckID) {
            Section {
                DeckRows(nodes: model.decks, expanded: $expanded)
            } header: {
                // Dropping a deck on the header moves it to the top level.
                Text("Decks")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .dropDestination(for: String.self) { items, _ in
                        model.dropDecks(items, on: 0)
                    }
            }
        }
        .contextMenu(forSelectionType: Int64.self) { ids in
            if let id = ids.first, ids.count == 1, let deck = model.deck(id) {
                Button("Options…") { model.showOptions(deck) }
                if deck.filtered {
                    Button(Tr.actionsRebuild) { model.rebuildFilteredDeck(id) }
                    Button(Tr.studyingEmpty) { model.emptyFilteredDeck(id) }
                } else {
                    Button("\(Tr.actionsCustomStudy)…") { model.showCustomStudy(id) }
                }
                Divider()
                Button(Tr.actionsRename) { model.beginRenaming(id) }
                Divider()
                Button(Tr.actionsDelete, role: .destructive) { model.deleteDeck(id) }
            } else if ids.isEmpty {
                Button("New Deck") { model.createDeck() }
            }
        } primaryAction: { ids in
            // A double-click on a deck edits its name, as in Things and Finder.
            if let id = ids.first, ids.count == 1 { model.beginRenaming(id) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("New Deck", systemImage: "plus") { model.createDeck() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Sidebar.footerPadding)
                .disabled(!model.isLoaded)
        }
        .navigationSplitViewColumnWidth(min: Theme.Sidebar.minWidth, ideal: Theme.Sidebar.idealWidth)
        .onChange(of: model.decks, initial: true) { _, decks in
            seedExpansion(decks)
            if let deckID = model.selectedDeckID { reveal(deckID, in: decks) }
        }
        .onChange(of: model.selectedDeckID) { _, deckID in
            if let deckID { reveal(deckID, in: model.decks) }
        }
    }

    /// Expands the parents of a deck selected from elsewhere, such as one
    /// just created inside a collapsed deck. Returns whether it was found.
    @discardableResult
    private func reveal(_ deckID: Int64, in nodes: [DeckNode]) -> Bool {
        for node in nodes {
            if node.id == deckID { return true }
            if reveal(deckID, in: node.children ?? []) {
                if expanded[node.id] != true {
                    expanded[node.id] = true
                    model.setCollapsed(node.id, false)
                }
                return true
            }
        }
        return false
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
                    draggableRow(node)
                }
                .tag(node.id)
            } else {
                draggableRow(node).tag(node.id)
            }
        }
    }

    /// Dragging a deck onto another nests it there, as on desktop.
    private func draggableRow(_ node: DeckNode) -> some View {
        DeckRow(node: node)
            .draggable(DeckDrag.text(node.id))
            .dropDestination(for: String.self) { items, _ in
                model.dropDecks(items, on: node.id)
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

/// A dragged deck travels as text, so no custom type needs declaring.
enum DeckDrag {
    private static let prefix = "anki-mac-deck:"

    static func text(_ deckID: Int64) -> String { prefix + String(deckID) }

    static func deckID(_ text: String) -> Int64? {
        text.hasPrefix(prefix) ? Int64(text.dropFirst(prefix.count)) : nil
    }
}

extension CollectionModel {
    /// Moves the dragged decks under `parentID`, 0 for the top level.
    func dropDecks(_ items: [String], on parentID: Int64) {
        let ids = items.compactMap(DeckDrag.deckID)
        if !ids.isEmpty { moveDecks(ids, to: parentID) }
    }
}

private struct DeckRow: View {
    @Environment(CollectionModel.self) private var model
    let node: DeckNode

    var body: some View {
        Label {
            HStack(spacing: Theme.Spacing.small) {
                if model.renamingDeckID == node.id {
                    DeckNameField(node: node)
                } else {
                    Text(node.name).lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.small)
                DueCounts(new: node.newCount, learn: node.learnCount, review: node.reviewCount)
                    .font(Theme.Fonts.sidebarCount)
            }
        } icon: {
            Image(systemName: node.filtered ? "line.3.horizontal.decrease.circle" : "rectangle.stack")
        }
        .accessibilityElement(children: model.renamingDeckID == node.id ? .contain : .combine)
    }
}

/// The deck's name, editable in place. Return or clicking away keeps the
/// new name; Escape puts the old one back.
private struct DeckNameField: View {
    @Environment(CollectionModel.self) private var model
    let node: DeckNode
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(Tr.actionsRename, text: $name)
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($focused)
            .onSubmit { model.finishRenaming(node.id, to: name) }
            .onExitCommand { model.finishRenaming(node.id, to: nil) }
            .onChange(of: focused) { _, focused in
                if !focused { model.finishRenaming(node.id, to: name) }
            }
            .onAppear {
                name = node.name
                focused = true
            }
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
