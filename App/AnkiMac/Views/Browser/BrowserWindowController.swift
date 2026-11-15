import AppKit
import Observation
import SwiftUI

/// The Browse window, built in AppKit: a SwiftUI `Window` scene with a
/// toolbar and split view took about 300 ms to open, most of it creating
/// the scene and bridging the toolbar, where desktop takes 100-160 ms.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    private(set) static var current: BrowserWindowController?

    let model: BrowserModel
    private let sidebar: BrowserSidebarController
    private let tableController: BrowserTableController
    private let editor: BrowserEditorModel?
    private let chrome: BrowserChrome
    private let searchField = NSSearchField()
    private let errorBar = SearchErrorBar()
    private var previewer: BrowserPreviewWindowController?
    private var presentingAlert = false
    private var promptSheet: NSViewController?
    private var findDuplicates: FindDuplicatesWindowController?

    /// Shows the browser, creating it on first use. The first search starts
    /// before the window is built, so the two overlap.
    static func show(collection: CollectionModel) {
        if let current {
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        guard collection.isLoaded else { return }
        let model = BrowserModel(collection: collection)
        model.open()
        let controller = BrowserWindowController(model: model)
        current = controller
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(model: BrowserModel) {
        self.model = model
        sidebar = BrowserSidebarController(model: model)
        editor = model.collection.backend.map {
            BrowserEditorModel(browser: model, backend: $0, mediaFolder: model.collection.paths?.mediaFolder)
        }
        tableController = BrowserTableController(model: model)
        chrome = BrowserChrome(hasEditor: editor != nil)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Browser.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)

        // The title names the window in the Window menu; the band draws its own.
        window.title = Tr.qtMiscBrowse
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: Theme.Browser.minWidth, height: Theme.Browser.minHeight)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        // Clear, the split view painting the canvas: the bar that comes down
        // in full screen is as opaque as the window's background colour.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.delegate = self
        window.contentViewController = makeSplit()
        window.setFrameAutosaveName("Browser")
        if !window.setFrameUsingName("Browser") { window.center() }

        // An empty toolbar, only so the traffic lights sit centred in a
        // unified bar's height. Its items would each be drawn in a glass
        // capsule, so the controls are in the band (`BrowserHeaderBar`)
        // drawn plainly, as the main window's are.
        let toolbar = NSToolbar(identifier: "Browser")
        toolbar.allowsDisplayModeCustomization = false
        // Icons only, as SwiftUI's toolbars: with room kept for labels the
        // bar is taller than the main window's, and the lights sit lower.
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        searchField.placeholderString = Tr.actionsSearch
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(searchSubmitted(_:))
        window.initialFirstResponder = searchField
        observeModel()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeSplit() -> NSSplitViewController {
        let split = BrowserSplitController(chrome: chrome)
        split.splitView = HairlineSplitView()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        chrome.toggleSidebar = { [weak split] in split?.toggleSidebar(nil) }
        chrome.toggleEditor = { [weak split] in split?.toggleInspector(nil) }
        chrome.togglePreview = { [weak self] in self?.togglePreview() }
        sidebar.chrome = chrome
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = Theme.Sidebar.minWidth
        // Unlike the main window's, this sidebar takes its room from the
        // table: the window keeps its width.
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        // A full-height sidebar gets its own section of the title bar, drawn
        // as glass in full screen; the bar is one piece, as the main window's.
        sidebarItem.allowsFullHeightLayout = false
        split.addSplitViewItem(sidebarItem)
        let header = BrowserHeaderBar(model: model, chrome: chrome, searchField: searchField)
        split.addSplitViewItem(NSSplitViewItem(
            viewController: DetailController(header: header, errorBar: errorBar, table: tableController)))
        if let editor {
            // An inspector, so a narrow window can fold it away.
            let view = BrowserEditorView(model: editor, browser: model, chrome: chrome) { [model] in
                CardTemplatesWindowController.show(collection: model.collection, note: editor.currentNote, ord: editor.cardOrd)
            }
            let host = NSHostingController(rootView: view)
            // By default the pane's SwiftUI size would cap the window's:
            // "No Note Selected" is short, and the window couldn't grow taller.
            host.sizingOptions = []
            // The pane starts under the band, not under the toolbar's safe area.
            host.safeAreaRegions = []
            let item = NSSplitViewItem(inspectorWithViewController: host)
            item.minimumThickness = Theme.Browser.editorMinWidth
            // An inspector stops at a narrow width by default; the editor can take as much as the table spares.
            item.maximumThickness = NSSplitViewItem.unspecifiedDimension
            item.preferredThicknessFraction = Theme.Browser.editorFraction
            item.canCollapse = true
            item.allowsFullHeightLayout = false
            split.addSplitViewItem(item)
        }
        split.splitView.autosaveName = "BrowserSplit"
        return split
    }

    private func observeModel() {
        track { [weak self] in
            guard let self else { return }
            // The model's text changes only on a search, never while typing.
            if searchField.stringValue != model.searchText {
                searchField.stringValue = model.searchText
            }
        }
        track { [weak self] in
            guard let self else { return }
            errorBar.show(model.searchError)
        }
        track { [weak self] in
            guard let self else { return }
            showPrompt(model.prompt)
        }
        track { [weak self] in
            guard let self else { return }
            // The note follows the selection, and a new search's rows.
            _ = model.idsVersion
            let selection = model.selection
            DispatchQueue.main.async { self.editor?.show(selection) }
        }
        track { [weak self] in
            guard let self else { return }
            if let notes = model.notesToDelete {
                confirmDelete(count: notes.count)
            } else if let failure = model.failure {
                showError(failure)
            }
        }
    }

    func showFindDuplicates() {
        let controller = findDuplicates ?? FindDuplicatesWindowController(
            model: FindDuplicatesModel(browser: model) { [weak self] text in
                self?.sidebar.clearSelection()
                self?.model.setMode(.notes)
                self?.model.search(text: text)
            })
        findDuplicates = controller
        controller.show(over: window)
    }

    @objc private func searchSubmitted(_ field: NSSearchField) {
        sidebar.clearSelection()
        model.searchText = field.stringValue
        model.search()
    }

    /// Opens the preview window, or closes it when it is open.
    @objc func togglePreview() {
        if let previewer {
            previewer.close()
        } else if model.singleSelectedRow != nil {
            let controller = BrowserPreviewWindowController(browser: model) { [weak self] in
                self?.previewer = nil
                self?.chrome.previewOpen = false
            }
            previewer = controller
            controller.showWindow(nil)
            chrome.previewOpen = true
        }
    }

    /// Shows the sheet for the model's prompt, and takes it down once the
    /// prompt is answered or cancelled.
    private func showPrompt(_ prompt: BrowserPrompt?) {
        if let promptSheet {
            promptSheet.dismiss(nil)
            self.promptSheet = nil
        }
        guard let prompt, let content = window?.contentViewController else { return }
        let sheet = NSHostingController(rootView: BrowserPromptSheet(prompt: prompt, model: model))
        sheet.sizingOptions = .preferredContentSize
        promptSheet = sheet
        content.presentAsSheet(sheet)
    }

    private func confirmDelete(count: Int) {
        guard let window, !presentingAlert else { return }
        presentingAlert = true
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Delete 1 note?" : "Delete \(count.formatted()) notes?"
        alert.informativeText = "Their cards are deleted too. You can undo this with Edit > Undo."
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        // Return cancels: the safe choice is the default one.
        delete.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            presentingAlert = false
            if response == .alertFirstButtonReturn {
                model.confirmDelete()
            } else {
                model.notesToDelete = nil
            }
        }
    }

    private func showError(_ failure: ActionFailure) {
        guard let window, !presentingAlert else { return }
        presentingAlert = true
        let alert = NSAlert()
        alert.messageText = failure.title
        alert.informativeText = failure.detail
        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.presentingAlert = false
            self?.model.failure = nil
        }
    }

    // MARK: Window

    /// View › Toggle Sidebar while the browser is key.
    func toggleSidebar() {
        chrome.toggleSidebar()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        KeyBrowser.shared.model = model
        model.refreshUndo()
    }

    func windowDidResignKey(_ notification: Notification) {
        if KeyBrowser.shared.model === model { KeyBrowser.shared.model = nil }
    }

    /// In full screen the empty toolbar would draw as a dark bar over the
    /// sidebar's band and its button; it hides with the menu bar instead,
    /// and comes down with it, the traffic lights in it.
    func window(
        _ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []
    ) -> NSApplication.PresentationOptions {
        // AppKit raises unless the menu bar hides too.
        proposedOptions.contains(.autoHideMenuBar) ? proposedOptions.union(.autoHideToolbar) : proposedOptions
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        chrome.fullScreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        if let window { FullScreenTitlebar.dress(window, true) }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        chrome.fullScreen = false
        if let window { FullScreenTitlebar.dress(window, false) }
    }

    func windowWillClose(_ notification: Notification) {
        previewer?.close()
        editor?.editor.commitPendingEdits()
        editor?.saveNow()
        findDuplicates?.close()
        if KeyBrowser.shared.model === model { KeyBrowser.shared.model = nil }
        Self.current = nil
    }
}

