import SwiftUI

/// The editor pane beside the browser's table.
struct BrowserEditorView: View {
    @Bindable var model: BrowserEditorModel
    let cardLayout: () -> Void

    var body: some View {
        if model.noteID == nil {
            ContentUnavailableView(
                "No Note Selected", systemImage: "square.and.pencil",
                description: Text("Select one card or note to edit it."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                NoteEditorView(editor: model.editor, cardLayout: cardLayout)
                Divider()
                TagField(tags: $model.tags, complete: model.completeTags)
                    .padding(Theme.Spacing.medium)
            }
        }
    }
}
