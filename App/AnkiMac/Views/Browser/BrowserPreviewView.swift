import SwiftUI

/// The previewer's window content: the card, and desktop's button row
/// under it (Replay Audio, Back Side Only, and the step buttons).
struct BrowserPreviewView: View {
    let model: BrowserPreviewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if let view = model.web.webView {
                CardWebView(webView: view)
                    .overlay(alignment: .top) {
                        CardIndicators(flag: model.flag, isMarked: model.isMarked)
                    }
            }
            HStack(spacing: Theme.Spacing.small) {
                Button(Tr.actionsReplayAudio) { model.replayAudio() }
                    .help(Tr.actionsShortcutKey(val: "R"))
                Toggle("Back Side Only", isOn: Binding { model.backSideOnly } set: { model.setBackSideOnly($0) })
                    .help(Tr.actionsShortcutKey(val: "B"))
                Spacer()
                Button { model.back() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack)
                    .help("Shortcut key: Left arrow")
                Button { model.forward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .help("Shortcut key: Right arrow or Enter")
            }
            .padding(Theme.Spacing.small)
        }
        .onChange(of: colorScheme, initial: true) { model.web.setNightMode(colorScheme == .dark) }
    }
}
