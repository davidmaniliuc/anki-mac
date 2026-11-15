import AppKit
import SwiftUI

/// A list floating under a field, in a panel in its own window, so it can
/// reach past the window's edge. It opens under the field, or over it when
/// the screen ends below. The panel never takes the focus: the keys stay
/// with the text.
final class FloatingList {
    private var panel: NSPanel?

    var isShown: Bool { panel?.isVisible == true }

    /// `inset` moves the list left of the field, so its rows' text lines up with the field's.
    func show(_ content: some View, under anchor: NSView, inset: CGFloat) {
        guard let parent = anchor.window else { return hide() }
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        guard let host = panel.contentView as? ClickThroughHostingView<AnyView> else { return }
        // A new root updates the list now, so it is measured with its new rows.
        host.rootView = AnyView(content)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let field = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        let gap = Theme.Tags.popupGap
        var origin = NSPoint(x: field.minX - inset, y: field.minY - gap - size.height)
        if origin.y < screen.minY { origin.y = field.maxY + gap }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let host = ClickThroughHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }
}

/// Takes the first click, so a row can be picked while the field's window
/// keeps the focus.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hands a floating list the view it opens against.
struct FloatingListAnchor: NSViewRepresentable {
    let set: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        set(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        set(view)
    }
}
