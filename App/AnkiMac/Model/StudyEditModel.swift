import AnkiKit
import Foundation
import Observation

/// The note of the card on screen, open in the editor sheet. Nothing is
/// written until the sheet is saved, so Cancel leaves the note alone.
@Observable
final class StudyEditModel: Identifiable {
    let editor: NoteEditorModel
    var tags: [String] = []

    private let backend: AnkiBackend
    private var note = Anki_Notes_Note()

    init(backend: AnkiBackend, mediaFolder: URL?) {
        self.backend = backend
        editor = NoteEditorModel(backend: backend, mediaFolder: mediaFolder)
        var request = Anki_Config_GetConfigBoolRequest()
        request.key = .pasteStripsFormatting
        editor.pasteKeepsFormatting = !((try? backend.getConfigBool(request).val) ?? false)
    }

    /// False when the note can't be read, in which case there is nothing to show.
    func load(noteID: Int64) async -> Bool {
        do {
            let (note, notetype) = try await backend.perform { backend in
                var id = Anki_Notes_NoteId()
                id.nid = noteID
                let note = try backend.getNote(id)
                var notetypeID = Anki_Notetypes_NotetypeId()
                notetypeID.ntid = note.notetypeID
                return (note, try backend.getNotetype(notetypeID))
            }
            self.note = note
            editor.load(notetype: notetype, values: note.fields)
            tags = note.tags
            return true
        } catch {
            return false
        }
    }

    /// The note with the editor's fields and tags as they stand.
    var currentNote: Anki_Notes_Note {
        var current = note
        current.fields = editor.values
        current.tags = tags
        return current
    }

    /// The note with the editor's fields and tags; nil when nothing changed.
    func changedNote() -> Anki_Notes_Note? {
        let updated = currentNote
        return updated.fields != note.fields || updated.tags != note.tags ? updated : nil
    }

    func completeTags(_ prefix: String) -> [String] {
        var request = Anki_Tags_CompleteTagRequest()
        request.input = prefix
        request.matchLimit = UInt32(Theme.Browser.tagSuggestions)
        return (try? backend.completeTag(request).tags) ?? []
    }
}
