import AnkiKit
import AppKit
import SwiftUI

/// The Browser's search, as Mail's: what a sidebar row stands for (a deck,
/// a tag, a note type, a card state, a flag) shows as a chip, the rest as
/// typed. Typing lists the rows that match the word being typed in a panel
/// under the field, and picking one makes it a chip and searches at once;
/// Return on "Search for" searches for the text. `deck:`, `tag:`, `note:`,
/// `is:` and `flag:` before the word keep the list to that kind, and Down
/// Arrow opens it with nothing typed. Delete on empty text selects the last
/// chip, and again removes it; Esc takes back what was typed. A filtered
/// deck's search is the same field (see `SearchFieldSource`).
struct BrowserSearchField: View {
    let model: any SearchFieldSource
    /// Called before each search the field starts, so the sidebar lets go of its rows.
    var willSearch: () -> Void = {}
    var focusOnAppear = true

    @State private var query = SearchQuery("", sidebar: [])
    @State private var text = ""
    @State private var selectedChip: Int?
    @State private var suggestions = SearchSuggestions()
    @FocusState private var focused: Bool
    @State private var scrolled = false
    private static let textID = "text"

    var body: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Palette.secondary)
                .accessibilityHidden(true)
            GeometryReader { geometry in
                ScrollViewReader { scroller in
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.xSmall) {
                            ForEach(Array(query.chips.enumerated()), id: \.offset) { index, chip in
                                chipView(chip, index: index)
                            }
                            TextField(Tr.actionsSearch, text: typing, prompt: query.chips.isEmpty ? Text(Tr.actionsSearch) : Text(""))
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .labelsHidden()
                                .focused($focused)
                                .onKeyPress(phases: .down, action: key)
                                .frame(minWidth: Theme.Browser.searchTextMinWidth, maxWidth: .infinity)
                                .id(Self.textID)
                        }
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .leading)
                    }
                    .scrollIndicators(.never)
                    .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.x > 0 } action: { scrolled = $1 }
                    // Chips scrolled out of sight fade under the magnifier rather than end in a cut.
                    .mask {
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                .frame(width: scrolled ? Theme.Browser.searchFadeWidth : 0)
                            Color.black
                        }
                    }
                    // The text stays in sight as chips are added and it grows.
                    .onChange(of: query) { scroller.scrollTo(Self.textID, anchor: .trailing) }
                    .onChange(of: text) { scroller.scrollTo(Self.textID, anchor: .trailing) }
                }
            }
            if !query.chips.isEmpty || !text.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Clear")
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Theme.Spacing.small)
        .frame(height: Theme.Browser.searchHeight)
        // The field has the focus nearly always, so it deepens a step for it
        // rather than wearing an accent ring the whole time.
        .background(Capsule().fill(focused ? Theme.Palette.selection : Theme.Palette.hover))
        .animation(.easeOut(duration: 0.15), value: focused)
        .background(FloatingListAnchor { suggestions.anchor = $0 })
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .onChange(of: model.searchText, initial: true) { _, search in
            query = SearchQuery(search, sidebar: model.sidebar)
            text = query.text
            selectedChip = nil
        }
        .onChange(of: model.sidebar) { _, sidebar in
            // A reload keeps what is being typed.
            let typed = text != query.text
            query = SearchQuery(model.searchText, sidebar: sidebar)
            if !typed { text = query.text }
        }
        .onChange(of: focused) { _, focused in
            if !focused {
                selectedChip = nil
                suggestions.hide()
            }
        }
        .onAppear {
            suggestions.pick = { [self] in pick($0) }
            if focusOnAppear { focused = true }
        }
        .onDisappear { suggestions.hide() }
    }

    private func chipView(_ chip: SearchQuery.Chip, index: Int) -> some View {
        let selected = selectedChip == index
        return HStack(spacing: Theme.Spacing.xSmall) {
            Image(systemName: chip.item.systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? Color.white : chip.item.tint)
            Text(chip.title)
                .font(Theme.Browser.searchChipFont)
                .foregroundStyle(selected ? Color.white : Theme.Palette.text)
                .lineLimit(1)
                // A deck's own name is at the end of its path.
                .truncationMode(.head)
            Button { remove(at: index) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(selected ? Color.white : Theme.Palette.secondary)
                    .frame(width: 12, height: 12)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.leading, Theme.Spacing.small - 2)
        .padding(.trailing, Theme.Spacing.xSmall)
        .frame(maxWidth: Theme.Browser.searchChipMaxWidth)
        .frame(height: Theme.Browser.searchChipHeight)
        .background(
            Capsule().fill(selected ? Theme.Palette.accent : Theme.Palette.raised)
                .overlay(Capsule().strokeBorder(selected ? .clear : Theme.Palette.hairline)))
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Capsule())
        .onTapGesture {
            selectedChip = index
            focused = true
        }
        .help("\(chip.item.kindName): \(chip.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chip.item.kindName): \(chip.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Remove") { remove(at: index) }
    }

    // MARK: Typing

    /// The text as typed: only the user's typing opens the suggestions, not
    /// a search putting its text in the field.
    private var typing: Binding<String> {
        Binding(
            get: { text },
            set: { new in
                text = new
                selectedChip = nil
                model.edited(chips: query.chips.map(\.raw), text: new)
                refreshSuggestions(all: false)
            })
    }

    /// The word the suggestions are for: the last one, until a space ends it.
    private var word: String {
        guard let last = text.last, !last.isWhitespace else { return "" }
        return SearchQuery.terms(text).last ?? ""
    }

    private func refreshSuggestions(all: Bool) {
        let word = word
        guard focused, all || !word.isEmpty else { return suggestions.hide() }
        let have = Set(query.chips.map(\.item.id))
        let groups = SearchSuggestions.groups(for: word, in: model.sidebar, excluding: have, typed: text)
        let search = text.trimmingCharacters(in: .whitespaces)
        suggestions.show(groups, searchFor: search.isEmpty ? nil : search)
    }

    private func key(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        switch press.key {
        case .downArrow:
            if suggestions.isShown { suggestions.move(1) } else { refreshSuggestions(all: true) }
        case .upArrow where suggestions.isShown:
            suggestions.move(-1)
        case .escape:
            if suggestions.isShown {
                suggestions.hide()
            } else if selectedChip != nil {
                selectedChip = nil
            } else if text != query.text {
                text = query.text
                model.edited(chips: query.chips.map(\.raw), text: text)
            } else {
                return .ignored
            }
        case .return:
            if suggestions.isShown {
                suggestions.pickHighlighted()
            } else if model.searchesOnReturn {
                submit()
            } else {
                return .ignored
            }
        // A text field hands Backspace on as DEL, not as `.delete`.
        case .delete where text.isEmpty, KeyEquivalent("\u{7F}") where text.isEmpty:
            guard !query.chips.isEmpty else { return .ignored }
            if let selected = selectedChip {
                remove(at: selected)
            } else {
                selectedChip = query.chips.count - 1
            }
        default:
            return .ignored
        }
        return .handled
    }

    // MARK: Searching

    /// A row from the suggestions takes the place of the word typed for it.
    private func pick(_ pick: SearchSuggestions.Pick) {
        suggestions.hide()
        let rest = String(text.dropLast(word.count)).trimmingCharacters(in: .whitespaces)
        switch pick {
        case .text:
            submit()
        case .item(let item):
            text = rest
            willSearch()
            model.search(chips: query.chips.map(\.raw), adding: item, text: rest)
        case .term(let term, _):
            text = rest.isEmpty ? term : "\(rest) \(term)"
            submit()
        }
    }

    private func submit() {
        suggestions.hide()
        willSearch()
        model.search(chips: query.chips.map(\.raw), text: text)
    }

    private func remove(at index: Int) {
        var chips = query.chips.map(\.raw)
        guard chips.indices.contains(index) else { return }
        chips.remove(at: index)
        selectedChip = nil
        focused = true
        willSearch()
        model.search(chips: chips, text: text)
    }

    private func clear() {
        text = ""
        suggestions.hide()
        focused = true
        willSearch()
        model.search(chips: [], text: "")
    }
}

