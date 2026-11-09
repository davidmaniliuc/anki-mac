import AppKit
import FieldEditor
import SwiftUI
import UniformTypeIdentifiers

/// A field's formatted text. The Format menu's commands reach it through
/// the responder chain while it has focus.
final class FieldTextView: NSTextView {
    var field: EditorField!
    weak var editor: NoteEditorModel?
    private var pasteKeepsFormatting: Bool { editor?.pasteKeepsFormatting ?? true }

    private var document: FieldDocument { field.document }

    static func make() -> FieldTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let view = FieldTextView(frame: .zero, textContainer: container)
        view.isRichText = true
        view.allowsUndo = true
        view.importsGraphics = false
        view.usesFontPanel = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.drawsBackground = false
        view.textContainerInset = Theme.Editor.fieldInset
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        return view
    }

    /// Shows a field's storage: the text view's own storage is swapped for
    /// the field's, so edits land there directly.
    func show(_ field: EditorField) {
        guard self.field !== field else { return }
        self.field = field
        layoutManager?.replaceTextStorage(field.storage)
        baseWritingDirection = field.rightToLeft ? .rightToLeft : .natural
        typingAttributes = FieldDocument.cleanTypingAttributes(
            field.storage.length > 0 ? field.storage.attributes(at: field.storage.length - 1, effectiveRange: nil)
                : document.attributes([]))
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { editor?.focusedView = self }
        return became
    }

    // MARK: Editing rules

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Typing next to an image or a line break would otherwise extend it.
        typingAttributes = FieldDocument.cleanTypingAttributes(typingAttributes)
        if typingAttributes[.fieldStack] == nil {
            typingAttributes.merge(document.attributes([])) { current, _ in current }
        }
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: range, replacementString: replacementString) else { return false }
        if replacementString?.isEmpty ?? false, let storage = textStorage {
            document.prepareDeletion(of: range, in: storage)
        }
        return true
    }

    override func didChangeText() {
        if let storage = textStorage { document.finishEdit(storage) }
        super.didChangeText()
        invalidateIntrinsicContentSize()
        field.markTouched()
        editor?.edited()
    }

    /// Double-clicking a table or other chip opens the field's HTML.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let index = characterIndex(at: convert(event.locationInWindow, from: nil)),
            let storage = textStorage, storage.attribute(.fieldAtom, at: index, effectiveRange: nil) != nil,
            let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
            (storage.attribute(.fieldAtom, at: index, effectiveRange: nil) as? String)?.lowercased().hasPrefix("<img") == false,
            attachment.image != nil
        {
            toggleHTMLSource(nil)
            return
        }
        super.mouseDown(with: event)
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let location = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layoutManager.characterIndex(for: location, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        return index < (textStorage?.length ?? 0) ? index : nil
    }

    // MARK: Format menu

    @objc func toggleFieldFormat(_ sender: Any?) {
        guard let format = (sender as? FormatCommand)?.format else { return }
        apply(format)
    }

    func apply(_ format: InlineFormat) {
        let range = selectedRange()
        guard let storage = textStorage else { return }
        if range.length == 0 {
            typingAttributes = document.typingAttributes(typingAttributes, toggling: format)
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        document.toggle(format, in: storage, range: range)
        didChangeText()
    }

    @objc func removeFieldFormatting(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        document.removeFormatting(in: storage, range: range)
        didChangeText()
    }

    /// The format bar's colour buttons and F7: the selection takes the
    /// last colour picked.
    @objc func applyFieldColor(_ sender: Any?) {
        guard let kind = (sender as? ColorCommand)?.kind else { return }
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        let (red, green, blue) = EditorColors.components(EditorColors.shared.color(kind))
        document.setColor(kind, red: red, green: green, blue: blue, in: storage, range: range)
        didChangeText()
    }

    /// Cmd-Shift-C: the selection becomes the next cloze; with Option, it
    /// keeps the current number.
    @objc func insertCloze(_ sender: Any?) {
        wrapCloze(number: editor?.nextClozeNumber ?? 1)
    }

    @objc func insertClozeSameNumber(_ sender: Any?) {
        wrapCloze(number: editor?.currentClozeNumber ?? 1)
    }

    private func wrapCloze(number: Int) {
        let range = selectedRange()
        guard let storage = textStorage else { return }
        let selected = storage.attributedSubstring(from: range)
        let attributes = FieldDocument.cleanTypingAttributes(typingAttributes)
        let wrapped = NSMutableAttributedString(string: "{{c\(number)::", attributes: attributes)
        wrapped.append(selected)
        wrapped.append(NSAttributedString(string: "}}", attributes: attributes))
        guard shouldChangeText(in: range, replacementString: wrapped.string) else { return }
        storage.replaceCharacters(in: range, with: wrapped)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + wrapped.length - (range.length == 0 ? 2 : 0), length: 0))
    }

    @objc func toggleHTMLSource(_ sender: Any?) {
        field.toggleSource(mediaFolder: editor?.mediaFolder)
    }

    // MARK: Paste and drop

    override func paste(_ sender: Any?) {
        let keep = pasteKeepsFormatting != NSEvent.modifierFlags.contains(.shift)
        if !pasteFrom(.general, keepFormatting: keep) { super.paste(sender) }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) { insertTyped(text) }
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.html, .rtf, .png, .tiff, .fileURL, .string]
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        if let index = characterIndex(at: point) { setSelectedRange(NSRange(location: index, length: 0)) }
        return pasteFrom(sender.draggingPasteboard, keepFormatting: pasteKeepsFormatting) || super.performDragOperation(sender)
    }

    /// Desktop's order: files, then HTML, then images, then rich text,
    /// then plain text.
    private func pasteFrom(_ pasteboard: NSPasteboard, keepFormatting: Bool) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        {
            let html = urls.compactMap(mediaReference).joined()
            if !html.isEmpty { insertHTML(html) }
            return !html.isEmpty
        }
        if let html = pasteboard.string(forType: .html) {
            pasteHTML(html, keepFormatting: keepFormatting)
            return true
        }
        if let image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
            let (data, ext) = Self.encodeImage(image), let name = editor?.addPastedImage(data, ext: ext)
        {
            insertHTML("<img src=\"\(Self.escapeAttribute(name))\">")
            return true
        }
        // A link to an image or sound is downloaded; any other link stays a link.
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, Self.isRemote(url.absoluteString) {
            pasteURL(url.absoluteString)
            return true
        }
        if let rtf = pasteboard.data(forType: .rtf),
            let text = NSAttributedString(rtf: rtf, documentAttributes: nil)
        {
            insertHTML(keepFormatting ? Self.html(from: text) : escapeHTMLText(text.string))
            return true
        }
        if let text = pasteboard.string(forType: .string) {
            insertTyped(text)
            return true
        }
        return false
    }

    /// Pasted HTML through desktop's filter. Inline images are saved
    /// straight away; remote ones are downloaded first, then the HTML is
    /// inserted where the cursor is by then.
    private func pasteHTML(_ html: String, keepFormatting: Bool) {
        var remote: [String] = []
        let filtered = PasteFilter.filter(html, keepFormatting: keepFormatting) { src in
            if Self.isRemote(src) { remote.append(src) }
            return localImage(src) ?? src
        }
        guard !remote.isEmpty, let editor else {
            insertHTML(filtered)
            return
        }
        Task {
            var downloaded: [String: String] = [:]
            for src in Set(remote) {
                switch await editor.addMedia(fromURL: Self.decodeAttribute(src)) {
                case .success(let name): downloaded[src] = name
                case .failure(let error): showError(error.message)
                }
            }
            insertHTML(PasteFilter.filter(html, keepFormatting: keepFormatting) { src in
                downloaded[src].map(Self.escapeAttribute) ?? localImage(src) ?? src
            })
        }
    }

    /// A `data:image/…;base64,` source, saved as a pasted image.
    private func localImage(_ src: String) -> String? {
        guard src.hasPrefix("data:image/"), let comma = src.firstIndex(of: ","),
            src[..<comma].hasSuffix(";base64"),
            let data = Data(base64Encoded: String(src[src.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        var ext = String(src.dropFirst("data:image/".count).prefix { $0 != ";" })
        guard ["jpg", "jpeg", "png", "gif"].contains(ext) else { return nil }
        if ext == "jpeg" { ext = "jpg" }
        return editor?.addPastedImage(data, ext: ext).map(Self.escapeAttribute)
    }

    /// Desktop's `urlToLink`: media is downloaded, anything else becomes a link.
    private func pasteURL(_ url: String) {
        let link = "<a href=\"\(Self.escapeAttribute(url))\">\(escapeHTMLText(url.removingPercentEncoding ?? url))</a>"
        guard let editor, Self.mediaSuffixes.contains(where: { url.lowercased().hasSuffix(".\($0)") }) else {
            insertHTML(link)
            return
        }
        Task {
            switch await editor.addMedia(fromURL: url) {
            case .success(let name):
                let image = UTType(filenameExtension: (name as NSString).pathExtension)?.conforms(to: .image) ?? false
                insertHTML(image ? "<img src=\"\(Self.escapeAttribute(name))\">" : "[sound:\(escapeHTMLText(name))]")
            case .failure(let error):
                showError(error.message)
                insertHTML(link)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// Desktop's image and audio suffixes for pasted links.
    private static let mediaSuffixes = [
        "jpg", "jpeg", "png", "gif", "svg", "webp", "ico", "avif", "3gp", "aac", "avi", "flac", "flv", "m4a", "mkv",
        "mov", "mp3", "mp4", "mpeg", "mpg", "oga", "ogg", "ogv", "ogx", "opus", "spx", "swf", "wav", "webm",
    ]

    private static func isRemote(_ src: String) -> Bool {
        let lower = src.lowercased()
        return ["http://", "https://", "ftp://"].contains { lower.hasPrefix($0) }
    }

    private static func decodeAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
    }

    /// A dropped or pasted file, copied into the media folder.
    private func mediaReference(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), let name = editor?.addMedia(data, preferredName: url.lastPathComponent)
        else { return nil }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) ?? false { return "<img src=\"\(Self.escapeAttribute(name))\">" }
        if type?.conforms(to: .audiovisualContent) ?? false { return "[sound:\(name)]" }
        return nil
    }

    private func insertHTML(_ html: String) {
        let stack = (typingAttributes[.fieldStack] as? [Int]) ?? []
        insertText(document.fragment(html: html, base: stack), replacementRange: selectedRange())
    }

    private func insertTyped(_ text: String) {
        insertText(
            NSAttributedString(string: text, attributes: FieldDocument.cleanTypingAttributes(typingAttributes)),
            replacementRange: selectedRange())
    }

    /// Desktop saves pasted bitmaps as JPEG unless the collection asks for PNG.
    private static func encodeImage(_ data: Data) -> (Data, String)? {
        guard let bitmap = NSBitmapImageRep(data: data),
            let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return nil }
        return (jpeg, "jpg")
    }

    /// Rich text from other apps, as the simple tags desktop keeps.
    private static func html(from text: NSAttributedString) -> String {
        var html = ""
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var run = escapeHTMLText((text.string as NSString).substring(with: range))
            let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.bold) { run = "<b>\(run)</b>" }
            if traits.contains(.italic) { run = "<i>\(run)</i>" }
            if (attributes[.underlineStyle] as? Int ?? 0) != 0 { run = "<u>\(run)</u>" }
            html += run
        }
        return html
    }

    private static func escapeAttribute(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private func escapeHTMLText(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
}

/// Carries a format through `NSApp.sendAction` from the Format menu.
final class FormatCommand: NSObject {
    let format: InlineFormat
    init(_ format: InlineFormat) { self.format = format }
}
