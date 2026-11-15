import SwiftUI

/// The editor pane beside the browser's table.
struct BrowserEditorView: View {
    @Bindable var model: BrowserEditorModel
    let browser: BrowserModel
    let chrome: BrowserChrome
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
                    // The bar's hairline carries on the one under the column titles.
                    NoteEditorView(
                        editor: model.editor, cardLayout: cardLayout, barHeight: Theme.Browser.headerHeight - 1)
                    Theme.Palette.hairline.frame(height: 1)
                    TagRow(tags: $model.tags, complete: model.completeTags)
                        .padding(Theme.Spacing.medium)
                }
            }
        }
        // The pane runs under the window's band; the editor starts below it.
        .padding(.top, Theme.Browser.chromeHeight)
        .background(Theme.Palette.canvas, ignoresSafeAreaEdges: .all)
        // The band's end is the window's top corner, where the main window
        // keeps its buttons.
        .overlay(alignment: .topTrailing) {
            BrowserHeaderActions(model: browser, chrome: chrome, inEditor: true)
                .frame(height: Theme.Browser.chromeHeight)
                .padding(.trailing, Theme.Spacing.small)
        }
    }
}
