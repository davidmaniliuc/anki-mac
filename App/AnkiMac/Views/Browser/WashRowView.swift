import AppKit

/// A row of the browser's outline or table that draws its own selection: a
/// wash in a rounded rectangle kept in from the pane's edges, in place of the
/// system's accent-blue bar. Rows of one selection join into a single block.
/// The wash looks the same whether or not the view has focus, and the row's
/// text stays Ink, so the row never reports itself as emphasized.
class WashRowView: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override var isPreviousRowSelected: Bool { didSet { needsDisplay = true } }
    override var isNextRowSelected: Bool { didSet { needsDisplay = true } }

    /// The selection is drawn with the background, so a subclass's tint can
    /// go over it.
    override func drawSelection(in dirtyRect: NSRect) {}

    override func drawBackground(in dirtyRect: NSRect) {
        if isSelected { fillWash(Theme.Palette.selectionNS) }
    }

    /// The area the wash is kept inside, less `rowInset` either side.
    var washBounds: NSRect { bounds }

    /// Fills the row's wash shape, the same for a selection, a hover and a
    /// tint. A selected row joins the selected rows beside it; others don't.
    func fillWash(_ color: NSColor) {
        let radius = Theme.Layout.rowRadius
        let gap = Theme.Browser.rowWashGap
        var rect = washBounds.insetBy(dx: Theme.Browser.rowInset, dy: 0)
        let joinsMinY = isSelected && (isFlipped ? isPreviousRowSelected : isNextRowSelected)
        let joinsMaxY = isSelected && (isFlipped ? isNextRowSelected : isPreviousRowSelected)
        // A joined side runs past the row, so its corners are drawn out of sight.
        if joinsMinY {
            rect.origin.y -= radius
            rect.size.height += radius
        } else {
            rect.origin.y += gap
            rect.size.height -= gap
        }
        rect.size.height += joinsMaxY ? radius : -gap
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
