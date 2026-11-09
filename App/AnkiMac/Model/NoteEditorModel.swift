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
    let plainText: Bool
    let rightToLeft: Bool

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

    init(backend: AnkiBackend, mediaFolder: URL?) {
        self.backend = backend
        self.mediaFolder = mediaFolder
    }

    /// Shows a note type's fields with these values.
    func load(notetype: Anki_Notetypes_Notetype, values: [String], focus: Bool = true) {
        fields = notetype.fields.enumerated().map { index, field in
            let config = field.config
            let size = config.fontSize > 0 ? CGFloat(config.fontSize) : Theme.Editor.defaultFontSize
            let font = NSFont(name: config.fontName, size: size) ?? .systemFont(ofSize: size)
            return EditorField(
                name: field.name, index: index, html: index < values.count ? values[index] : "", font: font,
                plainText: config.plainText, rightToLeft: config.rtl, mediaFolder: mediaFolder)
        }
        focusRequest = focus ? 0 : nil
    }

    func clear() {
        fields = []
    }

    var values: [String] { fields.map(\.html) }

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
