import AnkiKit
import AppKit
import SwiftUI

/// Today and Statistics, which show here, the Browse window, then the decks: every deck,
/// top-level or not, is the same selectable row with one due count, the
/// breakdown being in the overview. A deck with subdecks has a disclosure
/// arrow and sits apart from its neighbours by space alone. Up and Down move through the rows, Left and Right fold and
/// unfold, a double-click renames, and dragging a deck onto another nests it.
struct DeckSidebar: View {
    @Environment(CollectionModel.self) private var model
    @Environment(WindowLayout.self) private var layout
    @State private var expanded: [Int64: Bool] = [:]
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        places
                        decks
                        // Dropping a deck below the list moves it to the top level.
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .contentShape(.rect)
                            .dropDestination(for: String.self) { items, _ in model.dropDecks(items, on: 0) }
                    }
                    .padding(.horizontal, Theme.Spacing.small + 2)
                }
                .scrollIndicators(.never)
                // Rows scroll out of sight below the title bar, not under the
                // window's buttons.
                .clipped()
                .onChange(of: model.selectedDeckID) { _, deckID in
                    if let deckID {
                        reveal(deckID, in: model.decks)
                        withAnimation { scroller.scrollTo(deckID) }
                    }
                }
            }

            footer
        }
        .frame(width: Theme.Layout.sidebarWidth)
        // Up behind the toolbar too, so the sidebar runs the window's height.
        .background(Theme.Palette.sidebar.ignoresSafeArea())
        .overlay(alignment: .trailing) { Theme.Palette.hairline.frame(width: 1).ignoresSafeArea() }
        .onChange(of: model.decks, initial: true) { _, decks in
            seedExpansion(decks)
            if let deckID = model.selectedDeckID { reveal(deckID, in: decks) }
        }
        .onAppear { startKeys() }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    // MARK: Rows

    @ViewBuilder private var places: some View {
        let today = model.page == .today
        SidebarRowShell(selected: today) {
            model.page = .today
            layout.picked()
        } content: {
            AnkiStar(size: 17).foregroundStyle(Theme.Palette.star).frame(width: 20)
            Text("Today").font(Theme.Fonts.row).fontWeight(today ? .semibold : .regular)
            Spacer(minLength: Theme.Spacing.xSmall)
            Text(model.decks.reduce(0) { $0 + $1.dueCount }, format: .number)
                .font(Theme.Fonts.sidebarCount).foregroundStyle(Theme.Palette.secondary)
        }
        place("Browse", "magnifyingglass", Theme.Palette.teal, key: "B") {
            BrowserWindowController.show(collection: model)
        }
        place(Tr.statisticsTitle, "chart.bar.fill", Theme.Palette.violet, key: "T", selected: model.page == .statistics) {
            model.showStatistics()
            layout.picked()
        }
    }

    /// A row with a key, for Browse, which opens a window, and Statistics,
    /// which shows here.
    private func place(
        _ title: String, _ symbol: String, _ tint: Color, key: String, selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        SidebarRowShell(selected: selected, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(title).font(Theme.Fonts.row).fontWeight(selected ? .semibold : .regular)
            Spacer(minLength: Theme.Spacing.xSmall)
            // A key, not a count: drawn as one so it can't be read as a number.
            KeyCap(key)
        }
        .disabled(!model.isLoaded)
    }

    @ViewBuilder private var decks: some View {
        let decks = model.decks
        ForEach(decks.indices, id: \.self) { index in
            let node = decks[index]
            DeckRow(node: node, depth: 0, isExpanded: expansion(node))
                .padding(.top, gap(before: index, in: decks))
                .id(node.id)
            if node.children != nil, expansion(node).wrappedValue {
                DeckTree(nodes: node.children ?? [], depth: 1, expansion: expansion)
            }
        }
    }

    /// Space, not a heading, sets the decks off from the places above, and
    /// sets off each top-level deck that has subdecks from its neighbours.
    private func gap(before index: Int, in decks: [DeckNode]) -> CGFloat {
        if index == 0 { return Theme.Spacing.large }
        return decks[index].children != nil || decks[index - 1].children != nil ? Theme.Spacing.medium : 0
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Button { model.createDeck() } label: {
                Label("New Deck", systemImage: "plus").font(Theme.Fonts.row)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!model.isLoaded)
            Spacer()
            foldAllButton
            SyncButton()
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .frame(height: 48)
        .overlay(alignment: .top) { Theme.Palette.hairline.frame(height: 1) }
    }

    // MARK: Expansion

    private func expansion(_ node: DeckNode) -> Binding<Bool> {
        Binding {
            expanded[node.id] ?? !node.collapsed
        } set: { isExpanded in
            withAnimation(.smooth(duration: 0.2)) { expanded[node.id] = isExpanded }
            model.setCollapsed(node.id, !isExpanded)
        }
    }

    /// Folds every deck while any is open, as Obsidian's file list does, and
    /// otherwise unfolds them all.
    private var foldAllButton: some View {
        let parents = parentDecks(model.decks)
        let anyOpen = parents.contains { expansion($0).wrappedValue }
        let label = anyOpen ? "Collapse All" : "Expand All"
        return Button { setAllExpanded(!anyOpen, parents) } label: {
            FoldAllGlyph(folding: anyOpen ? 1 : 0)
                .frame(width: 30, height: 28)
        }
        .buttonStyle(QuietButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .disabled(!model.isLoaded || parents.isEmpty)
    }

    private func parentDecks(_ nodes: [DeckNode]) -> [DeckNode] {
        nodes.flatMap { node in
            node.children.map { [node] + parentDecks($0) } ?? []
        }
    }

    /// A selected deck that folding hides hands the selection to its
    /// top-level deck, so the arrow keys carry on from a row on screen.
    private func setAllExpanded(_ isExpanded: Bool, _ parents: [DeckNode]) {
        withAnimation(.smooth(duration: 0.25)) {
            for node in parents where expansion(node).wrappedValue != isExpanded {
                expanded[node.id] = isExpanded
                model.setCollapsed(node.id, !isExpanded)
            }
            if !isExpanded, let id = model.selectedDeckID,
               let top = model.decks.first(where: { contains(id, $0.children ?? []) }) {
                model.selectedDeckID = top.id
            }
        }
    }

    private func contains(_ deckID: Int64, _ nodes: [DeckNode]) -> Bool {
        nodes.contains { $0.id == deckID || contains(deckID, $0.children ?? []) }
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

    // MARK: Keys

    /// Today, Statistics and every deck on screen, top to bottom.
    private var visibleRows: [CollectionModel.MainPage] {
        var rows: [CollectionModel.MainPage] = [.today, .statistics]
        func walk(_ nodes: [DeckNode]) {
            for node in nodes {
                rows.append(.deck(node.id))
                if expanded[node.id] ?? !node.collapsed { walk(node.children ?? []) }
            }
        }
        walk(model.decks)
        return rows
    }

    /// The arrow keys move through the rows wherever the focus is, as long
    /// as nothing is being typed and no card is up.
    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window = event.window, window === model.mainWindow, window.isKeyWindow,
              !(window.firstResponder is NSText), model.session == nil, model.renamingDeckID == nil,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        else { return false }
        // Once the page has been clicked or scrolled, Up and Down scroll it.
        if event.keyCode == 125 || event.keyCode == 126, !layout.arrowsMoveSidebar,
           let scrollPage = layout.scrollPage?.scroll {
            _ = scrollPage(event.keyCode == 125 ? Theme.Layout.arrowScroll : -Theme.Layout.arrowScroll)
            return true
        }
        let rows = visibleRows
        let index = rows.firstIndex(of: model.page) ?? 0
        switch event.keyCode {
        case 126: show(rows[max(index - 1, 0)])
        case 125: show(rows[min(index + 1, rows.count - 1)])
        case 123, 124:
            guard let id = model.selectedDeckID, let node = model.deck(id), node.children != nil else { return false }
            expansion(node).wrappedValue = event.keyCode == 124
        default: return false
        }
        return true
    }

    private func show(_ page: CollectionModel.MainPage) {
        if page == .statistics { model.showStatistics() } else { model.page = page }
    }
}

