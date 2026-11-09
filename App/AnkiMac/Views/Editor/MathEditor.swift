import AppKit
import FieldEditor
import SwiftUI

/// The TeX behind one MathJax atom, edited in a popover as desktop's
/// MathJax overlay: Return accepts, Shift-Return starts a new line.
struct MathEditorView: View {
    @Bindable var draft: MathDraft
    let commit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            TextEditor(text: $draft.tex)
                .font(Theme.Editor.sourceFont)
                .autocorrectionDisabled()
                .focused($focused)
                .frame(minHeight: Theme.Editor.mathEditorMinHeight)
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    commit()
                    return .handled
                }
            Text(Tr.editingMathjaxPlaceholder(accept: "Return", newline: "Shift-Return"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.medium)
        .frame(width: Theme.Editor.mathEditorWidth)
        .onAppear { focused = true }
    }
}

/// What the math popover is editing, shared with the text view so that
/// closing the popover keeps it.
@Observable
final class MathDraft {
    var tex: String
    init(_ tex: String) { self.tex = tex }
}

extension FieldTextView: NSPopoverDelegate {
    /// Opens the editor for the MathJax atom at a character.
    func editMath(at index: Int) {
        guard let storage = textStorage, index < storage.length,
            let math = storage.attribute(.fieldMath, at: index, effectiveRange: nil) as? FieldMath,
            let layoutManager, let textContainer
        else { return }
        mathPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let draft = MathDraft(math.tex)
        var committed = false
        let accept = { [weak self] in
            guard !committed else { return }
            committed = true
            // Clicking away keeps what was typed too, as desktop's overlay does.
            if draft.tex != math.tex { self?.replaceMath(at: index, with: FieldMath(tex: draft.tex, display: math.display)) }
        }
        let host = NSHostingController(rootView: MathEditorView(draft: draft) { [weak popover] in
            accept()
            popover?.close()
        })
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        mathPopover = popover
        mathPendingCommit = accept
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        mathPendingCommit?()
        mathPendingCommit = nil
        mathPopover = nil
    }

    /// Puts new TeX in place of an atom; empty TeX removes it.
    private func replaceMath(at index: Int, with math: FieldMath) {
        guard let storage = textStorage, index < storage.length, storage.attribute(.fieldMath, at: index, effectiveRange: nil) != nil
        else { return }
        let range = NSRange(location: index, length: 1)
        let stack = (storage.attribute(.fieldStack, at: index, effectiveRange: nil) as? [Int]) ?? []
        let replacement = math.tex.isEmpty ? NSAttributedString() : field.document.fragment(html: math.html, base: stack)
        guard shouldChangeText(in: range, replacementString: replacement.string) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: index + replacement.length, length: 0))
    }

    /// Format › MathJax: the selection's text becomes TeX in a new atom,
    /// and its editor opens.
    func insertMath(display: Bool, chemistry: Bool) {
        let range = selectedRange()
        guard let storage = textStorage else { return }
        let selected = storage.attributedSubstring(from: range).string
        let tex = chemistry ? "\\ce{\(selected)}" : selected
        let stack = (typingAttributes[.fieldStack] as? [Int]) ?? []
        let atom = field.document.fragment(html: FieldMath(tex: tex, display: display).html, base: stack)
        guard shouldChangeText(in: range, replacementString: atom.string) else { return }
        storage.replaceCharacters(in: range, with: atom)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + atom.length, length: 0))
        editMath(at: range.location)
    }

    @objc func insertMathInline(_ sender: Any?) { insertMath(display: false, chemistry: false) }
    @objc func insertMathBlock(_ sender: Any?) { insertMath(display: true, chemistry: false) }
    @objc func insertMathChemistry(_ sender: Any?) { insertMath(display: false, chemistry: true) }
}
