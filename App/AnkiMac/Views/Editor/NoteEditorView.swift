import AppKit
import FieldEditor
import SwiftUI

/// A note's fields, one editor each, under a formatting bar: the editor
/// shared by Add Cards and the browser.
struct NoteEditorView: View {
    let editor: NoteEditorModel
    /// Add mode's pins: which fields keep their content after adding.
    var sticky: (isOn: (Int) -> Bool, toggle: (Int) -> Void)?
    /// The field shown as a duplicate of an existing note's.
    var duplicateField: Int?
    /// Opens the card layout editor for this note; nil hides the Cards button.
    var cardLayout: (() -> Void)?

    var body: some View {
        if let occlusion = editor.occlusion {
            // Desktop's Mask and Note tabs: the masks, or the remaining fields.
            VStack(spacing: 0) {
                QuietSegments(
                    selection: Binding { occlusion.tab } set: {
                        editor.commitPendingEdits()
                        occlusion.tab = $0
                    }, choices: [.masks, .note]
                ) {
                    switch $0 {
                    case .masks: Tr.notetypesOcclusionMask
                    case .note: Tr.notetypesOcclusionNote
                    }
                }
                .accessibilityLabel(Tr.notetypesImageOcclusionName)
                .padding(.vertical, Theme.Spacing.small)
                Theme.Palette.hairline.frame(height: 1)
                switch occlusion.tab {
                case .masks: ImageOcclusionView(editor: occlusion)
                case .note: fieldEditors(hiding: occlusion.hiddenFields)
                }
            }
        } else {
            fieldEditors(hiding: [])
        }
    }

    private func fieldEditors(hiding hidden: Set<Int>) -> some View {
        VStack(spacing: 0) {
            FormatBar(editor: editor, cardLayout: cardLayout)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.small)
            Theme.Palette.hairline.frame(height: 1)
            ScrollView {
                let shown = editor.fields.filter { !hidden.contains($0.index) }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { field in
                        FieldRow(
                            field: field, editor: editor, sticky: sticky,
                            duplicate: duplicateField == field.index)
                        if field.id != shown.last?.id { Theme.Palette.hairline.frame(height: 1) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.medium)
            }
        }
    }
}