private struct DeckTree: View {
    let nodes: [DeckNode]
    let depth: Int
    let expansion: (DeckNode) -> Binding<Bool>

    var body: some View {
        ForEach(nodes) { node in
            DeckRow(node: node, depth: depth, isExpanded: expansion(node)).id(node.id)
            if node.children != nil, expansion(node).wrappedValue {
                DeckTree(nodes: node.children ?? [], depth: depth + 1, expansion: expansion)
            }
        }
    }
}

private struct DeckRow: View {
    @Environment(CollectionModel.self) private var model
    @Environment(WindowLayout.self) private var layout
    let node: DeckNode
    let depth: Int
    @Binding var isExpanded: Bool

    var body: some View {
        let selected = model.selectedDeckID == node.id
        SidebarRowShell(selected: selected) {
            model.selectedDeckID = node.id
            layout.picked()
        } doubleClick: {
            model.beginRenaming(node.id)
        } content: {
            Group {
                if node.children != nil {
                    Disclosure(isExpanded: $isExpanded)
                } else {
                    Color.clear.frame(width: 12)
                }
            }
            .padding(.leading, CGFloat(depth) * Theme.Layout.indent)
            DeckRing(deck: node, selected: selected)
            if model.renamingDeckID == node.id {
                DeckNameField(node: node)
            } else {
                Text(node.name).font(Theme.Fonts.row).fontWeight(selected ? .semibold : .regular).lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.xSmall)
            if node.dueCount > 0 {
                Text(node.dueCount, format: .number).font(Theme.Fonts.sidebarCount)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
        .deckRowBehaviour(node)
    }
}

private struct Disclosure: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 12, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Palette.tertiary)
        .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
    }
}