/// Cards or Notes, as quiet segments. The model's mode is the only state:
/// picking one asks the model, and the segments follow it.
private struct ModeSwitch: View {
    static let help = "Show one row per card or one row per note"
    let model: BrowserModel

    var body: some View {
        QuietSegments(
            selection: Binding(get: { model.mode }, set: { model.setMode($0) }), choices: BrowserMode.allCases,
            title: \.title)
        .help(Self.help)
    }
}

/// Draws the line between panes as a hairline, not the system's grey, over
/// the canvas, which the window itself leaves clear.
private final class HairlineSplitView: NSSplitView {
    override var dividerColor: NSColor { Theme.Palette.hairlineNS }

    override func draw(_ dirtyRect: NSRect) {
        Theme.Palette.canvasNS.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

/// The browser that menu commands act on while its window is key. SwiftUI's
/// focused values only see SwiftUI scenes, and the browser window isn't one.
@Observable
final class KeyBrowser {
    static let shared = KeyBrowser()
    var model: BrowserModel?
}

/// What the band's buttons show and do: which panes are folded away and
/// whether the preview is open. The split view and the preview keep it current.
@Observable
final class BrowserChrome {
    let hasEditor: Bool
    var sidebarCollapsed = false
    var editorCollapsed = false
    var previewOpen = false
    var fullScreen = false
    @ObservationIgnored var toggleSidebar: () -> Void = {}
    @ObservationIgnored var toggleEditor: () -> Void = {}
    @ObservationIgnored var togglePreview: () -> Void = {}

    init(hasEditor: Bool) {
        self.hasEditor = hasEditor
    }

    /// Where the sidebar button starts: clear of the traffic lights, or at
    /// the margin in full screen, where there are none.
    var sidebarToggleLeading: CGFloat {
        fullScreen ? Theme.Browser.cellPadding : Theme.Browser.sidebarToggleLeading
    }
}

/// Tells the band when the sidebar or the editor folds away.
private final class BrowserSplitController: NSSplitViewController {
    private let chrome: BrowserChrome

    init(chrome: BrowserChrome) {
        self.chrome = chrome
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        let sidebar = splitViewItems.first?.isCollapsed ?? false
        let editor = chrome.hasEditor ? splitViewItems.last?.isCollapsed ?? false : true
        if chrome.sidebarCollapsed != sidebar { chrome.sidebarCollapsed = sidebar }
        if chrome.editorCollapsed != editor { chrome.editorCollapsed = editor }
    }
}

/// The band over the table, under the traffic lights, as a pane's header in
/// Rex: the window's name and counts on the left, then the Cards and Notes
/// switch, the search field, Preview and the editor's button, all drawn
/// plainly on the canvas. While the sidebar is hidden its button moves here,
/// to the same place beside the traffic lights.
private final class BrowserHeaderBar: NSView {
    init(model: BrowserModel, chrome: BrowserChrome, searchField: NSSearchField) {
        super.init(frame: .zero)
        let title = NSHostingView(rootView: HeaderTitle(model: model, chrome: chrome))
        let mode = NSHostingView(rootView: ModeSwitch(model: model))
        let actions = NSHostingView(rootView: BrowserHeaderActions(model: model, chrome: chrome, inEditor: false))
        // The band lies in the toolbar's safe area, which would push
        // SwiftUI's content down out of sight.
        title.safeAreaRegions = []
        mode.safeAreaRegions = []
        actions.safeAreaRegions = []
        for view in [title, mode, actions] as [NSView] {
            view.setContentHuggingPriority(.required, for: .horizontal)
        }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.controlSize = .regular
        let width = searchField.widthAnchor.constraint(equalToConstant: Theme.Browser.searchWidth)
        width.priority = .defaultLow
        NSLayoutConstraint.activate([
            width, searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.Browser.searchMinWidth),
        ])
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [title, spacer, mode, searchField, actions])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Theme.Spacing.small
        row.setCustomSpacing(Theme.Spacing.medium, after: mode)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: Theme.Spacing.small)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Theme.Browser.chromeHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Dragging the band moves the window, as a title bar does.
    override var mouseDownCanMoveWindow: Bool { true }
}

