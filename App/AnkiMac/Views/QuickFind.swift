import SwiftUI

/// Things' Quick Find: a field over the main window that finds Today, decks
/// and notes as you type. Return goes to the choice; Command-Return studies
/// a deck straight away, as desktop's Study Deck does.
struct QuickFind: View {
    @Environment(CollectionModel.self) private var model
    @State private var text = ""
    @State private var notes: [QuickFindNote] = []
    @State private var selection = 0
    @State private var listHeight: CGFloat = 0
    @State private var pointer = NSEvent.mouseLocation
    @FocusState private var focused: Bool

    private enum Hit: Hashable {
        case today
        case deck(DeckNode)
        case note(QuickFindNote)
        case newDeck(String)
        case browse(String)
    }

    private var query: String { text.trimmingCharacters(in: .whitespaces) }

    /// Places, then notes, then what to do with the text, each set off by a rule.
    private var groups: [[Hit]] {
        guard !query.isEmpty else { return [places] }
        let named = flattened(model.decks).contains { $0.fullName.caseInsensitiveCompare(query) == .orderedSame }
        let actions: [Hit] = (named ? [] : [.newDeck(query)]) + [.browse(query)]
        return [places, notes.map(Hit.note), actions].filter { !$0.isEmpty }
    }

    private var hits: [Hit] { groups.flatMap(\.self) }