private extension View {
    /// Dragging, dropping and the context menu, the same on every deck row.
    func deckRowBehaviour(_ node: DeckNode) -> some View {
        modifier(DeckRowBehaviour(node: node))
    }
}

private struct DeckRowBehaviour: ViewModifier {
    @Environment(CollectionModel.self) private var model
    let node: DeckNode

    func body(content: Content) -> some View {
        content
            .draggable(DeckDrag.text(node.id))
            .dropDestination(for: String.self) { items, _ in model.dropDecks(items, on: node.id) }
            .contextMenu {
                Button("Options…") { model.showOptions(node) }
                if node.filtered {
                    Button(Tr.actionsRebuild) { model.rebuildFilteredDeck(node.id) }
                    Button(Tr.studyingEmpty) { model.emptyFilteredDeck(node.id) }
                } else {
                    Button("\(Tr.actionsCustomStudy)…") { model.showCustomStudy(node.id) }
                }
                Divider()
                Button(Tr.actionsRename) { model.beginRenaming(node.id) }
                Divider()
                Button(Tr.actionsDelete, role: .destructive) { model.deleteDeck(node.id) }
            }
    }
}

/// The shape every sidebar row shares: a soft rounded highlight that shows
/// on hover and stays, a little stronger, on the selected row.
struct SidebarRowShell<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    var doubleClick: (() -> Void)? = nil
    @ViewBuilder let content: Content
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.small) { content }
            .padding(.horizontal, Theme.Spacing.small)
            .frame(height: Theme.Layout.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
                    .fill(selected ? Theme.Palette.selection : hovered && isEnabled ? Theme.Palette.hover : .clear))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(.rect)
            .onTapGesture(perform: action)
            .simultaneousGesture(TapGesture(count: 2).onEnded { doubleClick?() })
            .onHover { hovered = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }
}

/// Sync, with a spinner while it runs (a click cancels), and a dot when
/// something is waiting to sync. Media progress floats over the window,
/// and while it shows, the spinner there is the only one.
private struct SyncButton: View {
    @Environment(CollectionModel.self) private var model

    var body: some View {
        Button {
            if model.syncIsRunning { model.cancelSync() } else { Task { await model.synchronize() } }
        } label: {
            Group {
                if model.syncIsRunning && model.mediaSyncCapsule == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.syncStatus == .fullSync
                        ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .medium))
                        .overlay(alignment: .topTrailing) {
                            if waiting != nil {
                                Circle().fill(Theme.Palette.accent)
                                    .frame(width: Theme.Layout.badgeDot, height: Theme.Layout.badgeDot)
                                    .offset(x: Theme.Spacing.xxSmall, y: -Theme.Spacing.xxSmall)
                            }
                        }
                }
            }
            .frame(minWidth: 30, minHeight: 28)
        }
        .buttonStyle(QuietButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .disabled(!model.isLoaded)
    }

    /// What's waiting to sync, if anything. The queue colours stay with the
    /// queues, so the button says it with the accent dot and these words.
    private var waiting: String? {
        switch model.syncStatus {
        case .fullSync: "a one-way sync is needed"
        case .normalSync: "changes are waiting"
        default: nil
        }
    }

    private var label: String {
        if model.syncIsRunning { return "Cancel Sync" }
        return waiting.map { "Sync: \($0)" } ?? "Sync"
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
            .font(Theme.Fonts.row)
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