/// What the word being typed could mean, by kind, in a Liquid Glass panel
/// under the field (`FloatingList`): first "Search for" the text, then the
/// decks, tags, note types, card states, flags and saved searches whose
/// names match it.
@Observable
final class SearchSuggestions {
    /// What a row stands for.
    enum Pick {
        /// "Search for" the text.
        case text
        case item(SidebarItem)
        /// A search keyword with no sidebar row, such as `is:due`, which
        /// stays text; with its symbol.
        case term(String, systemImage: String)
    }

    struct Row: Identifiable {
        let id: Int
        let pick: Pick
        let title: String
        /// A deck or tag's parents, after its name.
        let detail: String?

        var item: SidebarItem? {
            if case .item(let item) = pick { item } else { nil }
        }

        var systemImage: String {
            switch pick {
            case .text: "magnifyingglass"
            case .item(let item): item.systemImage
            case .term(_, let systemImage): systemImage
            }
        }
    }

    struct Group {
        let title: String?
        let rows: [Row]
    }

    private(set) var groups: [Group] = []
    private(set) var width: CGFloat = 0
    var highlighted = 0
    @ObservationIgnored weak var anchor: NSView?
    @ObservationIgnored var pick: (Pick) -> Void = { _ in }
    @ObservationIgnored private let list = FloatingList()

