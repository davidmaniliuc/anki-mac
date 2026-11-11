import AnkiKit
import AppKit
import CryptoKit
import FieldEditor
import Observation

/// One field in the editor: its HTML as loaded, the editable document
/// built from it, and whether the user changed it. A field the user didn't
/// touch is saved exactly as it was loaded.
@Observable
final class EditorField: Identifiable {
    let id = UUID()
    let name: String
    let index: Int
    private(set) var document: FieldDocument
    /// The text view's storage, kept here so the field survives the view
    /// being rebuilt.
    let storage: NSTextStorage
    private(set) var touched = false
    /// Shown as its HTML source instead of formatted.
    private(set) var showingSource = false
    var source = ""
    let font: NSFont
    /// Swaps in rendered MathJax as it arrives.
    @ObservationIgnored private var mathTask: Task<Void, Never>?
    let plainText: Bool
    let rightToLeft: Bool
    /// Only the label shows, as desktop's collapsed field.
    var collapsed = false

    init(name: String, index: Int, html: String, font: NSFont, plainText: Bool, rightToLeft: Bool, mediaFolder: URL?) {
        self.name = name
        self.index = index
        self.font = font
        self.plainText = plainText
        self.rightToLeft = rightToLeft
        let document = FieldDocument(html: html, style: Theme.Editor.fieldStyle(font: font), mediaFolder: mediaFolder)
        self.document = document
        storage = NSTextStorage(attributedString: document.text)
        showingSource = plainText
        if plainText { source = html }
        mathTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: MathRenderer.didRender) {
                guard let self else { return }
                document.refreshMath(in: storage)
            }
        }
    }

    deinit {
        mathTask?.cancel()
    }

    /// The field's HTML now.
    var html: String {
        showingSource ? source : documentHTML
    }

    private var documentHTML: String {
        touched ? document.html(from: storage) : document.html
    }

    func markTouched() {
        touched = true
    }

    /// Replaces the whole field, as when a new note starts.
    func load(_ html: String, mediaFolder: URL?) {
        document = FieldDocument(html: html, style: Theme.Editor.fieldStyle(font: font), mediaFolder: mediaFolder)
        storage.setAttributedString(document.text)
        source = html
        touched = false
    }

    /// Switches between formatted text and HTML source. Coming back from
    /// source rebuilds the field only if the HTML changed.
    func toggleSource(mediaFolder: URL?) {
        guard !plainText else { return }
        if showingSource {
            if source != documentHTML {
                document = FieldDocument(html: source, style: Theme.Editor.fieldStyle(font: font), mediaFolder: mediaFolder)
                storage.setAttributedString(document.text)
                touched = true
            }
            showingSource = false
        } else {
            source = html
            showingSource = true
        }
    }

    func setSource(_ text: String) {
        guard text != source else { return }
        source = text
        touched = true
    }
}

/// The fields of one note being edited, shared by Add Cards and the
/// browser's editor pane.
@Observable
final class NoteEditorModel {
    private(set) var fields: [EditorField] = []
    /// Desktop's mask editor, for an image occlusion note. It owns the
    /// occlusion and image fields, which the field list leaves out.
    private(set) var occlusion: ImageOcclusionEditor?
    let mediaFolder: URL?
    private let backend: AnkiBackend
    /// Called after every edit, so the owner can save or check the note.
    var onChange: (() -> Void)?
    /// The collection's "paste strips formatting", inverted; Shift flips it.
    var pasteKeepsFormatting = true
    /// The field to focus once it's on screen.
    var focusRequest: Int?
    /// The field the format bar acts on: the last one focused, so the bar
    /// works even while its window isn't key.
    @ObservationIgnored weak var focusedView: NSView?
    /// Which fields the user collapsed, per note type, for as long as this
    /// editor is open, as desktop's session options.
    @ObservationIgnored private var collapsedByNotetype: [Int64: [Bool]] = [:]
    @ObservationIgnored private var notetypeID: Int64 = 0

    init(backend: AnkiBackend, mediaFolder: URL?) {
        self.backend = backend
        self.mediaFolder = mediaFolder
    }

    /// Shows a note type's fields with these values, and the mask editor
    /// when `occlusionSetup` read one for the note.
    func load(
        notetype: Anki_Notetypes_Notetype, values: [String], occlusion setup: OcclusionSetup?, focus: Bool = true
    ) {
        notetypeID = notetype.id
        let collapsed = collapsedByNotetype[notetype.id] ?? notetype.fields.map(\.config.collapsed)
        fields = notetype.fields.enumerated().map { index, field in
            let config = field.config
            let size = config.fontSize > 0 ? CGFloat(config.fontSize) : Theme.Editor.defaultFontSize
            let font = NSFont(name: config.fontName, size: size) ?? .systemFont(ofSize: size)
            let editorField = EditorField(
                name: field.name, index: index, html: index < values.count ? values[index] : "", font: font,
                plainText: config.plainText, rightToLeft: config.rtl, mediaFolder: mediaFolder)
            editorField.collapsed = index < collapsed.count && collapsed[index]
            return editorField
        }
        occlusion = setup.map { setup in
            let editor = ImageOcclusionEditor(setup) { [weak self] data, name in
                self?.addMedia(data, preferredName: name)
            }
            editor.onChange = { [weak self] in self?.edited() }
            return editor
        }
        let hidden = occlusion?.hiddenFields ?? []
        focusRequest = focus ? fields.first { !$0.collapsed && !hidden.contains($0.index) }?.index : nil
    }

