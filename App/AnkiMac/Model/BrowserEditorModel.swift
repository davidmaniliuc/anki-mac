import AnkiKit
import Foundation
import Observation

/// The browser's editor pane: the note of the one selected row, saved as
/// it's edited, as desktop's browser editor does.
@Observable
final class BrowserEditorModel {
    let editor: NoteEditorModel
    private(set) var noteID: Int64?
    var tags: [String] = [] {
        didSet { if tags != oldValue, noteID != nil { scheduleSave() } }
    }

    private let browser: BrowserModel
    private let backend: AnkiBackend
    private var note = Anki_Notes_Note()
    private var saveTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(browser: BrowserModel, backend: AnkiBackend, mediaFolder: URL?) {
        self.browser = browser
        self.backend = backend
        editor = NoteEditorModel(backend: backend, mediaFolder: mediaFolder)
        editor.onChange = { [weak self] in self?.scheduleSave() }
        var request = Anki_Config_GetConfigBoolRequest()
        request.key = .pasteStripsFormatting
        editor.pasteKeepsFormatting = !((try? backend.getConfigBool(request).val) ?? false)
    }

    /// Shows the selected row's note, or nothing when no row or several
    /// rows are selected. Pending edits to the previous note are saved first.
    func show(_ selection: BrowserModel.Selection?) {
        saveNow()
        loadGeneration += 1
        let generation = loadGeneration
        guard let selection, selection.ids.count == 1 else {
            clear()
            return
        }
        Task {
            do {
                let (note, notetype) = try await backend.perform { backend in
                    var noteID = Anki_Notes_NoteId()
                    noteID.nid = try BrowserModel.noteIDs(selection, backend: backend).first ?? 0
                    let note = try backend.getNote(noteID)
                    var notetypeID = Anki_Notetypes_NotetypeId()
                    notetypeID.ntid = note.notetypeID
                    return (note, try backend.getNotetype(notetypeID))
                }
                // A newer selection won while this one loaded.
                guard generation == loadGeneration else { return }
                guard note.id != noteID else { return }
                self.note = note
                noteID = note.id
                editor.load(notetype: notetype, values: note.fields, noteID: note.id, focus: false)
                tags = note.tags
            } catch {
                guard generation == loadGeneration else { return }
                clear()
            }
        }
    }

    private func clear() {
        noteID = nil
        editor.clear()
        tags = []
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: Theme.Browser.editorSaveDelay)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// Writes the note if anything changed. Untouched fields go back exactly
    /// as they were loaded, so only real edits change the note.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard noteID != nil else { return }
        var updated = note
        updated.fields = editor.values
        updated.tags = tags
        guard updated.fields != note.fields || updated.tags != note.tags else { return }
        note = updated
        browser.change { [updated] backend in
            var request = Anki_Notes_UpdateNotesRequest()
            request.notes = [updated]
            _ = try backend.updateNotes(request)
        }
    }

    func completeTags(_ prefix: String) -> [String] {
        var request = Anki_Tags_CompleteTagRequest()
        request.input = prefix
        request.matchLimit = UInt32(Theme.Browser.tagSuggestions)
        return (try? backend.completeTag(request).tags) ?? []
    }
}