    var isShown: Bool { list.isShown }

    private var rows: [Row] { groups.flatMap(\.rows) }

    func show(_ matches: [(title: String, items: [(Pick, String)])], searchFor search: String?) {
        var next = 0
        func row(_ pick: Pick, _ title: String) -> Row {
            defer { next += 1 }
            switch pick {
            case .item(.deck(_, let name)), .item(.tag(let name)): return Self.pathRow(next, pick, name)
            default: return Row(id: next, pick: pick, title: title, detail: nil)
            }
        }
        var groups: [Group] = []
        if let search { groups.append(Group(title: nil, rows: [row(.text, "Search for \u{201C}\(search)\u{201D}")])) }
        for match in matches {
            groups.append(Group(title: match.title, rows: match.items.map { row($0.0, $0.1) }))
        }
        self.groups = groups
        highlighted = 0
        guard !matches.isEmpty, let anchor else { return hide() }
        let inset = Theme.Tags.popupPadding
        width = max(anchor.bounds.width + 2 * inset, Theme.Browser.suggestionsMinWidth)
        list.show(SearchSuggestionList(suggestions: self), under: anchor, inset: inset)
    }

    private static func pathRow(_ id: Int, _ pick: Pick, _ name: String) -> Row {
        let parts = name.components(separatedBy: "::")
        let parents = parts.dropLast().joined(separator: " › ")
        return Row(id: id, pick: pick, title: parts.last ?? name, detail: parents.isEmpty ? nil : parents)
    }

    func hide() {
        list.hide()
    }

    func move(_ step: Int) {
        highlighted = (highlighted + step + rows.count) % rows.count
    }

    func pickHighlighted() {
        guard rows.indices.contains(highlighted) else { return hide() }
        pick(rows[highlighted].pick)
    }

    fileprivate func pick(row: Int) {
        guard rows.indices.contains(row) else { return }
        pick(rows[row].pick)
    }

    // MARK: Matching

    /// What a word before a colon keeps the list to.
    private static let prefixes: [String: SidebarKind] = [
        "deck:": .deckRoot, "tag:": .tagRoot, "note:": .notetypeRoot, "is:": .cardStateRoot, "flag:": .flagRoot,
    ]
    /// The kinds in the order they're listed, each with how many rows it shows.
    private static let kinds: [(SidebarKind, Int)] = [
        (.deckRoot, 5), (.tagRoot, 5), (.notetypeRoot, 4), (.cardStateRoot, 5), (.flagRoot, 7), (.savedSearchRoot, 3),
    ]

    /// The card states' search keywords, which `is:` matches as well as
    /// their names, so `is:l` finds Learning.
    private static let stateKeywords: [Anki_Search_SearchNode.CardState: String] = [
        .new: "new", .learn: "learn", .review: "review", .suspended: "suspended", .buried: "buried",
    ]
    /// `is:` keywords with no sidebar row, listed with the card states.
    private static let stateTerms: [(keyword: String, title: String, systemImage: String)] = [
        ("due", Tr.browsingSidebarDueToday, "calendar"),
    ]

    /// The rows whose names match `word`, by kind; every kind's first rows
    /// when `word` is empty. A name that starts with the word comes first,
    /// then one with a part that does, then one that has it anywhere; after
    /// `is:`, only a name or keyword that starts with it. `typed` is the
    /// whole text, so a keyword already in it isn't offered again.
    static func groups(
        for word: String, in sidebar: [SidebarSection], excluding: Set<SidebarItem.ID>, typed: String = ""
    ) -> [(title: String, items: [(Pick, String)])] {
        var word = Substring(word)
        if word.hasPrefix("\"") { word = word.dropFirst() }
        var only: SidebarKind?
        for (prefix, kind) in prefixes where word.lowercased().hasPrefix(prefix) {
            only = kind
            word = word.dropFirst(prefix.count)
        }
        let needle = String(word)
        let anchoredOnly = only == .cardStateRoot
        var groups: [(title: String, items: [(Pick, String)])] = []
        for (kind, limit) in kinds where only == nil || only == kind {
            guard let section = sidebar.first(where: { $0.kind == kind }) else { continue }
            var matches: [(rank: Int, pick: Pick, title: String)] = []
            func visit(_ nodes: [SidebarNode]) {
                for node in nodes {
                    let name = node.item.fullName.map { $0.replacing("::", with: " › ") } ?? node.title
                    var keyword: String?
                    if case .cardState(let state) = node.item { keyword = stateKeywords[state] }
                    if !excluding.contains(node.id),
                        let rank = rank(name, leaf: node.title, keyword: keyword, needle),
                        !anchoredOnly || rank == 0
                    {
                        matches.append((rank, .item(node.item), node.title))
                    }
                    visit(node.children ?? [])
                }
            }
            visit(section.nodes)
            if kind == .cardStateRoot {
                for term in stateTerms where !SearchQuery.terms(typed.lowercased()).dropLast().contains("is:\(term.keyword)") {
                    if let rank = rank(term.title, leaf: term.title, keyword: term.keyword, needle),
                        !anchoredOnly || rank == 0
                    {
                        matches.append((rank, .term("is:\(term.keyword)", systemImage: term.systemImage), term.title))
                    }
                }
            }
            let best = matches.enumerated()
                .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
                .prefix(only == nil ? limit : 12)
                .map { ($0.element.pick, $0.element.title) }
            if !best.isEmpty { groups.append((section.title, best)) }
        }
        return groups
    }

