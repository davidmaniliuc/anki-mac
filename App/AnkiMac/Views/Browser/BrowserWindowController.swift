import AppKit
import Observation

/// The Browse window, built in AppKit: a SwiftUI `Window` scene with a
/// toolbar and split view took about 300 ms to open, most of it creating
/// the scene and bridging the toolbar, where desktop takes 100-160 ms.
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private(set) static var current: BrowserWindowController?

    let model: BrowserModel
    private let sidebar: BrowserSidebarController
    private let tableController: BrowserTableController
    private let searchItem = NSSearchToolbarItem(itemIdentifier: .search)
    private let modeControl = NSSegmentedControl(
        labels: BrowserMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private let errorBar = SearchErrorBar()
    private var presentingAlert = false

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
        tableController = BrowserTableController(model: model)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Theme.Browser.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init(window: window)

        window.title = "Browse"
        window.minSize = NSSize(width: Theme.Browser.minWidth, height: Theme.Browser.minHeight)
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = makeSplit()
        window.setFrameAutosaveName("Browser")
        if !window.setFrameUsingName("Browser") { window.center() }

        if !UserDefaults.standard.bool(forKey: "XNoToolbar") {
        let toolbar = NSToolbar(identifier: "Browser")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        }

        searchItem.searchField.placeholderString = "Search"
        searchItem.searchField.sendsWholeSearchString = true
        searchItem.searchField.target = self
        searchItem.searchField.action = #selector(searchSubmitted(_:))
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.toolTip = "Show one row per card or one row per note"
        window.initialFirstResponder = searchItem.searchField
        observeModel()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeSplit() -> NSSplitViewController {
        let split = NSSplitViewController()
        if !UserDefaults.standard.bool(forKey: "XNoSidebar") {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = Theme.Sidebar.minWidth
        split.addSplitViewItem(sidebarItem)
        }
        // A future editor pane becomes a third item, beside the table.
        split.addSplitViewItem(NSSplitViewItem(viewController: DetailController(errorBar: errorBar, table: tableController)))
        split.splitView.autosaveName = "BrowserSplit"
        return split
    }

    private func observeModel() {
        track { [weak self] in
            guard let self else { return }
            // The model's text changes only on a search, never while typing.
            if searchItem.searchField.stringValue != model.searchText {
                searchItem.searchField.stringValue = model.searchText
            }
        }
        track { [weak self] in
            guard let self else { return }
            modeControl.selectedSegment = BrowserMode.allCases.firstIndex(of: model.mode) ?? 0
        }
        track { [weak self] in
            guard let self else { return }
            errorBar.show(model.searchError)
        }
        track { [weak self] in
            guard let self else { return }
            window?.subtitle = subtitle
        }
        track { [weak self] in
            guard let self else { return }
            if let notes = model.notesToDelete {
                confirmDelete(count: notes.count)
            } else if let message = model.errorMessage {
                showError(message)
            }
        }
    }

    private var subtitle: String {
        let noun = model.mode == .cards ? "card" : "note"
        let total = model.ids.count
        let selected = model.selectedRows.count
        let shown = "\(total.formatted()) \(total == 1 ? noun : noun + "s")"
        return selected == 0 ? shown : "\(selected.formatted()) of \(shown) selected"
    }

    @objc private func searchSubmitted(_ field: NSSearchField) {
        sidebar.clearSelection()
        model.searchText = field.stringValue
        model.search()
    }

    @objc private func modeChanged(_ control: NSSegmentedControl) {
        model.setMode(BrowserMode.allCases[control.selectedSegment])
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

    private func showError(_ message: String) {
        guard let window, !presentingAlert else { return }
        presentingAlert = true
        let alert = NSAlert()
        alert.messageText = "Something went wrong"
        alert.informativeText = message
        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.presentingAlert = false
            self?.model.errorMessage = nil
        }
    }

    // MARK: Window

    func windowDidBecomeKey(_ notification: Notification) {
        KeyBrowser.shared.model = model
        model.refreshUndo()
    }

    func windowDidResignKey(_ notification: Notification) {
        if KeyBrowser.shared.model === model { KeyBrowser.shared.model = nil }
    }

    func windowWillClose(_ notification: Notification) {
        if KeyBrowser.shared.model === model { KeyBrowser.shared.model = nil }
        Self.current = nil
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .mode, .flexibleSpace, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .search:
            return searchItem
        case .mode:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.view = modeControl
            item.label = "Show"
            return item
        default:
            return nil
        }
    }
}

private extension NSToolbarItem.Identifier {
    static let search = Self("search")
    static let mode = Self("mode")
}

/// The browser that menu commands act on while its window is key. SwiftUI's
/// focused values only see SwiftUI scenes, and the browser window isn't one.
@Observable
final class KeyBrowser {
    static let shared = KeyBrowser()
    var model: BrowserModel?
}

/// The error bar over the table.
private final class DetailController: NSViewController {
    private let errorBar: SearchErrorBar
    private let table: BrowserTableController

    init(errorBar: SearchErrorBar, table: BrowserTableController) {
        self.errorBar = errorBar
        self.table = table
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        addChild(table)
        let stack = NSStackView(views: [errorBar, table.view])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.setHuggingPriority(.defaultLow, for: .vertical)
        view = stack
    }
}

/// The backend's explanation of a search it could not parse, above the
/// results of the last search that worked.
private final class SearchErrorBar: NSVisualEffectView {
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        material = .headerView
        blendingMode = .withinWindow
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
        icon.symbolConfiguration = .preferringMulticolor()
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

    func show(_ message: String?) {
        isHidden = message == nil
        label.stringValue = message ?? ""
        setAccessibilityLabel(message.map { "Search error: \($0)" })
    }
}
