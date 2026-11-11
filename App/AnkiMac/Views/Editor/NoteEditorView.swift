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
        VStack(spacing: 0) {
            FormatBar(editor: editor, cardLayout: cardLayout)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.small)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    ForEach(editor.fields) { field in
                        FieldRow(
                            field: field, editor: editor, sticky: sticky,
                            duplicate: duplicateField == field.index)
                    }
                }
                .padding(Theme.Spacing.medium)
            }
        }
    }
}

private struct FieldRow: View {
    let field: EditorField
    let editor: NoteEditorModel
    let sticky: (isOn: (Int) -> Bool, toggle: (Int) -> Void)?
    let duplicate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack {
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
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(field.collapsed ? Tr.editingExpandField : Tr.editingCollapseField)
                .accessibilityLabel(field.name)
                .accessibilityValue(field.collapsed ? Tr.editingExpand : Tr.editingCollapse)
                Spacer()
                if let sticky {
                    Toggle(isOn: Binding { sticky.isOn(field.index) } set: { _ in sticky.toggle(field.index) }) {
                        Image(systemName: sticky.isOn(field.index) ? "pin.fill" : "pin")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help(Tr.editingToggleSticky)
                    .accessibilityLabel("\(Tr.editingToggleSticky): \(field.name)")
                }
                if !field.plainText {
                    Toggle(isOn: Binding { field.showingSource } set: { _ in
                        field.toggleSource(mediaFolder: editor.mediaFolder)
                    }) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help("Show HTML (\u{2318}\u{21E7}X)")
                    .accessibilityLabel("Show HTML for \(field.name)")
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
                .background(
                    duplicate ? Theme.Editor.duplicateBackground : Theme.Editor.fieldBackground,
                    in: RoundedRectangle(cornerRadius: Theme.Editor.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Editor.cornerRadius)
                        .strokeBorder(Theme.Editor.fieldBorder))
            }
        }
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
        FlowLayout(spacing: Theme.Spacing.small) {
            if let cardLayout {
                Button("\(Tr.editingCards)…", action: cardLayout)
                    .keyboardShortcut("l")
                    .help("\(Tr.editingCustomizeCardTemplates) (\u{2318}L)")
            }
            ControlGroup {
                formatButton(.bold, "bold", "Bold", "\u{2318}B")
                formatButton(.italic, "italic", "Italic", "\u{2318}I")
                formatButton(.underline, "underline", "Underline", "\u{2318}U")
                formatButton(.strikethrough, "strikethrough", "Strikethrough", nil)
            }
            ControlGroup {
                formatButton(.superscript, "textformat.superscript", "Superscript", "\u{2318}\u{21E7}=")
                formatButton(.subscript, "textformat.subscript", "Subscript", "\u{2318}=")
            }
            colorControl(.text, "character", "Text Color", "F7")
            colorControl(.highlight, "highlighter", "Highlight Color", nil)
            Button {
                send(#selector(FieldTextView.removeFieldFormatting(_:)))
            } label: {
                Label("Remove Formatting", systemImage: "eraser")
            }
            .help("Remove Formatting (\u{2318}R)")
            Button {
                send(#selector(FieldTextView.insertCloze(_:)))
            } label: {
                Label("Cloze Deletion", systemImage: "ellipsis.curlybraces")
            }
            .help("Cloze Deletion (\u{2318}\u{21E7}C)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .labelStyle(.iconOnly)
        .controlSize(.small)
    }

    private func formatButton(_ format: InlineFormat, _ symbol: String, _ title: String, _ shortcut: String?) -> some View {
        Button {
            send(#selector(FieldTextView.toggleFieldFormat(_:)), FormatCommand(format))
        } label: {
            Label(title, systemImage: symbol)
        }
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }

    /// Desktop's colour button and its picker: the button applies the last
    /// colour, picking one applies it too.
    private func colorControl(_ kind: ColorKind, _ symbol: String, _ title: String, _ shortcut: String?) -> some View {
        let colors = EditorColors.shared
        return HStack(spacing: Theme.Spacing.xxSmall) {
            Button {
                send(#selector(FieldTextView.applyFieldColor(_:)), ColorCommand(kind))
            } label: {
                Label(title, systemImage: symbol)
            }
            .help(shortcut.map { "\(title) (\($0))" } ?? title)
            ColorPicker(title, selection: Binding {
                colors.color(kind)
            } set: { color in
                if kind == .text { colors.text = color } else { colors.highlight = color }
                send(#selector(FieldTextView.applyFieldColor(_:)), ColorCommand(kind))
            }, supportsOpacity: false)
            .labelsHidden()
            .controlSize(.mini)
            .help("Change Color")
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

/// "MathJax inline" as a menu item's title: "Inline".
private func sentenceCase(_ title: String) -> String {
    let word = title.split(separator: " ").last.map(String.init) ?? title
    return word.prefix(1).uppercased() + word.dropFirst()
}

func applyColor(_ kind: ColorKind) {
    NSApp.sendAction(#selector(FieldTextView.applyFieldColor(_:)), to: nil, from: ColorCommand(kind))
}

/// Lays its views out in rows, starting a new row when the next one
/// doesn't fit.
private struct FlowLayout: Layout {
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
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!)), modifiers: [])
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
            Menu("MathJax") {
                Button(sentenceCase(Tr.editingMathjaxInline)) { send(#selector(FieldTextView.insertMathInline(_:))) }
                Button(sentenceCase(Tr.editingMathjaxBlock)) { send(#selector(FieldTextView.insertMathBlock(_:))) }
                Button(sentenceCase(Tr.editingMathjaxChemistry)) { send(#selector(FieldTextView.insertMathChemistry(_:))) }
            }
            Divider()
            Button("Show HTML") { send(#selector(FieldTextView.toggleHTMLSource(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
        }
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
