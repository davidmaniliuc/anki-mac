import AppKit

/// The browser's sidebar: a source-list NSOutlineView. A SwiftUI `List` took
/// about 70 ms of main thread to insert a 70-row sidebar; this takes a few.
final class BrowserSidebarController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let model: BrowserModel
    let outline = SidebarOutlineView()
    private var roots: [Row] = []
    private var shown: [SidebarSection]?
    /// Set while the sidebar restores its selection after a reload, which is
    /// not a new search.
    private var restoringSelection = false
    private var selectionCount = 0
    /// The row whose name is being edited in place.
    var editing: Row?
    var cancelledEdit = false

    init(model: BrowserModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        outline.style = .sourceList
        outline.headerView = nil
        outline.floatsGroupRows = false
        outline.allowsMultipleSelection = true
        outline.onDelete = { [weak self] in self?.deleteSelection() }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        outline.menu = menu
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = self
        outline.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        view = scroll
        track { [weak self] in self?.show(self?.model.sidebar) }
    }

    /// A typed search replaces the sidebar's.
    func clearSelection() {
        outline.deselectAll(nil)
    }

    /// Shows the sections again after a change, keeping what was expanded and
    /// selected. A header or parent that gained its first children opens, and
    /// the row the change made or renamed is revealed and selected.
    private func show(_ sections: [SidebarSection]?) {
        guard let sections, sections != shown else { return }
        cancelEdit()
        let change = model.sidebarChange
        var kept = shown == nil ? nil : snapshot(roots)
        if let rename = change?.tagRename { kept?.renameTags(rename) }
        shown = sections
        roots = sections.map(Row.init(section:))
        outline.reloadData()
        if let kept {
            restoreExpansion(roots, kept)
        } else {
            roots.forEach { outline.expandItem($0) }
        }
        var selected = kept?.selected ?? []
        if let reveal = change?.reveal, let path = path(to: .item(reveal), in: roots), let target = path.last {
            path.dropLast().forEach { outline.expandItem($0) }
            selected = [target.id]
        }
        restoringSelection = true
        defer { restoringSelection = false }
        let rows = IndexSet(allRows(roots).filter { selected.contains($0.id) }.map(outline.row(forItem:)).filter { $0 >= 0 })
        outline.selectRowIndexes(rows, byExtendingSelection: false)
        if let first = rows.first { outline.scrollRowToVisible(first) }
    }

    /// What of the old rows carries over a reload. A leaf is kept so that a
    /// row that gains children can be told from one the user collapsed.
    private struct Snapshot {
        var expanded: Set<Row.ID> = []
        var leaves: Set<Row.ID> = []
        var selected: Set<Row.ID> = []

        mutating func renameTags(_ rename: (from: String, to: String)) {
            func renamed(_ id: Row.ID) -> Row.ID {
                guard case .item(.tag(let name)) = id,
                    let range = name.range(of: rename.from, options: [.anchored, .caseInsensitive]),
                    range.upperBound == name.endIndex || name[range.upperBound...].hasPrefix("::")
                else { return id }
                return .item(.tag(rename.to + name[range.upperBound...]))
            }
            expanded = Set(expanded.map(renamed))
            leaves = Set(leaves.map(renamed))
            selected = Set(selected.map(renamed))
        }
    }

    private func snapshot(_ rows: [Row]) -> Snapshot {
        var kept = Snapshot()
        for row in allRows(rows) {
            if row.children.isEmpty {
                kept.leaves.insert(row.id)
            } else if outline.isItemExpanded(row) {
                kept.expanded.insert(row.id)
            }
        }
        kept.selected = Set(selectedRows.map(\.id))
        return kept
    }

    private func restoreExpansion(_ rows: [Row], _ kept: Snapshot) {
        for row in rows where !row.children.isEmpty && (kept.expanded.contains(row.id) || kept.leaves.contains(row.id)) {
            outline.expandItem(row)
            restoreExpansion(row.children, kept)
        }
    }

    private func path(to id: Row.ID, in rows: [Row]) -> [Row]? {
        for row in rows {
            if row.id == id { return [row] }
            if let rest = path(to: id, in: row.children) { return [row] + rest }
        }
        return nil
    }

    private func allRows(_ rows: [Row]) -> [Row] {
        rows.flatMap { [$0] + allRows($0.children) }
    }

    var selectedRows: [Row] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? Row }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Row)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Row)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Row)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? Row)?.item == nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? Row)?.item != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? Row else { return nil }
        guard let sidebarItem = row.item else {
            let header = outlineView.makeView(withIdentifier: SidebarHeaderCell.identifier, owner: nil)
                as? SidebarHeaderCell ?? SidebarHeaderCell()
            header.textField?.stringValue = row.title
            return header
        }
        let cell = outlineView.makeView(withIdentifier: SidebarCell.identifier, owner: nil) as? SidebarCell
            ?? SidebarCell()
        cell.show(row.title, item: sidebarItem)
        return cell
    }

    /// Clicking one row searches it; a selection of several is for the
    /// context menu, which searches them all or any.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let before = selectionCount
        selectionCount = outline.selectedRowIndexes.count
        guard !restoringSelection, selectionCount == 1,
            let row = outline.item(atRow: outline.selectedRow) as? Row, let item = row.item
        else { return }
        // Cmd-click or Shift-arrow that narrows several rows to one is still
        // picking rows for the menu.
        if before > 1, !NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) { return }
        model.search(item)
    }

    /// NSOutlineView keys rows by object identity, so the value-type tree is
    /// wrapped in objects once per load.
    final class Row {
        let title: String
        let kind: SidebarKind
        let item: SidebarItem?
        let children: [Row]

        /// Stable across reloads, unlike the object, and across renames.
        let id: ID

        enum ID: Hashable {
            case header(SidebarKind)
            case item(SidebarItem.ID)
        }

        init(section: SidebarSection) {
            title = section.title
            kind = section.kind
            item = nil
            id = .header(section.kind)
            children = section.nodes.map(Row.init(node:))
        }

        init(node: SidebarNode) {
            title = node.title
            kind = node.item.kind
            item = node.item
            id = .item(node.item.id)
            children = (node.children ?? []).map(Row.init(node:))
        }
    }
}

