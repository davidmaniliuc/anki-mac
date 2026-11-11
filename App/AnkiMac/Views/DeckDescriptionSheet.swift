import SwiftUI

/// Desktop's Description dialog: the deck's text, and whether it is Markdown.
struct DeckDescriptionSheet: View {
    @State var edit: DeckDescription
    let cancel: () -> Void
    let save: (DeckDescription) -> Void

    init(edit: DeckDescription, cancel: @escaping () -> Void, save: @escaping (DeckDescription) -> Void) {
        _edit = State(initialValue: edit)
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.schedulingDescription).font(.headline)
            Toggle(Tr.deckConfigDescriptionNewHandling2, isOn: $edit.markdown)
                .help(Tr.deckConfigDescriptionNewHandlingHint)
            CodeTextEditor(text: $edit.text)
                .border(Theme.Editor.fieldBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK") { save(edit) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Overview.descriptionSheetSize.width, height: Theme.Overview.descriptionSheetSize.height)
    }
}
