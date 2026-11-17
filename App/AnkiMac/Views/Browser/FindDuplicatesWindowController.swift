import AppKit
import SwiftUI

/// Desktop's Find Duplicates dialog: a window that stays above the Browser,
/// not a sheet, so a click on a group can search the Browser while the
/// report stays in view. It has Add's chrome: the canvas from the top edge
/// and the window's name in a band under the traffic lights.
final class FindDuplicatesWindowController: NSWindowController {
    private let model: FindDuplicatesModel

    init(model: FindDuplicatesModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Browser.findDuplicatesSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        let host = NSHostingView(rootView: FindDuplicatesView(model: model, close: { [weak window] in window?.close() }))
        // The band starts at the window's top, under the traffic lights.
        host.safeAreaRegions = []
        host.sizingOptions = []
        // Inside a plain view, as Add's, so the hosting view never resizes the window.
        host.autoresizingMask = [.width, .height]
        let content = NSView(frame: NSRect(origin: .zero, size: Theme.Browser.findDuplicatesSize))
        host.frame = content.bounds
        content.addSubview(host)
        window.contentView = content
        // The title names the window in the Window menu; the band shows it too.
        window.title = Tr.browsingFindDuplicates
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.Palette.canvasNS
        // An empty toolbar, only so the traffic lights sit centred in the band.
        let toolbar = NSToolbar(identifier: "FindDuplicates")
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        // It rides on the Browser, so the green button zooms rather than
        // taking a space of its own.
        window.collectionBehavior = [.fullScreenNone]
        window.contentMinSize = Theme.Browser.findDuplicatesMinSize
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FindDuplicates")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the window above `parent`, which it closes and minimises with.
    func show(over parent: NSWindow?) {
        guard let window else { return }
        model.loadFields()
        if window.parent == nil, let parent {
            if !window.setFrameUsingName("FindDuplicates") { window.center() }
            parent.addChildWindow(window, ordered: .above)
        }
        window.makeKeyAndOrderFront(nil)
    }
}

/// The field to compare and the filter as Deck Options' rows, then the
/// report: upstream's sentence counting what was found, and each group as
/// a dense row, as the Browser's, that shows its notes in the Browser.
private struct FindDuplicatesView: View {
    let model: FindDuplicatesModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            band
            OptionSection {
                OptionRow(title: rowTitle(Tr.browsingSearchIn), revertible: false) {
                    OptionPicker(selection: Bindable(model).field, choices: model.fields.map { ($0, $0) })
                }
                OptionRow(title: rowTitle(Tr.browsingOptionalFilter), revertible: false) {
                    OptionTextField(text: Bindable(model).filter, focusOnAppear: true)
                        .onSubmit(model.find)
                        .frame(width: Theme.Browser.fieldWidth)
                }
            }
            .padding(.horizontal, Theme.DeckOptions.margin)
            report
            foot
        }
        .background(Theme.Palette.canvas)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onExitCommand(perform: close)
    }

    /// The window's name after the traffic lights.
    private var band: some View {
        Text(Tr.browsingFindDuplicates)
            .font(Theme.Band.titleFont)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, Theme.Band.leading)
            .padding(.trailing, Theme.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: Theme.Band.height, maxHeight: Theme.Band.height, alignment: .leading)
            .titleBarBand()
    }

    @ViewBuilder private var report: some View {
        if let groups = model.groups, model.error == nil {
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                let whole = Tr.browsingNoteCount(count: model.noteCount)
                Text(figures(Tr.browsingFoundAsAcrossBs(part: Tr.browsingGroup(count: groups.count), whole: whole)))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .padding(.horizontal, Theme.DeckOptions.margin)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groups) { group in
                            DuplicateGroupRow(group: group) { model.show(group) }
                        }
                    }
                    .padding(.horizontal, Theme.DeckOptions.margin)
                }
                .scrollEdgeEffectHidden(true, for: .vertical)
            }
            .padding(.top, Theme.Spacing.large)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            Spacer(minLength: 0)
        }
    }

    /// Tag Duplicates once there's a report, what's happening or what
    /// failed, then Search, the window's one Primary.
    private var foot: some View {
        HStack(spacing: Theme.Spacing.small) {
            if model.groups != nil {
                Button(Tr.browsingTagDuplicates, action: model.tagDuplicates)
                    .buttonStyle(ChipButtonStyle())
                    .disabled(model.groups?.isEmpty ?? true)
            }
            if model.isSearching {
                ProgressView().controlSize(.small)
            } else if let error = model.error {
                OptionWarning(text: error, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            Button(action: model.find) {
                Text(Tr.actionsSearch)
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .keyboardShortcut(.defaultAction)
            .disabled(model.field.isEmpty || model.isSearching)
        }
        .padding(.horizontal, Theme.DeckOptions.margin)
        .padding(.vertical, Theme.Spacing.medium)
    }
}

/// A group of notes sharing a value: how many in rounded Pencil, then the
/// value in Ink. A click shows them in the Browser, the arrow appearing
/// under the pointer as Empty Cards' rows do.
private struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Spacing.small) {
                Text(figures(Tr.browsingNoteCount(count: group.noteIDs.count)))
                    .font(Theme.Maintenance.rowFont)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize()
                Text(group.value)
                    .font(Theme.Maintenance.rowFont)
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.small)
                Image(systemName: "arrow.up.forward.app")
                    .font(Theme.Maintenance.browseSymbol)
                    .foregroundStyle(Theme.Palette.secondary)
                    .opacity(hovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.small)
            .frame(height: Theme.Maintenance.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
            .fill(hovered ? Theme.Palette.hover : .clear))
        .padding(.horizontal, -Theme.Spacing.small)
        .onHover { hovered = $0 }
        .help(Tr.searchViewInBrowser)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Tr.searchViewInBrowser)
    }
}
