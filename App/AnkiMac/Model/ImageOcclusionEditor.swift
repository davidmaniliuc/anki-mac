import AnkiKit
import AppKit
import CryptoKit
import Observation

/// The mask editor of an image occlusion note, as desktop's editor shows
/// for that note type (ts/routes/image-occlusion): the image, its masks,
/// the drawing tool, and an undo history of its own. It owns the note's
/// occlusion and image fields; the others stay in the field editor.
@Observable
final class ImageOcclusionEditor {
    enum Tool: CaseIterable {
        case select, rectangle, ellipse, polygon, text

        var title: String {
            switch self {
            case .select: Tr.editingImageOcclusionSelectTool
            case .rectangle: Tr.editingImageOcclusionRectangleTool
            case .ellipse: Tr.editingImageOcclusionEllipseTool
            case .polygon: Tr.editingImageOcclusionPolygonTool
            case .text: Tr.editingImageOcclusionTextTool
            }
        }

        var symbol: String {
            switch self {
            case .select: "cursorarrow"
            case .rectangle: "rectangle"
            case .ellipse: "oval"
            case .polygon: "pentagon"
            case .text: "textformat"
            }
        }

        /// Desktop's single-key shortcuts.
        var key: Character {
            switch self {
            case .select: "s"
            case .rectangle: "r"
            case .ellipse: "e"
            case .polygon: "p"
            case .text: "t"
            }
        }
    }

    enum Tab: Hashable { case masks, note }

    let fields: Anki_ImageOcclusion_ImageOcclusionFieldIndexes
    private(set) var image: NSImage?
    /// The image's size in pixels; masks are fractions of it.
    private(set) var imageSize: CGSize = .zero
    private(set) var occlusions: [Occlusion] = []
    var selection: Set<Occlusion.ID> = []
    var tool: Tool = .select
    var tab: Tab = .masks
    /// Desktop's "Hide All, Guess One"; off is "Hide One, Guess One".
    private(set) var occludeInactive = true
    /// Masks drawn see-through, to place them over what they hide.
    var translucent = false
    var message: String?
    /// Called after every change to the masks or the image.
    var onChange: (() -> Void)?
    /// The canvas on screen, for the zoom buttons.
    @ObservationIgnored weak var canvas: MaskCanvasView?

    private(set) var undoStack: [[Occlusion]] = []
    private(set) var redoStack: [[Occlusion]] = []
    /// The two fields' new values; nil leaves a field as it was loaded.
    private var occlusionField: String?
    private var imageField: String?
    private let addMedia: (Data, String) -> String?

    /// A new note starts with no image and no masks; an existing one is
    /// loaded with `load(_:)`.
    init(
        fields: Anki_ImageOcclusion_ImageOcclusionFieldIndexes, isNew: Bool, addMedia: @escaping (Data, String) -> String?
    ) {
        self.fields = fields
        self.addMedia = addMedia
        if isNew {
            occlusionField = ""
            imageField = ""
        }
    }

    /// An existing note's image and masks, as the backend reads them.
    func load(_ note: Anki_ImageOcclusion_GetImageOcclusionNoteResponse.ImageOcclusionNote) {
        if let image = NSImage(data: note.imageData) { show(image) }
        occlusions = OcclusionCloze.occlusions(
            note.occlusions.map { occlusion in
                OcclusionCloze.Parsed(
                    ordinal: Int(occlusion.ordinal),
                    shapes: occlusion.shapes.map { shape in
                        (shape.shape, shape.properties.map { ($0.name, $0.value) })
                    })
            })
        occludeInactive = note.occludeInactive
    }

    /// The editor's value for one of the note's fields, or nil for a field
    /// it doesn't own or hasn't changed.
    func value(forField index: Int) -> String? {
        switch UInt32(index) {
        case fields.occlusions: occlusionField
        case fields.image: imageField
        default: nil
        }
    }

    var hiddenFields: Set<Int> { [Int(fields.occlusions), Int(fields.image)] }

    func setOccludeInactive(_ value: Bool) {
        guard value != occludeInactive else { return }
        occludeInactive = value
        save()
    }

    // MARK: Image

