import AppKit
import SwiftUI

/// Tags as chips, then the text being typed, which completes from the
/// collection's tags in a list floating under it, as Things' tag field.
/// Space, comma, Return or Tab ends a tag; Delete on empty text selects the
/// last chip, and again removes it. Double-clicking a chip takes it back
/// into the text to edit.
struct TagField: View {
    @Binding var tags: [String]
    let complete: (String) -> [String]
    var borderless = false

    @State private var text = ""
    @State private var selectedChip: Int?
    @State private var popup = TagSuggestions()
    @FocusState private var focused: Bool

    var body: some View {
        FlowLayout(spacing: Theme.Tags.spacing) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                chip(tag, selected: selectedChip == index)
                    .onTapGesture(count: 2) { edit(at: index) }
                    .onTapGesture {
                        selectedChip = index
                        focused = true
                    }
            }
            TextField(Tr.editingTags, text: $text, prompt: tags.isEmpty ? Text(Tr.editingTags) : Text(""))
                .textFieldStyle(.plain)
                .font(Font(Theme.Tags.font))
                .labelsHidden()
                .focused($focused)
                .frame(width: textWidth, height: Theme.Tags.chipHeight)
                .background(AnchorReader(popup: popup))
                .onKeyPress(phases: .down, action: key)
                .accessibilityLabel(Tr.editingTags)
        }
        .padding(borderless ? 0 : Theme.Spacing.xSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !borderless {
                RoundedRectangle(cornerRadius: Theme.Tags.boxRadius)
                    .strokeBorder(Theme.Palette.hairline)
                    .background(Theme.Palette.canvas, in: .rect(cornerRadius: Theme.Tags.boxRadius))
            }
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .onChange(of: text) { _, new in typed(new) }
        .onChange(of: focused) { _, focused in
            if !focused {
                commit(text)
                text = ""
                selectedChip = nil
                popup.hide()
            }
        }
        .onDisappear { popup.hide() }
        .onAppear { popup.pick = { [self] in pick($0) } }
    }

    private func chip(_ tag: String, selected: Bool) -> some View {
        Text(tag)
            .font(Theme.Tags.chipFont)
            .lineLimit(1)
            .foregroundStyle(selected ? Color.white : Theme.Palette.text)
            .padding(.horizontal, Theme.Tags.chipPadding)
            .frame(height: Theme.Tags.chipHeight)
            .background(
                Capsule().fill(selected ? Theme.Palette.accent : Theme.Palette.raised)
                    .overlay(Capsule().strokeBorder(selected ? .clear : Theme.Palette.hairline)))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// As wide as what's typed, and never so narrow it can't be clicked into.
    private var textWidth: CGFloat {
        let typed = (text as NSString).size(withAttributes: [.font: Theme.Tags.font]).width
        return max(Theme.Tags.fieldMinWidth, typed.rounded(.up) + Theme.Spacing.small)
    }

    // MARK: Typing

    private func typed(_ new: String) {
        selectedChip = nil
        // Anki's tags have no spaces: a space or comma ends one.
        let separators: Set<Character> = [" ", ",", "\u{3000}"]
        if new.contains(where: separators.contains) {
            let parts = new.split(whereSeparator: separators.contains).map(String.init)
            let ended = new.last.map(separators.contains) ?? false
            parts.dropLast(ended ? 0 : 1).forEach(commit)
            text = ended ? "" : parts.last ?? ""
            return
        }
        refreshSuggestions()
    }

    private func refreshSuggestions() {
        guard !text.isEmpty else { return popup.hide() }
        let have = Set(tags.map { $0.lowercased() })
        let matches = complete(text).filter { !have.contains($0.lowercased()) }
        let exact = matches.contains { $0.caseInsensitiveCompare(text) == .orderedSame }
        popup.show(matches: matches, newTag: exact || have.contains(text.lowercased()) ? nil : text)
    }

    private func key(_ press: KeyPress) -> KeyPress.Result {
        // Command-Return adds the note; the window's shortcut takes it.
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        switch press.key {
        case .downArrow where popup.isShown:
            popup.move(1)
        case .upArrow where popup.isShown:
            popup.move(-1)
        case .escape where popup.isShown:
            popup.hide()
        case .return, .tab:
            // With nothing to finish, Tab moves on and Return does what the window does.
            if popup.isShown {
                popup.pickHighlighted()
            } else if !text.isEmpty {
                commit(text)
                text = ""
            } else {
                return .ignored
            }
        // A text field hands Backspace on as DEL, not as `.delete`.
        case .delete where text.isEmpty, KeyEquivalent("\u{7F}") where text.isEmpty:
            guard !tags.isEmpty else { return .ignored }
            if let selected = selectedChip {
                tags.remove(at: selected)
                selectedChip = nil
            } else {
                selectedChip = tags.count - 1
            }
        default:
            return .ignored
        }
        return .handled
    }

    private func pick(_ tag: String) {
        commit(tag)
        text = ""
        popup.hide()
        focused = true
    }

    private func commit(_ tag: String) {
        let tag = tag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
        tags.append(tag)
    }

    private func edit(at index: Int) {
        commit(text)
        text = tags.remove(at: index)
        selectedChip = nil
        focused = true
    }
}