    private static func rank(_ name: String, leaf: String, keyword: String? = nil, _ needle: String) -> Int? {
        if needle.isEmpty { return 0 }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
        if leaf.range(of: needle, options: options) != nil { return 0 }
        if let keyword, keyword.range(of: needle, options: options) != nil { return 0 }
        if name.components(separatedBy: " › ").contains(where: { $0.range(of: needle, options: options) != nil }) {
            return 1
        }
        return name.localizedStandardContains(needle) ? 2 : nil
    }
}

private struct SearchSuggestionList: View {
    let suggestions: SearchSuggestions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.groups.enumerated()), id: \.offset) { index, group in
                if let title = group.title {
                    Text(title.uppercased())
                        .font(Theme.Fonts.eyebrow)
                        .tracking(Theme.Fonts.eyebrowTracking)
                        .foregroundStyle(Theme.Palette.secondary)
                        .padding(.horizontal, Theme.Tags.chipPadding)
                        .padding(.top, index == 0 ? Theme.Spacing.xSmall : Theme.Spacing.small)
                        .padding(.bottom, Theme.Spacing.xxSmall)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(group.rows) { row($0) }
            }
        }
        .padding(Theme.Tags.popupPadding)
        .frame(width: suggestions.width, alignment: .leading)
        .glassEffect(
            .regular.tint(Theme.Palette.canvas.opacity(Theme.Tags.tintOpacity)),
            in: RoundedRectangle(cornerRadius: Theme.Tags.popupRadius))
    }

    private func row(_ row: SearchSuggestions.Row) -> some View {
        let highlighted = suggestions.highlighted == row.id
        return HStack(spacing: Theme.Spacing.small) {
            Image(systemName: row.systemImage)
                .font(Theme.Tags.rowSymbol)
                .foregroundStyle(highlighted ? Color.white : row.item?.tint ?? Theme.Palette.secondary)
                .frame(width: Theme.Browser.sidebarIconSlot)
            Text(row.title)
                .font(Theme.Tags.rowFont)
                .foregroundStyle(highlighted ? Color.white : Theme.Palette.text)
                .lineLimit(1)
                .layoutPriority(1)
            if let detail = row.detail {
                Text(detail)
                    .font(Theme.Tags.rowFont)
                    .foregroundStyle(highlighted ? Color.white.opacity(0.75) : Theme.Palette.tertiary)
                    .lineLimit(1)
                    // The parents lose their start first, as in Quick Find.
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, Theme.Tags.chipPadding)
        .frame(maxWidth: .infinity, minHeight: Theme.Tags.rowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Tags.rowRadius)
                .fill(highlighted ? Theme.Palette.accent : .clear))
        .contentShape(.rect)
        .onHover { if $0 { suggestions.highlighted = row.id } }
        .onTapGesture { suggestions.pick(row: row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

extension SidebarItem {
    /// What a chip is, in its help tag and for VoiceOver.
    var kindName: String {
        switch self {
        case .savedSearch: "Saved Search"
        case .cardState: "Card State"
        case .flag: "Flag"
        case .deck: "Deck"
        case .notetype: "Note Type"
        case .tag: "Tag"
        }
    }
}

/// What the search field shows and searches: the Browser's table, or a
/// filtered deck's search in its sheet.
protocol SearchFieldSource: AnyObject {
    /// The rows a chip or a suggestion can stand for.
    var sidebar: [SidebarSection] { get }
    /// The search as last applied, which the field splits into chips and text.
    var searchText: String { get }
    /// Whether Return searches. In a sheet it falls through to the default
    /// button instead, and the typing counts as it goes (`edited`).
    var searchesOnReturn: Bool { get }
    func search(chips: [String], adding item: SidebarItem?, text: String)
    /// The chips and the text as typed, before any search.
    func edited(chips: [String], text: String)
}

extension SearchFieldSource {
    var searchesOnReturn: Bool { true }
    func edited(chips: [String], text: String) {}
    func search(chips: [String], text: String) { search(chips: chips, adding: nil, text: text) }
}

extension BrowserModel: SearchFieldSource {}
