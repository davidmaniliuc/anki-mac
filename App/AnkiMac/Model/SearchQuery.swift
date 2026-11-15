import AnkiKit
import Foundation

/// A Browser search as its field shows it: the filters a sidebar row stands
/// for (a deck, a tag, a note type, a card state, a flag) as chips, and the
/// rest as it was typed; `deck:*`, every deck, shows as nothing. Only a search whose top level is terms joined by
/// AND splits, since those can be shown in any order; one with a top-level
/// OR, and a filter that names nothing in the sidebar (`deck:Spa*`), stay text.
nonisolated struct SearchQuery: Equatable {
    struct Chip: Equatable {
        let item: SidebarItem
        let title: String
        /// The term as the backend wrote it, searched again as it is.
        let raw: String
    }

    var chips: [Chip] = []
    var text = ""

    init(_ search: String, sidebar: [SidebarSection]) {
        let terms = Self.terms(search)
        guard !terms.contains(where: { $0.caseInsensitiveCompare("or") == .orderedSame }) else {
            text = search
            return
        }
        let index = SidebarIndex(sidebar)
        var words: [String] = []
        for term in terms where term.caseInsensitiveCompare("and") != .orderedSame {
            // Every deck filters nothing: the backend's form of an empty search.
            if term.caseInsensitiveCompare("deck:*") == .orderedSame { continue }
            if let item = index.item(for: term), !chips.contains(where: { $0.item == item }) {
                chips.append(Chip(item: item, title: index.title(of: item), raw: term))
            } else {
                words.append(term)
            }
        }
        text = words.joined(separator: " ")
    }

    /// The field's chips, as the backend wrote them, then a row picked from
    /// its suggestions and the text, joined by AND.
    static func node(chips: [String], adding item: SidebarItem? = nil, text: String) -> Anki_Search_SearchNode {
        var nodes = chips.map { raw in
            var node = Anki_Search_SearchNode()
            node.parsableText = raw
            return node
        }
        if let item { nodes.append(item.searchNode) }
        let text = text.replacing(/\s/, with: " ").trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            var node = Anki_Search_SearchNode()
            node.parsableText = text
            nodes.append(node)
        }
        var node = Anki_Search_SearchNode()
        if nodes.count > 1 {
            var group = Anki_Search_SearchNode.Group()
            group.nodes = nodes
            group.joiner = .and
            node.group = group
        } else {
            node = nodes.first ?? node
            if nodes.isEmpty { node.parsableText = "" }
        }
        return node
    }

    /// The top-level terms, split on spaces outside quotes and brackets.
    static func terms(_ search: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var depth = 0
        var quoted = false
        var escaped = false
        for character in search {
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted && character == "(" {
                depth += 1
            } else if !quoted && character == ")" {
                depth = max(0, depth - 1)
            } else if !quoted && depth == 0 && character.isWhitespace {
                if !current.isEmpty { terms.append(current) }
                current = ""
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { terms.append(current) }
        return terms
    }

    /// A search value as it reads, or nil when it is a pattern: an unescaped
    /// `*` or `_` matches any text, so it names no one deck or tag.
    static func literal(_ value: some StringProtocol) -> String? {
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "*" || character == "_" {
                return nil
            } else {
                result.append(character)
            }
        }
        return result
    }
}

/// The sidebar's rows by what a search term names them by.
private nonisolated struct SidebarIndex {
    private var decks: [String: SidebarItem] = [:]
    private var notetypes: [String: SidebarItem] = [:]
    private var tags: [String: SidebarItem] = [:]
    private var titles: [SidebarItem.ID: String] = [:]

    init(_ sidebar: [SidebarSection]) {
        func add(_ nodes: [SidebarNode]) {
            for node in nodes {
                titles[node.id] = node.title
                switch node.item {
                case .deck(_, let name): decks[name.lowercased()] = node.item
                case .notetype(_, let name): notetypes[name.lowercased()] = node.item
                case .tag(let name): tags[name.lowercased()] = node.item
                default: break
                }
                add(node.children ?? [])
            }
        }
        sidebar.forEach { add($0.nodes) }
    }

    func item(for term: String) -> SidebarItem? {
        var term = Substring(term)
        if term.count > 1, term.hasPrefix("\""), term.hasSuffix("\"") { term = term.dropFirst().dropLast() }
        guard let colon = term.firstIndex(of: ":") else { return nil }
        let key = term[..<colon].lowercased()
        let value = term[term.index(after: colon)...]
        switch key {
        case "deck", "tag", "note":
            guard let name = SearchQuery.literal(value)?.lowercased() else { return nil }
            return key == "deck" ? decks[name] : key == "tag" ? tags[name] : notetypes[name]
        case "is":
            let states: [String: Anki_Search_SearchNode.CardState] = [
                "new": .new, "learn": .learn, "review": .review, "suspended": .suspended, "buried": .buried,
            ]
            return states[value.lowercased()].map { .cardState($0) }
        case "flag":
            return Int(value).flatMap(CardFlag.init(rawValue:)).flatMap { CardFlag.assignable.contains($0) ? .flag($0) : nil }
        default:
            return nil
        }
    }

    /// A deck or tag by its whole path, as the main window writes one; the
    /// others by their row's name (a renamed flag by its new one).
    func title(of item: SidebarItem) -> String {
        switch item {
        case .deck(_, let name), .tag(let name): name.replacing("::", with: " › ")
        default: titles[item.id] ?? ""
        }
    }
}