    /// Before anything is typed, Today and the first decks it would study.
    /// Then every word typed appears in the name, in any order, as desktop's
    /// Study Deck matches. Names that start with the first word come first.
    private var places: [Hit] {
        guard !query.isEmpty else {
            let due = flattened(model.decks).filter { $0.children == nil && $0.dueCount > 0 }
                .sorted { ($0.learnCount, $0.dueCount) > ($1.learnCount, $1.dueCount) }
            return [.today] + due.prefix(Theme.QuickFind.dueLimit).map(Hit.deck)
        }
        let words = query.split(separator: " ")
        let matches = { (name: String) in words.allSatisfy { name.localizedCaseInsensitiveContains($0) } }
        let starts = { (name: String) in
            words.first.map { name.range(of: $0, options: [.caseInsensitive, .anchored]) != nil } ?? true
        }
        let decks = flattened(model.decks).filter { matches($0.fullName) }
        let today: [Hit] = matches("Today") ? [.today] : []
        return today + (decks.filter { starts($0.name) } + decks.filter { !starts($0.name) }).map(Hit.deck)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            field
            if !hits.isEmpty {
                ScrollViewReader { scroller in
                    ScrollView {
                        list
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                    }
                    .frame(height: min(listHeight, Theme.QuickFind.listMaxHeight))
                    .scrollIndicators(.automatic)
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                    .onChange(of: selection) { _, index in scroller.scrollTo(index) }
                }
            }
        }
        .padding(Theme.Spacing.small)
        .frame(width: Theme.QuickFind.width)
        .glassEffect(
            .regular.tint(Theme.Palette.canvas.opacity(Theme.QuickFind.tintOpacity)),
            in: RoundedRectangle(cornerRadius: Theme.QuickFind.cornerRadius))
        .onAppear { focused = true }
        .onChange(of: query) { selection = 0 }
        .task(id: query) {
            guard !query.isEmpty else { notes = []; return }
            // Waits for a pause in typing before searching the collection.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            notes = await model.quickFindNotes(query, limit: Theme.QuickFind.noteLimit)
        }
    }

    private var field: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.secondary)
            TextField("Quick Find", text: $text, prompt: Text("Quick Find", comment: "Quick Find's field, before anything is typed"))
                .textFieldStyle(.plain)
                .font(Theme.Fonts.lead)
                .focused($focused)
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(keys: [.return]) { press in
                    choose(studying: press.modifiers.contains(.command))
                    return .handled
                }
                .onExitCommand { model.quickFindPresented = false }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .frame(height: Theme.QuickFind.fieldHeight)
        .background(RoundedRectangle(cornerRadius: Theme.QuickFind.fieldRadius).fill(Theme.Palette.selection))
    }

    private var list: some View {
        let groups = groups
        return VStack(spacing: 0) {
            ForEach(groups.indices, id: \.self) { group in
                if group > 0 {
                    Divider().padding(.vertical, Theme.Spacing.xSmall).padding(.horizontal, Theme.Spacing.small)
                }
                let base = groups[..<group].reduce(0) { $0 + $1.count }
                ForEach(groups[group].indices, id: \.self) { offset in
                    row(groups[group][offset], index: base + offset)
                }
            }
        }
        // Notes arrive after a pause in typing; let them settle in rather than jump.
        .animation(.easeOut(duration: 0.15), value: notes)
    }

    private func row(_ hit: Hit, index: Int) -> some View {
        let selected = index == selection
        return Button {
            selection = index
            choose(studying: false)
        } label: {
            HStack(spacing: Theme.Spacing.small) {
                icon(hit).frame(width: 20)
                // The path follows the name on one line, losing its start first when short of room.
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    Text(title(hit)).font(Theme.Fonts.listRow).layoutPriority(1)
                    if let subtitle = subtitle(hit) {
                        Text(subtitle)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(selected ? Color.white.opacity(0.75) : Theme.Palette.tertiary)
                            .truncationMode(.head)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: Theme.Spacing.small)
                if selected, case .deck = hit {
                    // Command-Return studies the deck, as desktop's Study Deck does.
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Text(Tr.decksStudy).font(Theme.Fonts.caption).foregroundStyle(Color.white.opacity(0.8))
                        KeyCap("⌘↩", onAccent: true)
                    }
                } else if let count = count(hit), count > 0 {
                    Text(count, format: .number)
                        .font(Theme.Fonts.sidebarCount)
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Theme.Palette.secondary)
                }
            }
            .foregroundStyle(selected ? Color.white : Theme.Palette.text)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.QuickFind.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.QuickFind.rowRadius).fill(selected ? Theme.Palette.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        // The choice follows the pointer only when it moves, not when the list scrolls under it.
        .onHover { inside in
            guard inside, NSEvent.mouseLocation != pointer else { return }
            pointer = NSEvent.mouseLocation
            selection = index
        }
        .id(index)
    }

    @ViewBuilder private func icon(_ hit: Hit) -> some View {
        switch hit {
        case .today: AnkiStar(size: 16).foregroundStyle(Theme.Palette.star)
        case .deck(let deck): DeckRing(deck: deck, size: 16)
        case .note: Image(systemName: "rectangle.on.rectangle").foregroundStyle(Theme.Palette.secondary)
        case .newDeck: Image(systemName: "plus").foregroundStyle(Theme.Palette.secondary)
        case .browse: Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.secondary)
        }
    }

    private func title(_ hit: Hit) -> String {
        switch hit {
        case .today: "Today"
        case .deck(let deck): deck.name
        case .note(let note):
            note.text.isEmpty ? String(localized: "Empty Note", comment: "A note whose first field is empty, in Quick Find") : note.text
        case .newDeck(let name): String(localized: "New Deck “\(name)”", comment: "Quick Find's row that creates a deck named as typed")
        case .browse: String(localized: "Continue Search in Browser", comment: "Quick Find's last row")
        }
    }

    /// A subdeck's parents, and the deck a note's cards are in.
    private func subtitle(_ hit: Hit) -> String? {
        switch hit {
        case .deck(let deck):
            let parents = deck.fullName.components(separatedBy: "::").dropLast()
            return parents.isEmpty ? nil : parents.joined(separator: " › ")
        case .note(let note): return model.deck(note.deckID)?.fullName.replacing("::", with: " › ")
        default: return nil
        }
    }

    private func count(_ hit: Hit) -> Int? {
        switch hit {
        case .today: model.decks.reduce(0) { $0 + $1.dueCount }
        case .deck(let deck): deck.dueCount
        default: nil
        }
    }

    /// Up and Down move the choice while the field keeps the keys, wrapping round.
    private func move(_ step: Int) -> KeyPress.Result {
        let count = hits.count
        if count > 0 { selection = (selection + step + count) % count }
        return .handled
    }

    private func choose(studying: Bool) {
        let hits = hits
        guard hits.indices.contains(selection) else { return }
        switch hits[selection] {
        case .today: model.showToday()
        case .deck(let deck):
            model.showOverview(of: deck.id)
            if studying { model.startStudying() }
        case .note(let note): model.showInBrowser(note: note.id)
        case .newDeck(let name):
            model.quickFindPresented = false
            model.addDeckAndShow(named: name)
        case .browse(let text): model.continueSearchInBrowser(text)
        }
    }

    private func flattened(_ decks: [DeckNode]) -> [DeckNode] {
        decks.flatMap { [$0] + flattened($0.children ?? []) }
    }
}
