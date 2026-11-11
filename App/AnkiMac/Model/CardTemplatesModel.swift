import AnkiKit
import Foundation
import Observation

/// Desktop's card layout editor (aqt/clayout.py): edits a copy of a note type's
/// templates and styling, previews the selected card from the edited copy, and
/// saves the lot at once.
@Observable
final class CardTemplatesModel {
    enum Editor: Hashable { case front, back, styling }

    let backend: AnkiBackend
    let manager: NotetypeManager
    let original: Anki_Notetypes_Notetype
    let useCount: UInt32
    var draft: Anki_Notetypes_Notetype
    var selected = 0 { didSet { scheduleRender() } }
    var editor = Editor.front
    var showsAnswer = false { didSet { scheduleRender() } }
    var fillEmpty = true { didSet { scheduleRender() } }
    var nightMode = false { didSet { scheduleRender() } }
    var mobileClass = false { didSet { scheduleRender() } }
    var errorMessage: String?
    /// The question or answer HTML for the preview, and the body class.
    private(set) var previewHTML = ""
    private(set) var previewIsAnswer = false
    private(set) var previewBodyClass = ""
    private(set) var previewVersion = 0
    private var note: Anki_Notes_Note?
    private var renderTask: Task<Void, Never>?

    init(manager: NotetypeManager, notetype: Anki_Notetypes_Notetype, useCount: UInt32) {
        self.manager = manager
        backend = manager.backend
        original = notetype
        self.useCount = useCount
        draft = notetype
    }

    var isEdited: Bool { draft != original }
    var isCloze: Bool { draft.config.kind == .cloze }
    var template: Anki_Notetypes_Notetype.Template? {
        draft.templates.indices.contains(selected) ? draft.templates[selected] : nil
    }

    // MARK: Text being edited

    /// The text of the editor tab in view.
    var text: String {
        get {
            guard let template else { return "" }
            switch editor {
            case .front: return template.config.qFormat
            case .back: return template.config.aFormat
            case .styling: return draft.config.css
            }
        }
        set {
            guard draft.templates.indices.contains(selected) else { return }
            switch editor {
            case .front: draft.templates[selected].config.qFormat = newValue
            case .back: draft.templates[selected].config.aFormat = newValue
            case .styling: draft.config.css = newValue
            }
            scheduleRender()
        }
    }

    /// Desktop's `_addField`: a div with the chosen font around the field.
    func insertField(_ name: String) {
        text += "\n<div style='font-family: \"Arial\"; font-size: 20px;'>{{\(name)}}</div>\n"
    }

    // MARK: Card types

    func cardTypeName(_ index: Int) -> String {
        guard draft.templates.indices.contains(index) else { return "" }
        return draft.templates[index].name
    }

    func addCardType() {
        guard let current = template else { return }
        let names = Set(draft.templates.map(\.name))
        var number = draft.templates.count + 1
        while names.contains(Tr.cardTemplatesCard(val: String(number))) { number += 1 }
        var added = Anki_Notetypes_Notetype.Template()
        added.name = Tr.cardTemplatesCard(val: String(number))
        added.config.qFormat = current.config.qFormat
        added.config.aFormat = current.config.aFormat
        draft.templates.append(added)
        selected = draft.templates.count - 1
    }

    func removeCardType() {
        guard draft.templates.count > 1, draft.templates.indices.contains(selected) else { return }
        draft.templates.remove(at: selected)
        selected = min(selected, draft.templates.count - 1)
    }

    func rename(to name: String) {
        let clean = name.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, draft.templates.indices.contains(selected) else { return }
        draft.templates[selected].name = clean
    }

    func reposition(to position: Int) {
        guard (1...draft.templates.count).contains(position), position - 1 != selected else { return }
        let moved = draft.templates.remove(at: selected)
        draft.templates.insert(moved, at: position - 1)
        selected = position - 1
    }

    /// Desktop's Flip: the back becomes the front and the front is put after
    /// the line on the back. False when the back has no `<hr id=answer>`.
    func flip() -> Bool {
        guard let current = template,
              let match = current.config.aFormat.firstMatch(of: /(?s)(.+)<hr id=answer>(.+)/)
        else { return false }
        draft.templates[selected].config.aFormat = "{{FrontSide}}\n\n<hr id=answer>\n\n\(current.config.qFormat)"
        draft.templates[selected].config.qFormat = String(match.2).trimmingCharacters(in: .whitespacesAndNewlines)
        return true
    }

