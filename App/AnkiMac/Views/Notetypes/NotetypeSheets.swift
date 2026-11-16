import AnkiKit
import AppKit
import SwiftUI

/// Desktop's one-line `getText` prompt, drawn as the study prompts: the
/// question as a Headline, desktop's label as a row's title with the quiet
/// box at its trailing edge, then what's wrong with the text, checked as
/// it is typed, beside Cancel and the action.
struct TextPromptSheet: View {
    let title: String
    let label: String
    let action: String
    /// A position takes a small box in the rounded face; a name a wider one.
    var number = false
    /// Why the text can't be used; nil when it can.
    var problem: (String) -> String? = { _ in nil }
    let submit: (String) -> Void
    /// Takes the sheet down when AppKit presented it, out of SwiftUI's reach.
    var close: (() -> Void)?
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(
        title: String, label: String, action: String, initial: String, number: Bool = false,
        problem: @escaping (String) -> String? = { _ in nil }, close: (() -> Void)? = nil,
        submit: @escaping (String) -> Void
    ) {
        self.title = title
        self.label = label
        self.action = action
        self.number = number
        self.problem = problem
        self.close = close
        self.submit = submit
        _text = State(initialValue: initial)
    }

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let problem = trimmed.isEmpty ? nil : problem(trimmed)
        SettingsSheet(title: title, width: Theme.Notetypes.promptWidth) {
            OptionSection {
                OptionRow(title: label, revertible: false) {
                    OptionTextField(
                        text: $text, font: number ? Theme.DeckOptions.figures : Theme.DeckOptions.rowFont,
                        focusOnAppear: true)
                    .multilineTextAlignment(number ? .trailing : .leading)
                    .frame(width: number ? Theme.DeckOptions.numberFieldWidth : Theme.Notetypes.promptFieldWidth)
                }
            }
        } footer: {
            if let problem {
                OptionWarning(text: problem, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(action: action, disabled: trimmed.isEmpty || problem != nil, cancel: finish) {
                submit(trimmed)
                finish()
            }
        }
    }

    private func finish() {
        if let close { close() } else { dismiss() }
    }
}

/// A menu item's words without desktop's trailing "...", for a sheet's
/// title: "Rename Card Type...", once open, is "Rename Card Type".
func sheetTitle(_ item: String) -> String {
    var title = item
    while title.hasSuffix(".") || title.hasSuffix("…") { title.removeLast() }
    return title
}

/// Desktop's label as a row's title, as a Mac settings row reads: "Font:"
/// is "Font", "New position (1...3):" is "New position (1...3)", and
/// "<b>Find</b>:" is "Find".
func rowTitle(_ label: String) -> String {
    label.replacing(/<[^>]+>/, with: "")
        .trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
}

/// The installed font families as a quiet menu's choices, with the one
/// set first when it isn't installed, so it still shows.
func fontFamilies(keeping current: String) -> [(String, String)] {
    current.isEmpty || installedFontFamilies.contains(current)
        ? installedFontChoices : [(current, current)] + installedFontChoices
}

/// Asked of the system once, rather than on each keystroke in a sheet
/// showing the menu: a few hundred names.
private let installedFontFamilies = Set(NSFontManager.shared.availableFontFamilies)
private let installedFontChoices = NSFontManager.shared.availableFontFamilies.map { ($0, $0) }

/// Desktop's note type Options, drawn as Deck Options' settings: the LaTeX
/// header and footer as code, each an unboxed block under its eyebrow, as
/// the editor's HTML source, then SVG output as a switch.
struct NotetypeOptionsSheet: View {
    @State private var notetype: Anki_Notetypes_Notetype
    let save: (Anki_Notetypes_Notetype) -> Void
    @Environment(\.dismiss) private var dismiss

    init(notetype: Anki_Notetypes_Notetype, save: @escaping (Anki_Notetypes_Notetype) -> Void) {
        _notetype = State(initialValue: notetype)
        self.save = save
    }

    var body: some View {
        SettingsSheet(title: Tr.actionsOptionsFor(val: notetype.name), width: Theme.Notetypes.optionsWidth) {
            latex(Tr.notetypesHeader, text: $notetype.config.latexPre)
            latex(Tr.notetypesFooter, text: $notetype.config.latexPost)
            OptionSection {
                OptionRow(title: Tr.notetypesCreateScalableImagesWithDvisvgm, revertible: false) {
                    SwitchControl(title: Tr.notetypesCreateScalableImagesWithDvisvgm, isOn: $notetype.config.latexSvg)
                }
            }
        } footer: {
            Spacer()
            // Return starts a new line in the code, so Save takes Command-Return.
            DialogButtons(
                action: Tr.actionsSave, key: "\u{2318}\u{21A9}", shortcut: KeyboardShortcut(.return, modifiers: .command),
                cancel: { dismiss() }
            ) {
                save(notetype)
                dismiss()
            }
        }
    }

    private func latex(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Eyebrow(title).accessibilityAddTraits(.isHeader)
            CodeBlock(text: text, label: title)
                .frame(height: Theme.Notetypes.latexHeight)
        }
    }
}

/// Code as an unboxed block with the hover wash always on, as the editor's
/// HTML source: no smart quotes or dashes, which would break it.
struct CodeBlock: View {
    @Binding var text: String
    /// What VoiceOver calls the text view.
    let label: String

    var body: some View {
        CodeTextEditor(text: $text, label: label)
            .padding(Theme.Spacing.xSmall)
            .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius).fill(Theme.Palette.hover))
    }
}