/// Hands the floating list the view it opens against.
private struct AnchorReader: NSViewRepresentable {
    let popup: TagSuggestions

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        popup.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        popup.anchor = view
    }
}

/// The list of matching tags, then "New Tag" for the text as typed, in a
/// Liquid Glass panel in its own window, so it can reach past the editor's
/// edge. It opens under the text, or over it when the screen ends below.
/// The panel never takes the focus: the keys stay with the text.
@Observable
final class TagSuggestions {
    private(set) var matches: [String] = []
    private(set) var newTag: String?
    var highlighted = 0
    @ObservationIgnored weak var anchor: NSView?
    @ObservationIgnored var pick: (String) -> Void = { _ in }
    @ObservationIgnored private var panel: NSPanel?

    var isShown: Bool { panel?.isVisible == true }

    private var rows: [String] { matches + (newTag.map { [$0] } ?? []) }

    func show(matches: [String], newTag: String?) {
        self.matches = matches
        self.newTag = newTag
        highlighted = 0
        guard !rows.isEmpty, let anchor, let parent = anchor.window else { return hide() }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let content = panel.contentView as? ClickThroughHostingView<TagSuggestionList> else { return }
        // A new root updates the list now, so it is measured with its new rows.
        content.rootView = TagSuggestionList(suggestions: self)
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let field = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        let gap = Theme.Tags.popupGap
        var origin = NSPoint(
            x: field.minX - Theme.Tags.popupPadding - Theme.Tags.chipPadding, y: field.minY - gap - size.height)
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

    func move(_ step: Int) {
        highlighted = (highlighted + step + rows.count) % rows.count
    }

    func pickHighlighted() {
        guard rows.indices.contains(highlighted) else { return hide() }
        pick(rows[highlighted])
    }

    fileprivate func pick(row: Int) {
        guard rows.indices.contains(row) else { return }
        pick(rows[row])
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        let host = ClickThroughHostingView(rootView: TagSuggestionList(suggestions: self))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }
}

/// Takes the first click, so a row can be picked while the editor's window
/// keeps the focus.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct TagSuggestionList: View {
    let suggestions: TagSuggestions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.matches.enumerated()), id: \.offset) { index, tag in
                row(tag, index: index)
            }
            if let newTag = suggestions.newTag {
                if !suggestions.matches.isEmpty {
                    Theme.Palette.hairline.frame(height: 1)
                        .padding(.horizontal, Theme.Tags.chipPadding)
                        .padding(.vertical, Theme.Tags.popupPadding)
                }
                row("New Tag \u{201C}\(newTag)\u{201D}", index: suggestions.matches.count)
            }
        }
        .padding(Theme.Tags.popupPadding)
        .frame(minWidth: Theme.Tags.popupMinWidth, maxWidth: Theme.Tags.popupMaxWidth, alignment: .leading)
        .fixedSize()
        .glassEffect(
            .regular.tint(Theme.Palette.canvas.opacity(Theme.Tags.tintOpacity)),
            in: RoundedRectangle(cornerRadius: Theme.Tags.popupRadius))
    }

    private func row(_ title: String, index: Int) -> some View {
        let highlighted = suggestions.highlighted == index
        return HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "tag")
                .font(Theme.Tags.rowSymbol)
                .foregroundStyle(highlighted ? Color.white : Theme.Palette.secondary)
            Text(title)
                .font(Theme.Tags.rowFont)
                .foregroundStyle(highlighted ? Color.white : Theme.Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Theme.Tags.chipPadding)
        .frame(maxWidth: .infinity, minHeight: Theme.Tags.rowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Tags.rowRadius)
                .fill(highlighted ? Theme.Palette.accent : .clear))
        .contentShape(.rect)
        .onHover { if $0 { suggestions.highlighted = index } }
        .onTapGesture { suggestions.pick(row: index) }
    }
}