    /// How many cards use the selected card type.
    func cardCount(ofTemplate index: Int) async -> Int {
        guard draft.templates.indices.contains(index), draft.templates[index].hasOrd else { return 0 }
        let ntid = original.id
        let ord = Int(draft.templates[index].ord.val)
        let backend = backend
        return (try? await backend.perform { backend in
            let query: [String: Any] = [
                "kind": "query", "first_row_only": true, "args": [ntid, ord],
                "sql": "select count() from cards where nid in (select id from notes where mid = ?) and ord = ?",
            ]
            let reply = try backend.dbCommand(try JSONSerialization.data(withJSONObject: query))
            return ((try JSONSerialization.jsonObject(with: reply) as? [[Any]])?.first?.first as? Int) ?? 0
        }) ?? 0
    }

    func deckNames() async -> [(id: Int64, name: String)] {
        let backend = backend
        return (try? await backend.perform { backend in
            var request = Anki_Decks_GetDeckNamesRequest()
            request.skipEmptyDefault = true
            return try backend.getDeckNames(request).entries.map { (id: $0.id, name: $0.name) }
        }) ?? []
    }

    /// Desktop's Restore to Default, for note types that remember their stock kind.
    func restoreToDefault() async -> Bool {
        let ntid = original.id
        let backend = backend
        do {
            _ = try await backend.perform { backend in
                var request = Anki_Notetypes_RestoreNotetypeToStockRequest()
                request.notetypeID.ntid = ntid
                return try backend.restoreNotetypeToStock(request)
            }
            await manager.refresh(select: ntid)
            manager.onChange()
            return true
        } catch {
            errorMessage = "\(error)"
            return false
        }
    }

    // MARK: Saving

    func save() async -> Bool { await manager.confirmAndSave(old: original, new: draft) }

    // MARK: Preview

    /// The note the preview shows: the first of this type if there is one,
    /// otherwise an empty one (desktop fills its fields with their names).
    func loadSampleNote() async {
        let ntid = original.id
        let backend = backend
        let loaded = try? await backend.perform { backend -> Anki_Notes_Note in
            var search = Anki_Search_SearchRequest()
            search.search = "mid:\(ntid)"
            if let first = try backend.searchNotes(search).ids.first {
                var id = Anki_Notes_NoteId()
                id.nid = first
                return try backend.getNote(id)
            }
            var request = Anki_Notetypes_NotetypeId()
            request.ntid = ntid
            return try backend.newNote(request)
        }
        note = loaded
        scheduleRender(immediately: true)
    }

    func scheduleRender(immediately: Bool = false) {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: Theme.Notetypes.previewDelay) }
            guard !Task.isCancelled else { return }
            await self?.render()
        }
    }

    private func render() async {
        guard var note, let template else { return }
        let draft = draft
        let answer = showsAnswer
        let fill = fillEmpty
        let isEmpty = note.fields.allSatisfy(\.isEmpty)
        if isEmpty, draft.config.kind == .cloze, !note.fields.isEmpty {
            note.fields[0] = Tr.cardTemplatesSampleCloze
        }
        let sample = note
        let ord = UInt32(draft.config.kind == .cloze ? 0 : selected)
        let backend = backend
        do {
            let html = try await backend.perform { backend -> String in
                var request = Anki_CardRendering_RenderUncommittedCardRequest()
                request.note = sample
                request.cardOrd = ord
                request.template = template
                request.fillEmpty = fill
                let rendered = try backend.renderUncommittedCard(request)
                let nodes = answer ? rendered.answerNodes : rendered.questionNodes
                var extract = Anki_CardRendering_ExtractAvTagsRequest()
                extract.text = nodes.map(\.text).joined()
                var encode = Anki_Generic_String()
                encode.val = try backend.extractAvTags(extract).text
                var text = try backend.encodeIriPaths(encode).val
                // The typing box, as desktop's `maybeTextInput`.
                if answer {
                    text.replace(/\[\[type:[^\]]+\]\]/, with: "")
                } else {
                    text.replace(/\[\[type:[^\]]+\]\]/, with: "<center><input type=text id=typeans style=\"width: 90%\"></center>")
                }
                // The edited styling, not the saved one.
                return "<style>\(draft.config.css)</style>\(text)"
            }
            previewHTML = html
            previewIsAnswer = answer
            previewBodyClass = "card card\(ord + 1)"
            previewVersion += 1
        } catch {
            previewHTML = "<pre>\(String(describing: error).replacingOccurrences(of: "<", with: "&lt;"))</pre>"
            previewIsAnswer = answer
            previewVersion += 1
        }
    }
}
