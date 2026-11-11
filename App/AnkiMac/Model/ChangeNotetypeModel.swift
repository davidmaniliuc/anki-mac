import AnkiKit
import Observation

/// What desktop's Change Note Type page (ts/routes/change-notetype) edits: for
/// each field and card type of the chosen note type, which of the notes'
/// current ones feeds it. Entries are indexes into the old note type's lists,
/// or `nothing`.
@MainActor
@Observable
final class ChangeNotetypeModel {
    static let nothing: Int32 = -1

    let noteIDs: [Int64]
    let notetypes: [NotetypeChoice]
    private let backend: AnkiBackend?
    private(set) var info: Anki_Notetypes_ChangeNotetypeInfo
    var fields: [Int32]
    /// Empty when changing to or from a cloze note type, whose cards the backend maps itself.
    var templates: [Int32]
    private(set) var newNotetypeID: Int64
    /// True while the mapping for a newly chosen note type loads; the old one no longer fits.
    private(set) var isLoading = false
    var errorMessage: String?
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(
        noteIDs: [Int64], notetypes: [NotetypeChoice], info: Anki_Notetypes_ChangeNotetypeInfo, backend: AnkiBackend?
    ) {
        self.noteIDs = noteIDs
        self.notetypes = notetypes
        self.backend = backend
        self.info = info
        fields = info.input.newFields
        templates = info.input.newTemplates
        newNotetypeID = info.input.newNotetypeID
    }

    var oldNotetypeName: String { info.oldNotetypeName }

    /// Whether saving would change nothing: the same note type, every field and card type kept in place.
    var isUnchanged: Bool {
        newNotetypeID == info.input.oldNotetypeID && fields == Array(0..<Int32(fields.count))
            && templates == Array(0..<Int32(templates.count))
    }

    func chooseNotetype(_ id: Int64) {
        guard id != newNotetypeID else { return }
        newNotetypeID = id
        loading?.cancel()
        guard let backend else { return }
        var request = Anki_Notetypes_GetChangeNotetypeInfoRequest()
        request.oldNotetypeID = info.input.oldNotetypeID
        request.newNotetypeID = id
        isLoading = true
        loading = Task {
            do {
                let loaded = try await backend.perform { [request] in try $0.getChangeNotetypeInfo(request) }
                guard !Task.isCancelled else { return }
                info = loaded
                fields = loaded.input.newFields
                templates = loaded.input.newTemplates
                isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? AnkiError)?.message ?? String(describing: error)
                isLoading = false
            }
        }
    }

    // A picker for a row the new note type no longer has still reads once while it's torn down.
    func field(_ index: Int) -> Int32 { fields.indices.contains(index) ? fields[index] : Self.nothing }
    func template(_ index: Int) -> Int32 { templates.indices.contains(index) ? templates[index] : Self.nothing }

    func setField(_ index: Int, to old: Int32) {
        guard fields.indices.contains(index) else { return }
        fields[index] = old
    }

    /// A card type can take its cards from one old card type only, unlike fields, which may be copied.
    func setTemplate(_ index: Int, to old: Int32) {
        guard templates.indices.contains(index) else { return }
        if old != Self.nothing {
            for other in templates.indices where templates[other] == old { templates[other] = Self.nothing }
        }
        templates[index] = old
    }

    /// The old fields no new field takes content from, which the change discards.
    var discardedFields: [String] { unused(info.oldFieldNames, fields) }

    /// The old card types no new one takes cards from, whose cards the change removes.
    var discardedTemplates: [String] { templates.isEmpty ? [] : unused(info.oldTemplateNames, templates) }

    private func unused(_ names: [String], _ map: [Int32]) -> [String] {
        names.indices.filter { !map.contains(Int32($0)) }.map { names[$0] }
    }

    var request: Anki_Notetypes_ChangeNotetypeRequest {
        var request = info.input
        request.noteIds = noteIDs
        request.newFields = fields
        request.newTemplates = templates
        return request
    }
}
