import AnkiKit
import AppKit
import Observation

/// What desktop's Manage Note Types window (aqt/models.py) does: the list of
/// note types with their use counts, and add, clone, rename, delete and the
/// LaTeX options. The Fields and Card Types editors save through `save`.
@Observable
final class NotetypeManager {
    struct Entry: Identifiable, Sendable {
        let id: Int64
        let name: String
        let useCount: UInt32
    }

    /// The stock note types the Add list offers, in desktop's order.
    enum Stock: CaseIterable {
        case basic, basicAndReversed, basicOptionalReversed, basicTyping, cloze, imageOcclusion

        var name: String {
            switch self {
            case .basic: Tr.notetypesBasicName
            case .basicAndReversed: Tr.notetypesBasicReversedName
            case .basicOptionalReversed: Tr.notetypesBasicOptionalReversedName
            case .basicTyping: Tr.notetypesBasicTypeAnswerName
            case .cloze: Tr.notetypesClozeName
            case .imageOcclusion: Tr.notetypesImageOcclusionName
            }
        }

        var kind: Anki_Notetypes_StockNotetype.Kind {
            switch self {
            case .basic: .basic
            case .basicAndReversed: .basicAndReversed
            case .basicOptionalReversed: .basicOptionalReversed
            case .basicTyping: .basicTyping
            case .cloze: .cloze
            case .imageOcclusion: .imageOcclusion
            }
        }
    }

    let backend: AnkiBackend
    private(set) var entries: [Entry] = []
    var selectedID: Int64?
    var failure: ActionFailure?
    /// Called after anything that may change what the main window shows
    /// (new cards from a template, deleted notes).
    var onChange: () -> Void = {}

    init(backend: AnkiBackend) { self.backend = backend }

    var selected: Entry? { entries.first { $0.id == selectedID } }

    func refresh(select id: Int64? = nil) async {
        do {
            let loaded = try await backend.perform { backend in
                try backend.getNotetypeNamesAndCounts().entries
                    .map { Entry(id: $0.id, name: $0.name, useCount: $0.useCount) }
            }
            entries = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if let id, entries.contains(where: { $0.id == id }) {
                selectedID = id
            } else if !entries.contains(where: { $0.id == selectedID }) {
                selectedID = entries.first?.id
            }
        } catch { failure = ActionFailure("Couldn’t load the note types", error: error) }
    }

    func notetype(_ id: Int64) async throws -> Anki_Notetypes_Notetype {
        try await backend.perform { backend in
            var request = Anki_Notetypes_NotetypeId()
            request.ntid = id
            return try backend.getNotetype(request)
        }
    }

    /// Writes a changed note type; the backend works out what to rewrite from
    /// the fields' and templates' original positions. Returns false on error.
    @discardableResult
    /// Saves, showing a failure in this window's alert. `old` is the note
    /// type as the editor opened it, so a change made since in another
    /// window isn't overwritten.
    func save(_ value: Anki_Notetypes_Notetype, editedFrom old: Anki_Notetypes_Notetype? = nil) async -> Bool {
        do {
            try await write(value, editedFrom: old)
            return true
        } catch {
            failure = ActionFailure("Couldn’t save the note type", error: error)
            return false
        }
    }

    /// Saves an edit from the Fields or Cards editor, first asking, as desktop
    /// does, when it adds, removes or reorders fields or card types (or moves
    /// the sort field) and so forces a full upload at the next sync. False
    /// when that is declined; a failure is thrown, for the editor to show.
    func confirmAndSave(old: Anki_Notetypes_Notetype, new: Anki_Notetypes_Notetype) async throws -> Bool {
        let schemaChange = new.fields.map { $0.hasOrd ? Int($0.ord.val) : -1 } != Array(0..<old.fields.count)
            || new.templates.map { $0.hasOrd ? Int($0.ord.val) : -1 } != Array(0..<old.templates.count)
            || new.config.sortFieldIdx != old.config.sortFieldIdx
        if schemaChange, !(await NotetypeAlerts.confirmSchemaChange(backend)) { return false }
        try await write(new, editedFrom: old)
        return true
    }