    /// Adds the picked image to the media folder and shows it, as desktop's
    /// Select Image.
    func useImage(at url: URL) {
        guard let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            message = Tr.notetypesErrorLoadingImageOcclusion
            return
        }
        useImage(image, data: data, name: url.lastPathComponent)
    }

    /// Desktop's Paste Image from Clipboard, named as a pasted image.
    func pasteImage() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else {
            message = Tr.editingNoImageFoundOnClipboard
            return
        }
        let png = pasteboard.data(forType: .png)
            ?? image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        guard let png else {
            message = Tr.editingNoImageFoundOnClipboard
            return
        }
        let checksum = Insecure.SHA1.hash(data: png).map { String(format: "%02x", $0) }.joined()
        useImage(image, data: png, name: "paste-\(checksum).png")
    }

    private func useImage(_ image: NSImage, data: Data, name: String) {
        guard let stored = addMedia(data, name) else {
            message = Tr.notetypesErrorLoadingImageOcclusion
            return
        }
        imageField = "<img src=\"\(stored.replacing("&", with: "&amp;").replacing("\"", with: "&quot;"))\">"
        show(image)
        save()
    }

    private func show(_ image: NSImage) {
        let pixels = image.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
        imageSize = pixels.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? image.size
        self.image = image
    }

    // MARK: Masks

    /// Replaces the masks as one undoable step.
    func commit(_ new: [Occlusion]) {
        guard new != occlusions else { return }
        undoStack.append(occlusions)
        redoStack = []
        occlusions = new
        let ids = Set(new.map(\.id))
        selection = selection.filter(ids.contains)
        save()
    }

    func add(_ shape: OcclusionShape) {
        let occlusion = Occlusion(shapes: [shape])
        commit(occlusions + [occlusion])
        selection = [occlusion.id]
    }

    /// Moves the selected masks by a fraction of the image.
    func moveSelection(dx: Double, dy: Double) {
        commit(occlusions.map { occlusion in
            guard selection.contains(occlusion.id) else { return occlusion }
            var moved = occlusion
            moved.shapes = occlusion.shapes.map { $0.offset(dx: dx, dy: dy) }
            return moved
        })
    }

    func replace(_ id: Occlusion.ID, shapes: [OcclusionShape]) {
        commit(occlusions.map { $0.id == id ? Occlusion(id: id, shapes: shapes, ordinal: $0.ordinal) : $0 })
    }

    func deleteSelection() {
        commit(occlusions.filter { !selection.contains($0.id) })
    }

    /// Copies of the selection, offset a little, as desktop's Duplicate.
    func duplicateSelection() {
        let dx = 10 / max(imageSize.width, 1), dy = 10 / max(imageSize.height, 1)
        let copies = occlusions.filter { selection.contains($0.id) }.map {
            Occlusion(shapes: $0.shapes.map { $0.offset(dx: dx, dy: dy) })
        }
        guard !copies.isEmpty else { return }
        commit(occlusions + copies)
        selection = Set(copies.map(\.id))
    }

    func selectAll() {
        selection = Set(occlusions.map(\.id))
    }

    /// One mask of the selected ones, revealed together, as desktop's Group.
    func groupSelection() {
        let grouped = occlusions.filter { selection.contains($0.id) }
        guard grouped.count > 1, let first = occlusions.firstIndex(where: { selection.contains($0.id) }) else { return }
        let group = Occlusion(grouping: grouped)
        var new = occlusions.filter { !selection.contains($0.id) }
        new.insert(group, at: min(first, new.count))
        commit(new)
        selection = [group.id]
    }

    /// Splits selected groups into masks of their own, numbered afresh.
    func ungroupSelection() {
        var split: Set<Occlusion.ID> = []
        let new = occlusions.flatMap { occlusion -> [Occlusion] in
            guard selection.contains(occlusion.id), occlusion.shapes.count > 1 else { return [occlusion] }
            let parts = occlusion.shapes.map { Occlusion(shapes: [$0]) }
            split.formUnion(parts.map(\.id))
            return parts
        }
        guard !split.isEmpty else { return }
        commit(new)
        selection = split
    }

    var canGroup: Bool { selection.count > 1 }
    var canUngroup: Bool { occlusions.contains { selection.contains($0.id) && $0.shapes.count > 1 } }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(occlusions)
        occlusions = previous
        selection = []
        save()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(occlusions)
        occlusions = next
        selection = []
        save()
    }

    /// Writes the masks into the occlusion field, numbering new ones.
    private func save() {
        let (text, numbered) = OcclusionCloze.text(occlusions, occludeInactive: occludeInactive)
        occlusions = numbered
        occlusionField = text
        onChange?()
    }
}

extension OcclusionShape {
    func offset(dx: Double, dy: Double) -> OcclusionShape {
        var moved = self
        moved.left += dx
        moved.top += dy
        if case .polygon(let points) = geometry {
            moved.geometry = .polygon(points: points.map { OcclusionPoint(x: $0.x + dx, y: $0.y + dy) })
        }
        return moved
    }
}