    /// Reads what an image occlusion note's mask editor starts from; nil
    /// for other note types. `noteID` is the note being edited, nil for a
    /// new one. It calls the backend, so run it off the main actor.
    nonisolated static func occlusionSetup(
        notetype: Anki_Notetypes_Notetype, noteID: Int64?, backend: AnkiBackend
    ) -> OcclusionSetup? {
        guard notetype.config.originalStockKind == .imageOcclusion else { return nil }
        var fieldsRequest = Anki_ImageOcclusion_GetImageOcclusionFieldsRequest()
        fieldsRequest.notetypeID = notetype.id
        guard let fields = try? backend.getImageOcclusionFields(fieldsRequest).fields else { return nil }
        guard let noteID else { return OcclusionSetup(fields: fields, note: .new) }
        var request = Anki_ImageOcclusion_GetImageOcclusionNoteRequest()
        request.noteID = noteID
        do {
            switch try backend.getImageOcclusionNote(request).value {
            case .note(let note): return OcclusionSetup(fields: fields, note: .existing(note))
            case .error(let reason): return OcclusionSetup(fields: fields, note: .unreadable(reason))
            case nil: return OcclusionSetup(fields: fields, note: .unreadable(""))
            }
        } catch {
            return OcclusionSetup(fields: fields, note: .unreadable((error as? AnkiError)?.message ?? "\(error)"))
        }
    }

    /// Commits a label still being typed on the mask canvas, so saving the
    /// note keeps it.
    func commitPendingEdits() {
        occlusion?.canvas?.endTextEditing()
    }

    /// Collapses or expands a field; an expanded field takes focus.
    func toggleCollapsed(_ field: EditorField) {
        field.collapsed.toggle()
        collapsedByNotetype[notetypeID] = fields.map(\.collapsed)
        if !field.collapsed { focusRequest = field.index }
    }

    func clear() {
        fields = []
        occlusion = nil
    }

    var values: [String] { fields.map { occlusion?.value(forField: $0.index) ?? $0.html } }

    func edited() {
        onChange?()
    }

    /// Saves pasted or dropped data into the media folder under desktop's
    /// name for it, and returns the name the backend chose.
    func addMedia(_ data: Data, preferredName: String) -> String? {
        var request = Anki_Media_AddMediaFileRequest()
        request.desiredName = preferredName
        request.data = data
        return try? backend.addMediaFile(request).val
    }

    /// Copies a file into the media folder, as desktop's Attach does, and
    /// returns the name the backend chose.
    func addMedia(fromPath path: String) async throws -> String {
        var request = Anki_Media_AddMediaFromPathRequest()
        request.path = path
        let sent = request
        return try await backend.perform { try $0.addMediaFromPath(sent).val }
    }

    /// Downloads a pasted image or sound into the media folder, as
    /// desktop's paste does. Returns the file name, or the error to show.
    func addMedia(fromURL url: String) async -> Result<String, MediaDownloadError> {
        var request = Anki_Media_AddMediaFromUrlRequest()
        request.url = url
        let sent = request
        do {
            let response = try await backend.perform { try $0.addMediaFromUrl(sent) }
            if response.hasFilename { return .success(response.filename) }
            return .failure(MediaDownloadError(message: response.error))
        } catch {
            return .failure(MediaDownloadError(message: (error as? AnkiError)?.message ?? String(describing: error)))
        }
    }

    func addPastedImage(_ data: Data, ext: String) -> String? {
        let checksum = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return addMedia(data, preferredName: "paste-\(checksum).\(ext)")
    }

    /// Cloze numbers count across all the note's fields.
    var nextClozeNumber: Int {
        FieldDocument.nextClozeNumber(in: values)
    }

    var currentClozeNumber: Int {
        max(1, nextClozeNumber - 1)
    }
}

/// An image occlusion note's field indexes and its masks as the backend
/// read them, for the mask editor.
nonisolated struct OcclusionSetup: Sendable {
    enum Note: Sendable {
        case new
        case existing(Anki_ImageOcclusion_GetImageOcclusionNoteResponse.ImageOcclusionNote)
        /// The masks couldn't be read, for the backend's reason.
        case unreadable(String)
    }

    let fields: Anki_ImageOcclusion_ImageOcclusionFieldIndexes
    let note: Note
}

struct MediaDownloadError: Error {
    let message: String
}
