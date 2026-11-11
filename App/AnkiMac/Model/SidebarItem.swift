import AnkiKit
import Foundation

/// Something in the browser's sidebar. Each one stands for a search.
nonisolated enum SidebarItem: Hashable, Sendable {
    case savedSearch(name: String, search: String)
    case cardState(Anki_Search_SearchNode.CardState)
    case flag(CardFlag)
    /// Full names ("Spanish::Verbs"), as the search needs them.
    case deck(id: Int64, name: String)
    case notetype(id: Int64, name: String)
    case tag(String)

    var searchNode: Anki_Search_SearchNode {
        var node = Anki_Search_SearchNode()
        switch self {
        case .savedSearch(_, let search): node.parsableText = search
        case .cardState(let state): node.cardState = state
        case .flag(let flag): node.flag = Anki_Search_SearchNode.Flag(rawValue: flag.rawValue + 1) ?? .any
        case .deck(_, let name): node.deck = name
        case .notetype(_, let name): node.note = name
        case .tag(let name): node.tag = name
        }
        return node
    }

    var kind: SidebarKind {
        switch self {
        case .savedSearch: .savedSearch
        case .cardState: .cardState
        case .flag: .flag
        case .deck: .deck
        case .notetype: .notetype
        case .tag: .tag
        }
    }

    /// The name that renaming changes in the collection: the saved search's,
    /// or the deck or tag's full name.
    var fullName: String? {
        switch self {
        case .savedSearch(let name, _), .deck(_, let name), .tag(let name): name
        case .cardState, .flag, .notetype: nil
        }
    }

    /// The part of a deck or tag name above this one, with its trailing "::".
    var namePrefix: String {
        guard kind == .deck || kind == .tag, let name = fullName,
            let range = name.range(of: "::", options: .backwards)
        else { return "" }
        return String(name[..<range.upperBound])
    }

    var systemImage: String {
        switch self {
        case .savedSearch: "magnifyingglass"
        case .cardState(let state):
            switch state {
            case .new: "sparkles"
            case .learn: "arrow.trianglehead.2.clockwise"
            case .review: "checkmark.circle"
            case .suspended: "pause.circle"
            case .buried: "eye.slash"
            default: "rectangle.on.rectangle"
            }
        case .flag: "flag.fill"
        case .deck: "rectangle.stack"
        case .notetype: "doc.text"
        case .tag: "tag"
        }
    }
}

nonisolated struct SidebarNode: Identifiable, Hashable, Sendable {
    let item: SidebarItem
    let title: String
    /// nil for a leaf, so the list shows no disclosure triangle.
    let children: [SidebarNode]?

    var id: SidebarItem { item }
}

nonisolated struct SidebarSection: Identifiable, Equatable, Sendable {
    /// The header's own kind, for its context menu.
    let kind: SidebarKind
    let title: String
    let nodes: [SidebarNode]

    var id: String { title }

    /// Desktop's sidebar, minus the "Today" searches and note type templates.
    static func load(_ backend: AnkiBackend) throws -> [SidebarSection] {
        var sections: [SidebarSection] = []

        let saved = backend.configJSON("savedFilters", as: [String: String].self) ?? [:]
        sections.append(SidebarSection(
            kind: .savedSearchRoot, title: "Saved Searches",
            nodes: saved.keys.sorted(using: .localizedStandard).map { name in
                SidebarNode(item: .savedSearch(name: name, search: saved[name]!), title: name, children: nil)
            }))

        let states: [(Anki_Search_SearchNode.CardState, String)] = [
            (.new, "New"), (.learn, "Learning"), (.review, "Review"), (.suspended, "Suspended"), (.buried, "Buried"),
        ]
        sections.append(SidebarSection(
            kind: .cardStateRoot, title: "Card State",
            nodes: states.map { SidebarNode(item: .cardState($0.0), title: $0.1, children: nil) }))

        // Renamed flags keep their colour; the label comes from the config.
        let labels = backend.configJSON("flagLabels", as: [String: String].self) ?? [:]
        sections.append(SidebarSection(
            kind: .flagRoot, title: "Flags",
            nodes: CardFlag.assignable.map { flag in
                let label = labels[String(flag.rawValue)].flatMap { $0.isEmpty ? nil : $0 } ?? flag.title
                return SidebarNode(item: .flag(flag), title: label, children: nil)
            }))

        var deckRequest = Anki_Decks_DeckTreeRequest()
        deckRequest.now = 0
        sections.append(SidebarSection(
            kind: .deckRoot, title: "Decks", nodes: decks(try backend.deckTree(deckRequest).children, parent: nil)))

        sections.append(SidebarSection(
            kind: .notetypeRoot, title: "Note Types",
            nodes: try backend.getNotetypeNamesAndCounts().entries.map {
                SidebarNode(item: .notetype(id: $0.id, name: $0.name), title: $0.name, children: nil)
            }))

        sections.append(SidebarSection(
            kind: .tagRoot, title: "Tags", nodes: tags(try backend.tagTree().children, parent: nil)))
        return sections
    }

    private static func decks(_ nodes: [Anki_Decks_DeckTreeNode], parent: String?) -> [SidebarNode] {
        nodes.map { node in
            let name = parent.map { "\($0)::\(node.name)" } ?? node.name
            let children = decks(node.children, parent: name)
            return SidebarNode(item: .deck(id: node.deckID, name: name), title: node.name, children: children.isEmpty ? nil : children)
        }
    }

    private static func tags(_ nodes: [Anki_Tags_TagTreeNode], parent: String?) -> [SidebarNode] {
        nodes.map { node in
            let name = parent.map { "\($0)::\(node.name)" } ?? node.name
            let children = tags(node.children, parent: name)
            return SidebarNode(item: .tag(name), title: node.name, children: children.isEmpty ? nil : children)
        }
    }
}
