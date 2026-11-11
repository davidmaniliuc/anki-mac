import AppKit
import SwiftUI

/// The image and its masks, drawn and edited with the mouse and desktop's
/// single-key shortcuts: desktop's fabric canvas as an AppKit view. One
/// point is one image pixel; the scroll view around it zooms and pans.
final class MaskCanvasView: NSView {
    let editor: ImageOcclusionEditor

    private enum Drag {
        case move(start: NSPoint, current: NSPoint)
        case resize(Occlusion.ID, original: OcclusionShape, handle: Handle, current: NSPoint)
        case marquee(start: NSPoint, current: NSPoint, adding: Set<Occlusion.ID>)
        case draw(start: NSPoint, current: NSPoint)
    }

    /// A resize handle, as a corner or edge midpoint of the box (0, ½ or 1).
    private struct Handle: Equatable {
        let x: CGFloat
        let y: CGFloat

        static let all: [Handle] = [(0, 0), (0.5, 0), (1, 0), (1, 0.5), (1, 1), (0.5, 1), (0, 1), (0, 0.5)].map {
            Handle(x: $0.0, y: $0.1)
        }
    }

    private var drag: Drag?
    /// The polygon being drawn, closed by clicking its first point,
    /// double-clicking or Return.
    private var polygon: [NSPoint] = []
    private var pointer: NSPoint?
    private var textField: NSTextField?
    /// The label being retyped; nil while typing a new one.
    private var editingText: Occlusion.ID?
    private var needsFit = true