    /// The Fields sheet, Card Types and Options each edit a copy of the
    /// note type and write it whole, so one saved after another would undo
    /// the other's change: a copy older than the collection's is refused.
    private func write(_ value: Anki_Notetypes_Notetype, editedFrom old: Anki_Notetypes_Notetype?) async throws {
        if let old, try await notetype(old.id).mtimeSecs != old.mtimeSecs { throw ChangedElsewhere() }
        _ = try await backend.perform { try $0.updateNotetype(value) }
        await refresh(select: value.id)
        onChange()
    }

    struct ChangedElsewhere: LocalizedError {
        var errorDescription: String? {
            "The note type was changed in another window since this one opened. Close this one and open it again to make your changes."
        }
    }

    func rename(_ id: Int64, to name: String) async {
        do {
            var value = try await notetype(id)
            value.name = name
            await save(value)
        } catch { failure = ActionFailure("Couldn’t rename the note type", error: error) }
    }

    func remove(_ id: Int64) async {
        do {
            try await backend.perform { backend in
                var request = Anki_Notetypes_NotetypeId()
                request.ntid = id
                _ = try backend.removeNotetype(request)
            }
            selectedID = nil
            await refresh()
            onChange()
        } catch { failure = ActionFailure("Couldn’t delete the note type", error: error) }
    }

    /// The name a new note type of this kind starts with.
    func defaultName(cloning id: Int64) -> String {
        Tr.notetypesCopy(val: entries.first { $0.id == id }?.name ?? "")
    }

    func add(_ stock: Stock, name: String) async {
        do {
            let kind = stock.kind
            let id = try await backend.perform { backend -> Int64 in
                if kind == .imageOcclusion {
                    // Desktop's Image Occlusion has a fixed name and no prompt.
                    _ = try backend.addImageOcclusionNotetype()
                    var request = Anki_Generic_String()
                    request.val = Tr.notetypesImageOcclusionName
                    return try backend.getNotetypeIdByName(request).ntid
                }
                var request = Anki_Notetypes_StockNotetype()
                request.kind = kind
                var json = try JSONSerialization.jsonObject(with: backend.getStockNotetypeLegacy(request).json) as? [String: Any] ?? [:]
                json["name"] = name
                var add = Anki_Generic_Json()
                add.json = try JSONSerialization.data(withJSONObject: json)
                return try backend.addNotetypeLegacy(add).id
            }
            await refresh(select: id)
        } catch { failure = ActionFailure("Couldn’t add the note type", error: error) }
    }

    func clone(_ id: Int64, name: String) async {
        do {
            var copy = try await notetype(id)
            copy.id = 0
            copy.name = name
            // A new note type has no history for the backend to reconcile.
            for index in copy.fields.indices { copy.fields[index].clearOrd() }
            for index in copy.templates.indices { copy.templates[index].clearOrd() }
            let value = copy
            let newID = try await backend.perform { try $0.addNotetype(value).id }
            await refresh(select: newID)
        } catch { failure = ActionFailure("Couldn’t clone the note type", error: error) }
    }

}

extension AnkiBackend {
    /// Whether the collection already needs a full upload at the next sync,
    /// so another schema change costs nothing more (desktop's `schema_changed`).
    nonisolated func schemaAlreadyChanged() -> Bool {
        let query: [String: Any] = ["kind": "query", "sql": "select scm > ls from col", "args": [], "first_row_only": true]
        guard let reply = try? dbCommand(try JSONSerialization.data(withJSONObject: query)),
            let row = (try? JSONSerialization.jsonObject(with: reply) as? [[Any]])?.first
        else { return false }
        return (row.first as? Int ?? 0) != 0
    }

    /// Desktop's `set_schema_modified`, so the next sync is a one-way one.
    nonisolated func setSchemaModified() throws {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let query: [String: Any] = ["kind": "query", "sql": "update col set scm=?", "args": [now], "first_row_only": false]
        _ = try dbCommand(try JSONSerialization.data(withJSONObject: query))
    }
}
