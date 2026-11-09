import AppKit
import FieldEditor
import SwiftUI

/// A note's fields, one editor each, under a formatting bar: the editor
/// shared by Add Cards and the browser.
struct NoteEditorView: View {
    let editor: NoteEditorModel

    var body: some View {
        VStack(spacing: 0) {
            FormatBar()
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.small)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    ForEach(editor.fields) { field in
                        FieldRow(field: field, editor: editor)
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

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack {
                Text(field.name).font(Theme.Editor.labelFont).foregroundStyle(.secondary)
                Spacer()
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
                }
            }
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
            .background(Theme.Editor.fieldBackground, in: RoundedRectangle(cornerRadius: Theme.Editor.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Editor.cornerRadius)
                    .strokeBorder(Theme.Editor.fieldBorder))
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
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: FieldTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? Theme.Editor.minWidth
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
    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            ControlGroup {
                formatButton(.bold, "bold", "Bold (\u{2318}B)")
                formatButton(.italic, "italic", "Italic (\u{2318}I)")
                formatButton(.underline, "underline", "Underline (\u{2318}U)")
                formatButton(.strikethrough, "strikethrough", "Strikethrough")
            }
            ControlGroup {
                formatButton(.superscript, "textformat.superscript", "Superscript (\u{2318}\u{21E7}=)")
                formatButton(.subscript, "textformat.subscript", "Subscript (\u{2318}=)")
            }
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
            Spacer()
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
    }

    private func formatButton(_ format: InlineFormat, _ symbol: String, _ help: String) -> some View {
        Button {
            NSApp.sendAction(#selector(FieldTextView.toggleFieldFormat(_:)), to: nil, from: FormatCommand(format))
        } label: {
            Label(help, systemImage: symbol)
        }
        .help(help)
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
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
            Button("Remove Formatting") { send(#selector(FieldTextView.removeFieldFormatting(_:))) }
                .keyboardShortcut("r")
            Divider()
            Button("Cloze Deletion") { send(#selector(FieldTextView.insertCloze(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Cloze Deletion, Same Number") { send(#selector(FieldTextView.insertClozeSameNumber(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
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
