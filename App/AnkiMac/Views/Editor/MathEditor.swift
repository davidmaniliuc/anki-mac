import AppKit
import FieldEditor
import SwiftUI

/// The TeX behind one MathJax atom, edited in a popover as desktop's
/// MathJax overlay: Inline or Block and Delete over the equation as it
/// renders, then its TeX. Return accepts, Shift-Return starts a new line.
struct MathEditorView: View {
    @Bindable var draft: MathDraft
    /// The number a new cloze takes, in a cloze note type's field; nil
    /// hides the cloze button, as desktop's overlay does.
    let clozeNumber: (() -> Int)?
    let commit: () -> Void
    let delete: () -> Void
    @FocusState private var focused: Bool
    @State private var selection: TextSelection?
    @State private var preview: NSImage?
    /// The preview is of older TeX that still doesn't render.
    @State private var previewIsStale = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.xxSmall) {
                QuietSegments(selection: $draft.display, choices: [false, true]) {
                    $0 ? Tr.editingMathjaxBlock : Tr.editingMathjaxInline
                }
                Spacer(minLength: Theme.Spacing.small)
                if clozeNumber != nil {
                    Button(action: cloze) { glyph("Cloze Deletion", "ellipsis.curlybraces") }
                        .buttonStyle(QuietButtonStyle(inset: 0))
                        .help("Cloze Deletion")
                }
                Button(action: delete) { glyph(Tr.actionsDelete, "trash") }
                    .buttonStyle(QuietButtonStyle(inset: 0))
                    .help(Tr.actionsDelete)
            }
            if !draft.tex.isEmpty, let preview {
                // The last equation that rendered, faded once the TeX hasn't
                // rendered for a moment, so a typo doesn't make it jump away.
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: preview.size.width, maxHeight: min(preview.size.height, Theme.Editor.mathPreviewMaxHeight))
                    .frame(maxWidth: .infinity, minHeight: Theme.Editor.mathPreviewMinHeight)
                    .opacity(previewIsStale ? 0.4 : 1)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $draft.tex, selection: $selection)
                .font(Theme.Editor.sourceFont)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: Theme.Editor.mathEditorMinHeight)
                .padding(Theme.Spacing.xSmall)
                .overlay(alignment: .topLeading) {
                    // Desktop's placeholder, in the place of the TeX.
                    if draft.tex.isEmpty {
                        Text(placeholder)
                            .font(Theme.Editor.sourceFont)
                            .foregroundStyle(Theme.Palette.tertiary)
                            .padding(Theme.Spacing.xSmall)
                            .padding(.leading, Theme.Editor.mathTextInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                // Code reads as a block, as a field's HTML does.
                .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius).fill(Theme.Palette.hover))
                .accessibilityLabel(draft.display ? Tr.editingMathjaxBlock : Tr.editingMathjaxInline)
                .accessibilityHint(placeholder)
                .onKeyPress(.return, phases: .down) { press in
                    // Return that ends an input method's composition stays with it.
                    guard !press.modifiers.contains(.shift), !composing else { return .ignored }
                    commit()
                    return .handled
                }
        }
        .padding(Theme.Spacing.medium)
        .frame(width: Theme.Editor.mathEditorWidth)
        .onAppear { focused = true }
        .task(id: draft.math) {
            guard !render() else { return }
            try? await Task.sleep(for: .seconds(Theme.Editor.mathStaleDelay))
            if !Task.isCancelled { previewIsStale = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: MathRenderer.didRender)) { _ in render() }
        // The equation is drawn in the text colour, which the appearance changes.
        .onChange(of: colorScheme) { render() }
    }

    private var placeholder: String {
        Tr.editingMathjaxPlaceholder(accept: "Return", newline: "Shift-Return")
    }

    /// Whether an input method is composing in the TeX.
    private var composing: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextInputClient)?.hasMarkedText() == true
    }

    private func glyph(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(Theme.Editor.buttonSymbol)
            .frame(width: Theme.Editor.buttonSize.width, height: Theme.Editor.buttonSize.height)
    }

    /// Whether the TeX as it stands has rendered.
    @discardableResult
    private func render() -> Bool {
        guard !draft.tex.isEmpty,
            let rendered = MathRenderer.shared.image(draft.math, fontSize: Theme.Editor.mathPreviewFontSize)
        else { return false }
        preview = rendered.image
        previewIsStale = false
        return true
    }

    /// Wraps the selected TeX in a cloze, as desktop's overlay does; with
    /// nothing selected, the cursor lands inside it.
    private func cloze() {
        guard let clozeNumber else { return }
        let tex = draft.tex
        var range = tex.endIndex..<tex.endIndex
        switch selection?.indices {
        case .selection(let selected): range = selected
        case .multiSelection(let ranges): range = ranges.ranges.first ?? range
        default: break
        }
        let number = max(clozeNumber(), FieldDocument.nextClozeNumber(in: [tex]))
        let front = "{{c\(number)::"
        let inner = String(tex[range])
        let start = tex.distance(from: tex.startIndex, to: range.lowerBound)
        draft.tex.replaceSubrange(range, with: front + inner + "}}")
        let caret = draft.tex.index(draft.tex.startIndex, offsetBy: start + front.count + inner.count)
        selection = TextSelection(insertionPoint: caret)
        focused = true
    }
}

/// What the math popover is editing, shared with the text view so that
/// closing the popover keeps it.
@Observable
final class MathDraft {
    var tex: String
    var display: Bool
    init(_ math: FieldMath) {
        tex = math.tex
        display = math.display
    }

    var math: FieldMath { FieldMath(tex: tex, display: display) }
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
        let draft = MathDraft(math)
        var committed = false
        let accept = { [weak self] in
            guard !committed else { return }
            committed = true
            // Clicking away keeps what was typed too, as desktop's overlay does.
            if draft.math != math { self?.replaceMath(at: index, with: draft.math) }
        }
        let clozeNumber: (() -> Int)? = editor?.isCloze == true ? { [weak self] in self?.editor?.nextClozeNumber ?? 1 } : nil
        let host = NSHostingController(
            rootView: MathEditorView(draft: draft, clozeNumber: clozeNumber) { [weak popover] in
                accept()
                popover?.close()
            } delete: { [weak self, weak popover] in
                committed = true
                self?.replaceMath(at: index, with: FieldMath(tex: "", display: math.display))
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
