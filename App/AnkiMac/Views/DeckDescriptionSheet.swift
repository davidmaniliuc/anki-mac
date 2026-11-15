import SwiftUI

/// Desktop's Description dialog, drawn as Deck Options' settings: the
/// deck's path over "Description", whether the text is Markdown, then the
/// text as an unboxed block, as the editor's HTML source.
struct DeckDescriptionSheet: View {
    @State var edit: DeckDescription
    /// "Spanish::Verbs", shown as the eyebrow.
    let deckName: String
    let cancel: () -> Void
    let save: (DeckDescription) -> Void
    @FocusState private var textFocused: Bool

    init(
        edit: DeckDescription, deckName: String, cancel: @escaping () -> Void,
        save: @escaping (DeckDescription) -> Void
    ) {
        _edit = State(initialValue: edit)
        self.deckName = deckName
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        SettingsSheet(
            eyebrow: deckName.replacingOccurrences(of: "::", with: " \u{203A} "), title: Tr.schedulingDescription,
            width: Theme.DeckDescription.width
        ) {
            // The text belongs to the switch above it, so it follows the row
            // closely rather than a section's gap down.
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                OptionSection {
                    // Upstream's three-line hint is the title's help tag, as a
                    // Deck Options setting's tooltip is, so the text leads.
                    OptionRow(
                        title: Tr.deckConfigDescriptionNewHandling2, help: Tr.deckConfigDescriptionNewHandlingHint,
                        revertible: false
                    ) {
                        SwitchControl(title: Tr.deckConfigDescriptionNewHandling2, isOn: $edit.markdown)
                    }
                }
                TextEditor(text: $edit.text)
                    .font(Theme.DeckOptions.rowFont)
                    .scrollContentBackground(.hidden)
                    .focused($textFocused)
                    .padding(Theme.DeckOptions.fieldPadding)
                    .frame(height: Theme.DeckDescription.textHeight)
                    .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius).fill(Theme.Palette.hover))
                    .accessibilityLabel(Tr.schedulingDescription)
                    .onAppear { textFocused = true }
            }
        } footer: {
            Spacer()
            // Return starts a new line in the text, so Save takes Command-Return.
            DialogButtons(
                action: Tr.actionsSave, key: "\u{2318}\u{21A9}", shortcut: KeyboardShortcut(.return, modifiers: .command),
                cancel: cancel, submit: { save(edit) })
        }
    }
}