/// "Browse" over what the table shows, its first letter on the table's
/// text edge; a change's message takes the counts' place for a moment.
private struct HeaderTitle: View {
    let model: BrowserModel
    let chrome: BrowserChrome

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            if chrome.sidebarCollapsed {
                IconButton("sidebar.left", help: "Show Sidebar") { chrome.toggleSidebar() }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Tr.qtMiscBrowse)
                    .font(Theme.Browser.titleFont)
                    .foregroundStyle(Theme.Palette.text)
                    .lineLimit(1)
                Text(model.toast ?? status)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, chrome.sidebarCollapsed ? chrome.sidebarToggleLeading : Theme.Browser.cellPadding)
        // In a narrow pane the counts lose their end before the search field goes.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var status: String {
        let noun = model.mode == .cards ? "card" : "note"
        let total = model.ids.count
        let selected = model.selectedRows.count
        let shown = "\(total.formatted()) \(total == 1 ? noun : noun + "s")"
        return selected == 0 ? shown : "\(selected.formatted()) of \(shown) selected"
    }
}

/// Preview, and the button that shows or hides the editor. They sit at the
/// window's top trailing corner: in the editor's band while it is shown, and
/// at the end of the table's once it is hidden, so each place draws them
/// only when it is that corner.
struct BrowserHeaderActions: View {
    let model: BrowserModel
    let chrome: BrowserChrome
    let inEditor: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xxSmall) {
            if inEditor == (chrome.hasEditor && !chrome.editorCollapsed) {
                IconButton(chrome.previewOpen ? "eye.fill" : "eye", help: Tr.actionsPreview, shortcut: Tr.actionsShortcutKey(val: "\u{21E7}\u{2318}P")) {
                    chrome.togglePreview()
                }
                // As desktop, a preview needs exactly one card selected.
                .disabled(!chrome.previewOpen && model.singleSelectedRow == nil)
                if chrome.hasEditor {
                    IconButton("sidebar.right", help: chrome.editorCollapsed ? "Show Editor" : "Hide Editor") {
                        chrome.toggleEditor()
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// The band, the error bar and the table, top to bottom.
private final class DetailController: NSViewController {
    private let header: BrowserHeaderBar
    private let errorBar: SearchErrorBar
    private let table: BrowserTableController

    init(header: BrowserHeaderBar, errorBar: SearchErrorBar, table: BrowserTableController) {
        self.header = header
        self.errorBar = errorBar
        self.table = table
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        addChild(table)
        let stack = NSStackView(views: [header, errorBar, table.view])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // From the window's top edge: the band sits under the traffic lights,
        // where the transparent title bar passes its clicks through.
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }
}

/// The backend's explanation of a search it could not parse, above the
/// results of the last search that worked. Flat Raised Oat under a hairline.
private final class SearchErrorBar: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
        icon.symbolConfiguration = .preferringMulticolor()
        label.textColor = Theme.Palette.textNS
        label.isSelectable = true
        let row = NSStackView(views: [icon, label])
        row.spacing = Theme.Spacing.small
        row.alignment = .firstBaseline
        row.edgeInsets = NSEdgeInsets(
            top: Theme.Spacing.small, left: Theme.Spacing.medium, bottom: Theme.Spacing.small,
            right: Theme.Spacing.medium)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        Theme.Palette.raisedNS.setFill()
        dirtyRect.fill()
        Theme.Palette.hairlineNS.setFill()
        NSRect(x: bounds.minX, y: isFlipped ? bounds.maxY - 1 : bounds.minY, width: bounds.width, height: 1)
            .intersection(dirtyRect).fill()
    }

    func show(_ message: String?) {
        isHidden = message == nil
        label.stringValue = message ?? ""
        setAccessibilityLabel(message.map { "Search error: \($0)" })
    }
}