private final class SidebarHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarHeader")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        let label = NSTextField(labelWithString: "")
        label.font = Theme.Browser.sidebarHeaderFont
        label.textColor = .secondaryLabelColor
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        guard let label = textField else { return }
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
    }
}

/// Delete removes the selected rows, when their kind allows it.
final class SidebarOutlineView: NSOutlineView {
    var onDelete: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        // Delete and Forward Delete.
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class SidebarCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(label)
        imageView = icon
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func beginEditing(delegate: NSTextFieldDelegate) {
        label.isEditable = true
        label.drawsBackground = true
        label.delegate = delegate
        label.selectText(nil)
    }

    func endEditing(title: String) {
        label.isEditable = false
        label.drawsBackground = false
        label.delegate = nil
        label.stringValue = title
    }

    func show(_ title: String, item: SidebarItem) {
        label.isEditable = false
        label.drawsBackground = false
        label.delegate = nil
        label.stringValue = title
        icon.image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil)
        // Flags keep their colour; every other icon follows the accent colour.
        if case .flag(let flag) = item {
            icon.contentTintColor = NSColor(Theme.flagColor(flag))
        } else {
            icon.contentTintColor = .controlAccentColor
        }
    }

    override func layout() {
        super.layout()
        let side = Theme.Browser.sidebarIconSize
        icon.frame = NSRect(x: 0, y: (bounds.height - side) / 2, width: side, height: side)
        let height = label.intrinsicContentSize.height
        let x = side + Theme.Spacing.small
        label.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: max(0, bounds.width - x), height: height)
    }
}
