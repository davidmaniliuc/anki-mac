import AppKit
import SwiftUI

/// Desktop's Find Duplicates dialog: a window that stays above the Browser,
/// not a sheet, so a click on a group can search the Browser while the
/// report stays in view.
final class FindDuplicatesWindowController: NSWindowController {
    private let model: FindDuplicatesModel

    init(model: FindDuplicatesModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Browser.findDuplicatesSize),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = Tr.browsingFindDuplicates
        window.contentViewController = NSHostingController(rootView: FindDuplicatesView(model: model, close: { [weak window] in window?.close() }))
        window.minSize = Theme.Browser.findDuplicatesMinSize
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

private struct FindDuplicatesView: View {
    let model: FindDuplicatesModel
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Form {
                Picker(Tr.browsingSearchIn, selection: Bindable(model).field) {
                    ForEach(model.fields, id: \.self) { Text($0).tag($0) }
                }
                TextField(Tr.browsingOptionalFilter, text: Bindable(model).filter)
                    .focused($focused)
                    .onSubmit(model.find)
            }
            .formStyle(.columns)
            report
            HStack {
                if model.groups != nil {
                    Button(Tr.browsingTagDuplicates, action: model.tagDuplicates)
                        .disabled(model.groups?.isEmpty ?? true)
                }
                Spacer()
                Button(Tr.actionsClose, role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                Button(Tr.actionsSearch, action: model.find)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.field.isEmpty || model.isSearching)
            }
        }
        .padding(Theme.Spacing.large)
        .onAppear { focused = true }
    }

    @ViewBuilder private var report: some View {
        if let error = model.error {
            Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let groups = model.groups {
            let whole = Tr.browsingNoteCount(count: model.noteCount)
            Text(Tr.browsingFoundAsAcrossBs(part: Tr.browsingGroup(count: groups.count), whole: whole))
            List(groups) { group in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Button(Tr.browsingNoteCount(count: group.noteIDs.count)) { model.show(group) }
                        .buttonStyle(.link)
                    Text(": " + group.value).textSelection(.enabled)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        } else {
            Color.clear.frame(maxHeight: .infinity)
        }
    }
}
