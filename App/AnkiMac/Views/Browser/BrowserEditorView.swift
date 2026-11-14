import SwiftUI

/// The editor pane beside the browser's table.
struct BrowserEditorView: View {
    @Bindable var model: BrowserEditorModel
    let cardLayout: () -> Void

    var body: some View {
        Group {
            if model.noteID == nil {
                ContentUnavailableView(
                    model.emptyTitle, systemImage: "square.and.pencil",
                    description: Text("Select one card or note to edit it."))
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    NoteEditorView(editor: model.editor, cardLayout: cardLayout)
                    Theme.Palette.hairline.frame(height: 1)
                    TagRow(tags: $model.tags, complete: model.completeTags)
                        .padding(Theme.Spacing.medium)
                }
            }
        }
        // The pane runs under the window's band, which the table's side
        // holds; the editor starts below it.
        .padding(.top, Theme.Browser.chromeHeight)
        .background(Theme.Palette.canvas, ignoresSafeAreaEdges: .all)
    }
}