private struct FieldRow: View {
    let field: EditorField
    let editor: NoteEditorModel
    let sticky: (isOn: (Int) -> Bool, toggle: (Int) -> Void)?
    let duplicate: Bool
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack(spacing: Theme.Spacing.xxSmall) {
                Button {
                    editor.toggleCollapsed(field)
                } label: {
                    Label {
                        Text(field.name)
                    } icon: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(field.collapsed ? 0 : 90))
                            .imageScale(.small)
                    }
                    .font(Theme.Editor.labelFont)
                    .foregroundStyle(editor.focusedField == field.index ? Theme.Palette.text : Theme.Palette.secondary)
                }
                .buttonStyle(.plain)
                .help(field.collapsed ? Tr.editingExpandField : Tr.editingCollapseField)
                .accessibilityLabel(field.name)
                .accessibilityValue(field.collapsed ? Tr.editingExpand : Tr.editingCollapse)
                Spacer()
                if let sticky {
                    let pinned = sticky.isOn(field.index)
                    Button {
                        sticky.toggle(field.index)
                    } label: {
                        toggleGlyph(pinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(QuietButtonStyle(selected: pinned, inset: 0))
                    .help(Tr.editingToggleSticky)
                    .accessibilityLabel("\(Tr.editingToggleSticky): \(field.name)")
                    .accessibilityAddTraits(pinned ? .isSelected : [])
                }
                if !field.plainText {
                    Button {
                        field.toggleSource(mediaFolder: editor.mediaFolder)
                    } label: {
                        toggleGlyph("chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(QuietButtonStyle(selected: field.showingSource, inset: 0))
                    .help("Show HTML (\u{2318}\u{21E7}X)")
                    .accessibilityLabel("Show HTML for \(field.name)")
                    .accessibilityAddTraits(field.showingSource ? .isSelected : [])
                    // Hidden on a collapsed field, keeping its place so the pins line up.
                    .opacity(field.collapsed ? 0 : 1)
                    .disabled(field.collapsed)
                    .accessibilityHidden(field.collapsed)
                }
            }
            if !field.collapsed {
                Group {
                    if field.showingSource {
                        TextEditor(text: Binding { field.source } set: {
                            field.setSource($0)
                            editor.edited()
                        })
                        .font(Theme.Editor.sourceFont)
                        .autocorrectionDisabled()
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: Theme.Editor.sourceMinHeight)
                        .padding(Theme.Spacing.xSmall)
                    } else {
                        FieldTextEditor(field: field, editor: editor)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(field.name)
                    }
                }
                // Code reads as a block, so its wash stays on.
                .background(shape.fill(
                    duplicate ? Theme.Editor.duplicateBackground
                        : hovered || field.showingSource ? Theme.Palette.hover : .clear))
                .onHover { hovered = $0 }
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private func toggleGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(Theme.Editor.buttonSymbol)
            .frame(width: Theme.Editor.buttonSize.width, height: Theme.Editor.buttonSize.height)
    }
}

/// The AppKit text view in SwiftUI, as tall as its text.
private struct FieldTextEditor: NSViewRepresentable {
    let field: EditorField
    let editor: NoteEditorModel

    func makeNSView(context: Context) -> FieldTextView {
        let view = FieldTextView.make()
        view.editor = editor
        view.show(field)
        return view
    }

    func updateNSView(_ view: FieldTextView, context: Context) {
        view.editor = editor
        view.show(field)
        if editor.focusRequest == field.index {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
                editor.focusRequest = nil
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: FieldTextView, context: Context) -> CGSize? {
        // Asked for an ideal size, claim little width: the row decides.
        let width = proposal.width ?? Theme.Editor.minFieldWidth
        return CGSize(width: width, height: view.height(forWidth: width))
    }
}

extension FieldTextView {
    /// The height the text needs at a width, never less than one line.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return Theme.Editor.minFieldHeight }
        let inset = textContainerInset
        textContainer.size = NSSize(width: max(1, width - inset.width * 2), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height
        return max(Theme.Editor.minFieldHeight, ceil(used + inset.height * 2))
    }
}

/// Bold, italic and the rest for the focused field, as desktop's editor
/// toolbar. The same commands are in the Format menu.
struct FormatBar: View {
    let editor: NoteEditorModel
    let cardLayout: (() -> Void)?

    var body: some View {
        // Wraps onto more lines in a narrow pane rather than clipping buttons.
        FlowLayout(spacing: Theme.Spacing.xxSmall) {
            if let cardLayout {
                group {
                    Button(action: cardLayout) {
                        Text("\(Tr.editingCards)…")
                            .font(Theme.Fonts.chip)
                            .frame(height: Theme.Editor.buttonSize.height)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut("l")
                    .help("\(Tr.editingCustomizeCardTemplates) (\u{2318}L)")
                }
            }
            group {
                formatButton(.bold, "bold", "Bold", "\u{2318}B")
                formatButton(.italic, "italic", "Italic", "\u{2318}I")
                formatButton(.underline, "underline", "Underline", "\u{2318}U")
                formatButton(.strikethrough, "strikethrough", "Strikethrough", nil)
            }
            group {
                formatButton(.superscript, "textformat.superscript", "Superscript", "\u{2318}\u{21E7}=")
                formatButton(.subscript, "textformat.subscript", "Subscript", "\u{2318}=")
            }
            group {
                colorControl(.text, "character", "Text Color", "F7")
                colorControl(.highlight, "highlighter", "Highlight Color", nil)
            }
            group {
                Button {
                    send(#selector(FieldTextView.removeFieldFormatting(_:)))
                } label: {
                    glyph("Remove Formatting", "eraser")
                }
                .buttonStyle(QuietButtonStyle(inset: 0))
                .help("Remove Formatting (\u{2318}R)")
            }
            group(divided: false) {
                Button {
                    send(#selector(FieldTextView.insertCloze(_:)))
                } label: {
                    glyph("Cloze Deletion", "ellipsis.curlybraces")
                }
                .buttonStyle(QuietButtonStyle(inset: 0))
                .help("Cloze Deletion (\u{2318}\u{21E7}C)")
                Button {
                    send(#selector(FieldTextView.attachMedia(_:)))
                } label: {
                    glyph(Tr.editingAttachPicturesaudiovideo, "paperclip")
                }
                .buttonStyle(QuietButtonStyle(inset: 0))
                .help("\(Tr.editingAttachPicturesaudiovideo) (F3)")
                Button {
                    send(#selector(FieldTextView.recordAudio(_:)))
                } label: {
                    glyph(Tr.editingRecordAudio, "mic")
                }
                .buttonStyle(QuietButtonStyle(inset: 0))
                .help("\(Tr.editingRecordAudio) (F5)")
                Menu {
                    EquationButtons(send: { send($0) })
                } label: {
                    glyph(Tr.editingEquations, "function")
                }
                .menuStyle(.button)
                .buttonStyle(QuietButtonStyle(inset: 0))
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Tr.editingEquations)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .labelStyle(.iconOnly)
    }

    /// Buttons that belong together, then a hairline; the line trails the
    /// group so a wrapped row never starts with one.
    private func group<Content: View>(divided: Bool = true, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.xxSmall) {
            content()
            if divided {
                Theme.Palette.hairline
                    .frame(width: 1, height: Theme.Editor.dividerHeight)
                    .padding(.horizontal, Theme.Spacing.xSmall)
            }
        }
    }

    private func glyph(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(Theme.Editor.buttonSymbol)
            .frame(width: Theme.Editor.buttonSize.width, height: Theme.Editor.buttonSize.height)
    }

    private func formatButton(_ format: InlineFormat, _ symbol: String, _ title: String, _ shortcut: String?) -> some View {
        Button {
            send(#selector(FieldTextView.toggleFieldFormat(_:)), FormatCommand(format))
        } label: {
            glyph(title, symbol)
        }
        .buttonStyle(QuietButtonStyle(inset: 0))
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }

    /// Desktop's colour button and its picker: the button applies the last
    /// colour, which shows in a bar under its glyph; the chevron opens the
    /// colour panel, and picking there applies the colour too.
    private func colorControl(_ kind: ColorKind, _ symbol: String, _ title: String, _ shortcut: String?) -> some View {
        let apply = { send(#selector(FieldTextView.applyFieldColor(_:)), ColorCommand(kind)) }
        return HStack(spacing: 0) {
            Button(action: apply) {
                glyph(title, symbol)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: Theme.Editor.swatchSize.height / 2)
                            .fill(EditorColors.shared.color(kind))
                            .frame(width: Theme.Editor.swatchSize.width, height: Theme.Editor.swatchSize.height)
                            .padding(.bottom, Theme.Spacing.xxSmall)
                    }
            }
            .buttonStyle(QuietButtonStyle(inset: 0))
            .help(shortcut.map { "\(title) (\($0))" } ?? title)
            Button {
                EditorColorPanel.shared.show(kind, apply: apply)
            } label: {
                Image(systemName: "chevron.down")
                    .font(Theme.Editor.chevronSymbol)
                    .frame(width: Theme.Editor.chevronWidth, height: Theme.Editor.buttonSize.height)
            }
            .buttonStyle(QuietButtonStyle(inset: 0))
            .help("Change Color")
            .accessibilityLabel(title)
        }
    }

    /// Sends to this editor's last focused field, not the key window's.
    private func send(_ action: Selector, _ sender: Any? = nil) {
        guard let field = editor.focusedView else {
            NSApp.sendAction(action, to: nil, from: sender)
            return
        }
        field.window?.makeKeyAndOrderFront(nil)
        field.window?.makeFirstResponder(field)
        NSApp.sendAction(action, to: field, from: sender)
    }
}

func applyColor(_ kind: ColorKind) {
    NSApp.sendAction(#selector(FieldTextView.applyFieldColor(_:)), to: nil, from: ColorCommand(kind))
}

/// Lays its views out in rows, starting a new row when the next one
/// doesn't fit.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// The Format menu: the editor's commands, for whichever field has focus.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            format(.bold, "Bold", "b")
            format(.italic, "Italic", "i")
            format(.underline, "Underline", "u")
            format(.strikethrough, "Strikethrough", nil)
            format(.superscript, "Superscript", "=", [.command, .shift])
            format(.subscript, "Subscript", "=")
            Divider()
            Button("Text Color") { applyColor(.text) }
                .keyboardShortcut(functionKey(NSF7FunctionKey), modifiers: [])
            Button("Highlight Color") { applyColor(.highlight) }
            Divider()
            Button("Remove Formatting") { send(#selector(FieldTextView.removeFieldFormatting(_:))) }
                .keyboardShortcut("r")
            Divider()
            Button("Cloze Deletion") { send(#selector(FieldTextView.insertCloze(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Cloze Deletion, Same Number") { send(#selector(FieldTextView.insertClozeSameNumber(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            Divider()
            Button(Tr.editingAttachPicturesaudiovideo) { send(#selector(FieldTextView.attachMedia(_:))) }
                .keyboardShortcut(functionKey(NSF3FunctionKey), modifiers: [])
            Button(Tr.editingRecordAudio) { send(#selector(FieldTextView.recordAudio(_:))) }
                .keyboardShortcut(functionKey(NSF5FunctionKey), modifiers: [])
            Divider()
            Menu(Tr.editingEquations) {
                EquationButtons(send: { send($0) })
            }
            Divider()
            Button("Show HTML") { send(#selector(FieldTextView.toggleHTMLSource(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
        }
    }

    private func functionKey(_ code: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(code)!))
    }

    private func format(
        _ format: InlineFormat, _ title: String, _ key: Character?, _ modifiers: EventModifiers = .command
    ) -> some View {
        Button(title) {
            NSApp.sendAction(#selector(FieldTextView.toggleFieldFormat(_:)), to: nil, from: FormatCommand(format))
        }
        .keyboardShortcut(key.map { KeyboardShortcut(KeyEquivalent($0), modifiers: modifiers) })
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
