import AnkiKit
import Foundation
import Observation

/// The notes that share one value of the searched field.
nonisolated struct DuplicateGroup: Identifiable, Sendable {
    let value: String
    var noteIDs: [Int64]
    var id: String { value }
}

/// What desktop's Find Duplicates dialog (aqt/browser/find_duplicates.py)
/// does: the fields of every note type to pick from, an optional search to
/// narrow it, and the groups found, which can be tagged `duplicate`.
@Observable
final class FindDuplicatesModel {
    private(set) var fields: [String] = []
    var field = ""
    var filter = ""
    /// Nil until the first search.
    private(set) var groups: [DuplicateGroup]?
    private(set) var isSearching = false
    private(set) var error: String?

    @ObservationIgnored private let browser: BrowserModel
    @ObservationIgnored private let showInBrowser: (String) -> Void
    /// The field last searched, kept for the next time the window opens.
    @ObservationIgnored private static var lastField = ""

    init(browser: BrowserModel, showInBrowser: @escaping (String) -> Void) {
        self.browser = browser
        self.showInBrowser = showInBrowser
    }

    var noteCount: Int { groups?.reduce(0) { $0 + $1.noteIDs.count } ?? 0 }

    /// Field names across all note types, sorted without regard to case.
    func loadFields() {
        guard let backend = browser.collection.backend else { return }
        Task {
            guard let names = try? await backend.perform({ try Self.fieldNames(backend: $0) }) else { return }
            fields = names
            if !names.contains(field) {
                field = names.contains(Self.lastField) ? Self.lastField : (names.first ?? "")
            }
        }
    }

    func find() {
        guard !field.isEmpty, !isSearching, let backend = browser.collection.backend else { return }
        Self.lastField = field
        isSearching = true
        let (field, filter) = (field, filter)
        Task {
            defer { isSearching = false }
            do {
                groups = try await backend.perform { try Self.findDuplicates(field: field, filter: filter, backend: $0) }
                error = nil
            } catch {
                self.error = (error as? AnkiError)?.message ?? String(describing: error)
            }
        }
    }

    func show(_ group: DuplicateGroup) {
        showInBrowser("nid:" + group.noteIDs.map(String.init).joined(separator: ","))
    }

    func tagDuplicates() {
        let noteIDs = Array(Set((groups ?? []).flatMap(\.noteIDs)))
        guard !noteIDs.isEmpty else { return }
        browser.change(searchAgain: true) { backend in
            var request = Anki_Tags_NoteIdsAndTagsRequest()
            request.noteIds = noteIDs
            request.tags = Tr.browsingDuplicate
            _ = try backend.addNoteTags(request)
        }
    }

    // MARK: Backend

    private nonisolated static func fieldNames(backend: AnkiBackend) throws -> [String] {
        var names: Set<String> = []
        for notetype in try backend.getNotetypeNames().entries {
            var id = Anki_Notetypes_NotetypeId()
            id.ntid = notetype.id
            names.formUnion(try backend.getFieldNames(id).vals)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Pylib's `find_dupes`: the notes matching the filter that have the
    /// field, grouped by its value with markup removed (media names kept).
    /// Empty values never count, and groups come in the order each reached
    /// two notes.
    private nonisolated static func findDuplicates(
        field: String, filter: String, backend: AnkiBackend
    ) throws -> [DuplicateGroup] {
        var filterNode = Anki_Search_SearchNode()
        filterNode.parsableText = filter
        var fieldNode = Anki_Search_SearchNode()
        fieldNode.fieldName = field
        var node = Anki_Search_SearchNode()
        node.group.nodes = [filterNode, fieldNode]
        var request = Anki_Search_SearchRequest()
        request.search = try backend.buildSearchString(node).val
        request.order.none = Anki_Generic_Empty()
        let noteIDs = try backend.searchNotes(request).ids
        guard !noteIDs.isEmpty else { return [] }

        let query: [String: Any] = [
            "kind": "query", "args": [], "first_row_only": false,
            "sql": "select id, mid, flds from notes where id in (\(noteIDs.map(String.init).joined(separator: ",")))",
        ]
        let reply = try backend.dbCommand(try JSONSerialization.data(withJSONObject: query))
        let rows = (try JSONSerialization.jsonObject(with: reply) as? [[Any]]) ?? []

        var fieldIndex: [Int64: Int] = [:]
        var groups: [DuplicateGroup] = []
        var seen: [String: Int] = [:]
        var firsts: [String: Int64] = [:]
        for row in rows {
            guard row.count == 3, let id = (row[0] as? NSNumber)?.int64Value,
                let mid = (row[1] as? NSNumber)?.int64Value, let flds = row[2] as? String
            else { continue }
            if fieldIndex[mid] == nil {
                var ntid = Anki_Notetypes_NotetypeId()
                ntid.ntid = mid
                fieldIndex[mid] = try backend.getFieldNames(ntid).vals
                    .firstIndex { $0.compare(field, options: .caseInsensitive) == .orderedSame } ?? -1
            }
            let parts = flds.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            guard let index = fieldIndex[mid], parts.indices.contains(index) else { continue }
            var strip = Anki_CardRendering_StripHtmlRequest()
            strip.text = String(parts[index])
            strip.mode = .preserveMediaFilenames
            let value = try backend.stripHtml(strip).val
            if value.isEmpty { continue }
            if let at = seen[value] {
                groups[at].noteIDs.append(id)
            } else if let first = firsts[value] {
                seen[value] = groups.count
                groups.append(DuplicateGroup(value: value, noteIDs: [first, id]))
            } else {
                firsts[value] = id
            }
        }
        return groups
    }
}