    init(editor: ImageOcclusionEditor) {
        self.editor = editor
        super.init(frame: NSRect(origin: .zero, size: editor.imageSize))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var size: CGSize { bounds.size }
    private var zoom: CGFloat { enclosingScrollView?.magnification ?? 1 }

    /// Follows the editor after a change.
    func refresh() {
        if frame.size != editor.imageSize {
            setFrameSize(editor.imageSize)
            needsFit = true
            enclosingScrollView?.tile()
        }
        if editor.tool != .polygon { polygon = [] }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: Zoom

    func zoomIn() { zoom(by: Theme.ImageOcclusion.zoomStep) }
    func zoomOut() { zoom(by: 1 / Theme.ImageOcclusion.zoomStep) }

    private func zoom(by factor: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let visible = scrollView.documentVisibleRect
        scrollView.setMagnification(scrollView.magnification * factor, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
    }

    /// The whole image in view, never enlarged, as desktop's Reset Zoom.
    func fit() {
        guard let scrollView = enclosingScrollView, size.width > 0, size.height > 0 else { return }
        let available = scrollView.contentSize
        guard available.width > 0, available.height > 0 else { return }
        needsFit = false
        scrollView.magnification = min(1, available.width / size.width, available.height / size.height)
    }

    fileprivate func fitIfNeeded() {
        if needsFit { fit() }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        editor.image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let alpha = editor.translucent ? Theme.ImageOcclusion.translucentAlpha : 1
        let line = 1 / zoom
        // The label being retyped shows in its text field instead.
        for occlusion in displayedOcclusions where occlusion.id != editingText {
            for shape in occlusion.shapes {
                if case .text(let text, _, _) = shape.geometry {
                    drawText(text, shape: shape, alpha: alpha)
                    continue
                }
                let path = self.path(shape)
                color(shape.fill, default: OcclusionShape.maskColor).withAlphaComponent(alpha).setFill()
                path.fill()
                Theme.ImageOcclusion.border.withAlphaComponent(alpha).setStroke()
                path.lineWidth = line
                path.stroke()
            }
        }
        drawSelection(line: line)
        drawDraft(line: line)
    }

    /// The masks with the drag in progress applied.
    private var displayedOcclusions: [Occlusion] {
        switch drag {
        case .move(let start, let current):
            let (dx, dy) = normalized(current - start)
            return editor.occlusions.map { occlusion in
                guard editor.selection.contains(occlusion.id) else { return occlusion }
                var moved = occlusion
                moved.shapes = occlusion.shapes.map { $0.offset(dx: dx, dy: dy) }
                return moved
            }
        case .resize(let id, let original, let handle, let current):
            let resized = self.resized(original, handle: handle, to: current)
            return editor.occlusions.map { $0.id == id ? Occlusion(id: id, shapes: [resized], ordinal: $0.ordinal) : $0 }
        default:
            return editor.occlusions
        }
    }

    private func drawSelection(line: CGFloat) {
        let occlusions = displayedOcclusions.filter { editor.selection.contains($0.id) }
        Theme.ImageOcclusion.selection.setStroke()
        for occlusion in occlusions {
            let box = NSBezierPath(rect: bounds(occlusion).insetBy(dx: -2 * line, dy: -2 * line))
            box.lineWidth = line
            box.setLineDash([4 * line, 3 * line], count: 2, phase: 0)
            box.stroke()
        }
        guard let (_, shape) = resizable(in: occlusions) else { return }
        let side = Theme.ImageOcclusion.handleSize * line
        for handle in Handle.all {
            let point = handlePoint(handle, of: pixelRect(shape))
            let square = NSBezierPath(rect: NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
            NSColor.white.setFill()
            square.fill()
            square.lineWidth = line
            square.stroke()
        }
    }

    private func drawDraft(line: CGFloat) {
        Theme.ImageOcclusion.selection.setStroke()
        switch drag {
        case .draw(let start, let current):
            let rect = NSRect(points: start, current)
            let path = editor.tool == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            color(nil, default: OcclusionShape.maskColor).withAlphaComponent(Theme.ImageOcclusion.translucentAlpha).setFill()
            path.fill()
            path.lineWidth = line
            path.stroke()
        case .marquee(let start, let current, _):
            let path = NSBezierPath(rect: NSRect(points: start, current))
            Theme.ImageOcclusion.selection.withAlphaComponent(0.1).setFill()
            path.fill()
            path.lineWidth = line
            path.stroke()
        default:
            break
        }
        guard let first = polygon.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        for point in polygon.dropFirst() { path.line(to: point) }
        if let pointer { path.line(to: pointer) }
        path.lineWidth = line
        path.stroke()
        let side = Theme.ImageOcclusion.handleSize * line
        NSBezierPath(ovalIn: NSRect(x: first.x - side / 2, y: first.y - side / 2, width: side, height: side)).stroke()
    }

    // MARK: Geometry in pixels

    private func normalized(_ delta: CGSize) -> (Double, Double) {
        (delta.width / size.width, delta.height / size.height)
    }

    /// The unrotated box of a shape.
    private func pixelRect(_ shape: OcclusionShape) -> NSRect {
        let origin = NSPoint(x: shape.left * size.width, y: shape.top * size.height)
        switch shape.geometry {
        case .rect(let width, let height):
            return NSRect(origin: origin, size: CGSize(width: width * size.width, height: height * size.height))
        case .ellipse(let rx, let ry):
            return NSRect(origin: origin, size: CGSize(width: 2 * rx * size.width, height: 2 * ry * size.height))
        case .polygon(let points):
            let xs = points.map(\.x), ys = points.map(\.y)
            return NSRect(
                origin: origin,
                size: CGSize(
                    width: ((xs.max() ?? 0) - (xs.min() ?? 0)) * size.width,
                    height: ((ys.max() ?? 0) - (ys.min() ?? 0)) * size.height))
        case .text(let text, let scale, let fontSize):
            return textLayout(text, scale: scale, fontSize: fontSize, origin: origin).box
        }
    }

    /// The shape's outline, rotated about (left, top) as the reviewer draws it.
    private func path(_ shape: OcclusionShape) -> NSBezierPath {
        let rect = pixelRect(shape)
        let path: NSBezierPath
        switch shape.geometry {
        case .ellipse:
            path = NSBezierPath(ovalIn: rect)
        case .polygon(let points):
            let minX = points.map(\.x).min() ?? 0, minY = points.map(\.y).min() ?? 0
            path = NSBezierPath()
            for (index, point) in points.enumerated() {
                let pixel = NSPoint(
                    x: (point.x - minX + shape.left) * size.width, y: (point.y - minY + shape.top) * size.height)
                if index == 0 { path.move(to: pixel) } else { path.line(to: pixel) }
            }
            path.close()
            // The reviewer doesn't rotate polygons; their points carry it.
            return path
        default:
            path = NSBezierPath(rect: rect)
        }
        if shape.angle != 0 { path.transform(using: rotation(shape)) }
        return path
    }

    private func rotation(_ shape: OcclusionShape) -> AffineTransform {
        var transform = AffineTransform(translationByX: shape.left * size.width, byY: shape.top * size.height)
        transform.rotate(byDegrees: shape.angle)
        transform.translate(x: -shape.left * size.width, y: -shape.top * size.height)
        return transform
    }

    private struct TextLayout {
        let font: NSFont
        let lines: [String]
        let lineHeight: CGFloat
        let box: NSRect
    }

    /// Lines, font and white box as the reviewer lays out a label.
    private func textLayout(_ text: String, scale: Double, fontSize: Double?, origin: NSPoint) -> TextLayout {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let pixels = (fontSize.map { $0 * size.height } ?? Theme.ImageOcclusion.textFontSize) * scale
        let font = NSFont(name: Theme.ImageOcclusion.textFont, size: pixels) ?? .systemFont(ofSize: pixels)
        let lines = text.components(separatedBy: "\n")
        let lineHeight = 1.5 * font.capHeight
        let width = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let padding = Theme.ImageOcclusion.textPadding * scale
        return TextLayout(
            font: font, lines: lines, lineHeight: lineHeight,
            box: NSRect(
                origin: origin, size: CGSize(width: width + padding, height: lineHeight * CGFloat(lines.count) + padding)))
    }

    private func drawText(_ text: String, shape: OcclusionShape, alpha: CGFloat) {
        guard case .text(_, let scale, let fontSize) = shape.geometry else { return }
        let layout = textLayout(text, scale: scale, fontSize: fontSize, origin: pixelRect(shape).origin)
        NSGraphicsContext.saveGraphicsState()
        if shape.angle != 0 { (rotation(shape) as NSAffineTransform).concat() }
        Theme.ImageOcclusion.textBackground.withAlphaComponent(alpha).setFill()
        layout.box.fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: layout.font,
            .foregroundColor: color(shape.fill, default: OcclusionShape.textColor).withAlphaComponent(alpha),
        ]
        for (index, line) in layout.lines.enumerated() {
            let top = layout.box.minY + CGFloat(index) * layout.lineHeight
            (line as NSString).draw(at: NSPoint(x: layout.box.minX, y: top), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Several shapes' box: a group's, or one mask's.
    private func bounds(_ occlusion: Occlusion) -> NSRect {
        occlusion.shapes.map { shape in
            guard shape.isText else { return path(shape).bounds }
            let box = NSBezierPath(rect: pixelRect(shape))
            box.transform(using: rotation(shape))
            return box.bounds
        }.reduce(NSRect.null) { $0.union($1) }
    }

    /// Hit-tests from the topmost mask down.
    private func occlusion(at point: NSPoint) -> Occlusion? {
        editor.occlusions.last { occlusion in
            occlusion.shapes.contains { shape in
                if shape.isText {
                    var inverse = rotation(shape)
                    inverse.invert()
                    return pixelRect(shape).contains(inverse.transform(point))
                }
                return path(shape).contains(point)
            }
        }
    }

    /// The selection's one shape when it can be resized: a single
    /// unrotated mask, not a label or a group.
    private func resizable(in occlusions: [Occlusion]) -> (Occlusion.ID, OcclusionShape)? {
        guard occlusions.count == 1, occlusions[0].shapes.count == 1 else { return nil }
        let shape = occlusions[0].shapes[0]
        return shape.isText || shape.angle != 0 ? nil : (occlusions[0].id, shape)
    }

    private func handlePoint(_ handle: Handle, of rect: NSRect) -> NSPoint {
        NSPoint(x: rect.minX + handle.x * rect.width, y: rect.minY + handle.y * rect.height)
    }

    private func handle(at point: NSPoint) -> (Occlusion.ID, OcclusionShape, Handle)? {
        guard let (id, shape) = resizable(in: editor.occlusions.filter { editor.selection.contains($0.id) }) else {
            return nil
        }
        let reach = Theme.ImageOcclusion.handleSize / zoom
        let rect = pixelRect(shape)
        return Handle.all.first { handle in
            let center = handlePoint(handle, of: rect)
            return abs(center.x - point.x) <= reach && abs(center.y - point.y) <= reach
        }.map { (id, shape, $0) }
    }

    /// The shape with the handle's edges dragged to a point.
    private func resized(_ shape: OcclusionShape, handle: Handle, to point: NSPoint) -> OcclusionShape {
        let old = pixelRect(shape)
        var minX = old.minX, maxX = old.maxX, minY = old.minY, maxY = old.maxY
        if handle.x == 0 { minX = min(point.x, maxX - 1) } else if handle.x == 1 { maxX = max(point.x, minX + 1) }
        if handle.y == 0 { minY = min(point.y, maxY - 1) } else if handle.y == 1 { maxY = max(point.y, minY + 1) }
        let new = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return shape.fitted(from: old, to: new, in: size)
    }

    // MARK: Mouse

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: editor.tool == .select ? .arrow : editor.tool == .text ? .iBeam : .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard !polygon.isEmpty else { return }
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        endTextEditing()
        window?.makeFirstResponder(self)
        guard editor.image != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch editor.tool {
        case .select:
            selectDown(at: point, event: event)
        case .rectangle, .ellipse:
            drag = .draw(start: point, current: point)
        case .polygon:
            polygonDown(at: point, event: event)
        case .text:
            beginTextEditing(at: point, existing: nil)
        }
        needsDisplay = true
    }

    private func selectDown(at point: NSPoint, event: NSEvent) {
        let extending = event.modifierFlags.contains(.shift)
        if !extending, let (id, shape, handle) = handle(at: point) {
            drag = .resize(id, original: shape, handle: handle, current: point)
            return
        }
        guard let hit = occlusion(at: point) else {
            if !extending { editor.selection = [] }
            drag = .marquee(start: point, current: point, adding: editor.selection)
            return
        }
        if event.clickCount == 2, hit.isText {
            editor.selection = [hit.id]
            beginTextEditing(at: pixelRect(hit.shapes[0]).origin, existing: hit)
            return
        }
        if extending {
            editor.selection.formSymmetricDifference([hit.id])
        } else if !editor.selection.contains(hit.id) {
            editor.selection = [hit.id]
        }
        if editor.selection.contains(hit.id) { drag = .move(start: point, current: point) }
    }

    private func polygonDown(at point: NSPoint, event: NSEvent) {
        let closing = polygon.count >= 3
            && (event.clickCount == 2 || hypot(point.x - polygon[0].x, point.y - polygon[0].y)
                <= Theme.ImageOcclusion.closeDistance / zoom)
        if closing {
            finishPolygon()
        } else if event.clickCount < 2 {
            polygon.append(point)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .move(let start, _): drag = .move(start: start, current: point)
        case .resize(let id, let original, let handle, _): drag = .resize(id, original: original, handle: handle, current: point)
        case .marquee(let start, _, let adding):
            drag = .marquee(start: start, current: point, adding: adding)
            let rect = NSRect(points: start, point)
            editor.selection = adding.union(editor.occlusions.filter { bounds($0).intersects(rect) }.map(\.id))
        case .draw(let start, _): drag = .draw(start: start, current: point)
        case nil: return
        }
        autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            drag = nil
            needsDisplay = true
        }
        switch drag {
        case .move(let start, let current) where start != current:
            let (dx, dy) = normalized(current - start)
            editor.moveSelection(dx: dx, dy: dy)
        case .resize(let id, let original, let handle, let current):
            editor.replace(id, shapes: [resized(original, handle: handle, to: current)])
        case .draw(let start, let current):
            let rect = NSRect(points: start, current).intersection(bounds)
            guard rect.width >= Theme.ImageOcclusion.minShapeSize, rect.height >= Theme.ImageOcclusion.minShapeSize
            else { return }
            let left = rect.minX / size.width, top = rect.minY / size.height
            let geometry: OcclusionShape.Geometry = editor.tool == .ellipse
                ? .ellipse(rx: rect.width / 2 / size.width, ry: rect.height / 2 / size.height)
                : .rect(width: rect.width / size.width, height: rect.height / size.height)
            editor.add(OcclusionShape(geometry: geometry, left: left, top: top))
        default:
            break
        }
    }

    private func finishPolygon() {
        let points = polygon
        polygon = []
        pointer = nil
        let xs = points.map(\.x), ys = points.map(\.y)
        let rect = NSRect(points: NSPoint(x: xs.min() ?? 0, y: ys.min() ?? 0), NSPoint(x: xs.max() ?? 0, y: ys.max() ?? 0))
        guard points.count >= 3, rect.width >= Theme.ImageOcclusion.minShapeSize,
            rect.height >= Theme.ImageOcclusion.minShapeSize
        else { return }
        editor.add(
            OcclusionShape(
                geometry: .polygon(
                    points: points.map { OcclusionPoint(x: $0.x / size.width, y: $0.y / size.height) }),
                left: rect.minX / size.width, top: rect.minY / size.height))
    }

    // MARK: Labels

    private func beginTextEditing(at point: NSPoint, existing: Occlusion?) {
        let shape = existing?.shapes.first
        var text = ""
        var fontSize = Theme.ImageOcclusion.textFontSize / zoom / (window?.backingScaleFactor ?? 1)
        if let shape, case .text(let current, let scale, let size) = shape.geometry {
            text = current
            fontSize = (size.map { $0 * self.size.height } ?? Theme.ImageOcclusion.textFontSize) * scale
        }
        let field = NSTextField(string: text)
        field.font = NSFont(name: Theme.ImageOcclusion.textFont, size: fontSize) ?? .systemFont(ofSize: fontSize)
        field.isBordered = true
        field.focusRingType = .none
        field.backgroundColor = Theme.ImageOcclusion.textBackground
        field.textColor = .black
        field.usesSingleLineMode = false
        field.target = self
        field.action = #selector(textFieldDone(_:))
        field.sizeToFit()
        field.frame = NSRect(
            origin: point, size: CGSize(width: max(field.frame.width, fontSize * 6), height: field.frame.height))
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        editingText = existing?.id
        needsDisplay = true
    }

    @objc private func textFieldDone(_ sender: NSTextField) {
        endTextEditing()
        window?.makeFirstResponder(self)
    }

    /// Adds or retypes the label being edited; an emptied one is removed.
    private func endTextEditing() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        let origin = field.frame.origin
        let fontSize = (field.font?.pointSize ?? Theme.ImageOcclusion.textFontSize) / size.height
        field.removeFromSuperview()
        defer {
            editingText = nil
            needsDisplay = true
        }
        if let id = editingText, let existing = editor.occlusions.first(where: { $0.id == id }) {
            var shape = existing.shapes[0]
            guard case .text(_, let scale, let size) = shape.geometry else { return }
            if text.isEmpty {
                editor.selection = [id]
                editor.deleteSelection()
            } else {
                shape.geometry = .text(text, scale: scale, fontSize: size)
                editor.replace(id, shapes: [shape])
            }
        } else if !text.isEmpty {
            editor.add(
                OcclusionShape(
                    geometry: .text(text, scale: 1, fontSize: fontSize), left: origin.x / size.width,
                    top: origin.y / size.height))
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 51, 117:  // delete, forward delete
            editor.deleteSelection()
            return
        case 53:  // escape
            if polygon.isEmpty {
                editor.selection = []
            } else {
                polygon = []
                pointer = nil
            }
            needsDisplay = true
            return
        case 36, 76:  // return, enter
            finishPolygon()
            needsDisplay = true
            return
        default:
            break
        }
        guard flags.subtracting(.capsLock).isEmpty, let key = event.charactersIgnoringModifiers?.lowercased().first
        else {
            super.keyDown(with: event)
            return
        }
        if let tool = ImageOcclusionEditor.Tool.allCases.first(where: { $0.key == key }) {
            editor.tool = tool
            return
        }
        switch key {
        case "d": editor.duplicateSelection()
        case "g": editor.groupSelection()
        case "u": editor.ungroupSelection()
        case "a": editor.selectAll()
        case "l": editor.translucent.toggle()
        case "[": zoomOut()
        case "]": zoomIn()
        case "f": fit()
        default: super.keyDown(with: event)
        }
    }

    /// Undo and redo act on the masks while the canvas has focus, ahead of
    /// the menu's collection undo, as desktop's mask editor.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
        case ("z", [.command]): editor.undo()
        case ("z", [.command, .shift]), ("y", [.command]): editor.redo()
        case ("a", [.command]): editor.selectAll()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Colours

    private func color(_ hex: String?, default fallback: String) -> NSColor {
        Self.color(hex) ?? Self.color(fallback) ?? .systemYellow
    }

    private static func color(_ hex: String?) -> NSColor? {
        guard let hex, hex.count == 7, hex.hasPrefix("#"), let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat(value >> 16) / 255, green: CGFloat(value >> 8 & 0xff) / 255, blue: CGFloat(value & 0xff) / 255,
            alpha: 1)
    }
}

extension OcclusionShape {
    /// The shape stretched from one pixel box to another.
    fileprivate func fitted(from old: NSRect, to new: NSRect, in size: CGSize) -> OcclusionShape {
        var shape = self
        shape.left = new.minX / size.width
        shape.top = new.minY / size.height
        switch geometry {
        case .rect:
            shape.geometry = .rect(width: new.width / size.width, height: new.height / size.height)
        case .ellipse:
            shape.geometry = .ellipse(rx: new.width / 2 / size.width, ry: new.height / 2 / size.height)
        case .polygon(let points):
            let minX = points.map(\.x).min() ?? 0, minY = points.map(\.y).min() ?? 0
            let sx = old.width > 0 ? new.width / old.width : 1, sy = old.height > 0 ? new.height / old.height : 1
            shape.geometry = .polygon(
                points: points.map { point in
                    OcclusionPoint(
                        x: (new.minX + (point.x - minX) * size.width * sx) / size.width,
                        y: (new.minY + (point.y - minY) * size.height * sy) / size.height)
                })
        case .text:
            break
        }
        return shape
    }
}

private func - (lhs: NSPoint, rhs: NSPoint) -> CGSize {
    CGSize(width: lhs.x - rhs.x, height: lhs.y - rhs.y)
}

extension NSRect {
    fileprivate init(points a: NSPoint, _ b: NSPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Keeps a smaller-than-the-view image in the middle.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return rect }
        if rect.width > document.width { rect.origin.x = (document.width - rect.width) / 2 }
        if rect.height > document.height { rect.origin.y = (document.height - rect.height) / 2 }
        return rect
    }
}

/// Fits the image once the view has a size.
private final class MaskScrollView: NSScrollView {
    override func tile() {
        super.tile()
        (documentView as? MaskCanvasView)?.fitIfNeeded()
    }
}

/// The canvas in SwiftUI, zoomed by pinching or the toolbar.
struct MaskCanvas: NSViewRepresentable {
    let editor: ImageOcclusionEditor
    /// Read here so SwiftUI redraws the canvas when they change.
    let occlusions: [Occlusion]
    let selection: Set<Occlusion.ID>
    let tool: ImageOcclusionEditor.Tool
    let translucent: Bool
    let imageSize: CGSize

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MaskScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Theme.ImageOcclusion.minZoom
        scrollView.maxMagnification = Theme.ImageOcclusion.maxZoom
        scrollView.backgroundColor = Theme.ImageOcclusion.canvasBackground
        let canvas = MaskCanvasView(editor: editor)
        scrollView.documentView = canvas
        editor.canvas = canvas
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        (scrollView.documentView as? MaskCanvasView)?.refresh()
    }
}
