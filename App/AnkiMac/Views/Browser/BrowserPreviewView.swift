import SwiftUI

/// The previewer's window content: desktop's controls in the band under the
/// traffic lights, as Add's, then the card on the canvas.
struct BrowserPreviewView: View {
    let model: BrowserPreviewModel
    let chrome: BandChrome
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            band
            if let view = model.web.webView {
                CardWebView(webView: view)
                    .overlay(alignment: .top) {
                        CardIndicators(flag: model.flag, isMarked: model.isMarked)
                    }
            }
        }
        .background(Theme.Palette.canvas)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onChange(of: colorScheme, initial: true) { model.web.setNightMode(colorScheme == .dark) }
    }

    /// Back Side Only after the lights, the steps at the trailing edge, all
    /// quiet, since the card is what the window is for. Replay Audio has no
    /// button, as on the study screen: R replays, and the card's players
    /// play on a click.
    private var band: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            backSideOnly
            Spacer(minLength: Theme.Spacing.small)
            IconButton("chevron.left", help: Tr.qtAccelPreviousCard, shortcut: Tr.qtMiscShortcutKeyLeftArrow) {
                model.back()
            }
            .disabled(!model.canGoBack)
            IconButton("chevron.right", help: Tr.qtAccelNextCard, shortcut: Tr.qtMiscShortcutKeyRightArrowOrEnter) {
                model.forward()
            }
            .disabled(!model.canGoForward)
        }
        // Clear of the traffic lights, which in full screen come down over
        // the band in a pill of their own.
        .padding(.leading, chrome.fullScreen ? Theme.Spacing.medium : Theme.Band.leading)
        .padding(.trailing, Theme.Spacing.medium)
        .frame(height: Theme.Band.height)
        .titleBarBand()
    }

    /// A quiet text switch led by a box that fills with a check while on,
    /// the box then in Ink. No selection wash: beside the check it only
    /// looked hovered. Where its words don't fit, in a narrow window or a
    /// long translation, the box stands alone, so the steps never leave the band.
    private var backSideOnly: some View {
        Button { model.setBackSideOnly(!model.backSideOnly) } label: {
            ViewThatFits(in: .horizontal) {
                backSideOnlyLabel.labelStyle(BoxSwitchLabelStyle())
                backSideOnlyLabel.labelStyle(.iconOnly)
            }
            .font(Theme.Fonts.chip)
            .padding(.horizontal, Theme.Layout.segmentPadding - Theme.Spacing.xSmall)
            .frame(height: Theme.Layout.controlHeight)
        }
        .buttonStyle(QuietButtonStyle())
        .help("\(Tr.qtMiscBackSideOnly)\n\(Tr.actionsShortcutKey(val: "B"))")
        .accessibilityLabel(Tr.qtMiscBackSideOnly)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(model.backSideOnly ? "On" : "Off")
    }

    private var backSideOnlyLabel: some View {
        Label {
            Text(Tr.qtMiscBackSideOnly).lineLimit(1)
        } icon: {
            if model.backSideOnly {
                Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.Palette.text)
            } else {
                Image(systemName: "square")
            }
        }
    }
}

/// The box sits close to its words, as a checkbox's does.
private struct BoxSwitchLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            configuration.icon
            configuration.title
        }
    }
}
