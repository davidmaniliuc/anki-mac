import AppKit

/// The browser's sidebar: an NSOutlineView on Sidebar Linen, its rows and
/// selection drawn by hand in the main window's look. A SwiftUI `List` took
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
        // Plain, not a source list: no vibrancy and no system selection, so
        // the rows (see `SidebarRowView`) and the linen are drawn here.
        outline.style = .plain
        outline.rowSizeStyle = .custom
        outline.rowHeight = Theme.Browser.denseRowHeight
        outline.intercellSpacing = .zero
        outline.indentationPerLevel = Theme.Layout.indent
        outline.backgroundColor = .clear
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
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.Palette.sidebarNS
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

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        outlineView.makeView(withIdentifier: SidebarRowView.identifier, owner: nil) as? SidebarRowView ?? SidebarRowView()
    }

    /// A section's name has room above it, except the first.
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let row = item as? Row, row.item == nil, row !== roots.first else { return Theme.Browser.denseRowHeight }
        return Theme.Browser.denseRowHeight + Theme.Browser.sidebarHeaderGap
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let row = item as? Row else { return nil }
        guard let sidebarItem = row.item else {
            let header = outlineView.makeView(withIdentifier: SidebarHeaderCell.identifier, owner: nil)
                as? SidebarHeaderCell ?? SidebarHeaderCell()
            header.show(row.title)
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

/// A section's name: an eyebrow, in Pencil.
private final class SidebarHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarHeader")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        let label = NSTextField(labelWithString: "")
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ title: String) {
        textField?.attributedStringValue = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: Theme.Browser.headerFont, .foregroundColor: Theme.Palette.secondaryNS,
                .kern: Theme.Fonts.eyebrowTracking,
            ])
        textField?.setAccessibilityLabel(title)
    }

    /// The name sits in the row's last 26px; any extra height is the gap above it.
    override func layout() {
        super.layout()
        guard let label = textField else { return }
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(
            x: 0, y: (Theme.Browser.denseRowHeight - height) / 2, width: bounds.width, height: height)
    }
}

/// A sidebar row: the selection wash, and a hover wash under the pointer. A
/// selected row's label steps forward to semibold, as the main sidebar's.
private final class SidebarRowView: WashRowView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarRow")

    private var hovered = false {
        didSet { if hovered != oldValue { needsDisplay = true } }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isSelected: Bool {
        didSet { cell?.showsSelection = isSelected }
    }

    private var cell: SidebarCell? { subviews.lazy.compactMap { $0 as? SidebarCell }.first }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? SidebarCell)?.showsSelection = isSelected
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hovered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = !isGroupRowStyle }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if hovered, !isSelected { fillWash(Theme.Palette.hoverNS) }
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

    /// Set by the row view: the selected row's name is semibold.
    var showsSelection = false {
        didSet { if showsSelection != oldValue { label.font = showsSelection ? Theme.Browser.sidebarSelectedFont : Theme.Browser.sidebarFont } }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.font = Theme.Browser.sidebarFont
        label.textColor = Theme.Palette.textNS
        label.backgroundColor = Theme.Palette.canvasNS
        label.lineBreakMode = .byTruncatingTail
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Theme.Browser.sidebarIconSize, weight: .regular)
        addSubview(icon)
        addSubview(label)
        imageView = icon
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows the name over the canvas, as a field being typed in.
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
        // Flags keep their colour; every other icon is Pencil.
        if case .flag(let flag) = item {
            icon.contentTintColor = NSColor(Theme.flagColor(flag))
        } else {
            icon.contentTintColor = Theme.Palette.secondaryNS
        }
    }

    override func layout() {
        super.layout()
        let slot = Theme.Browser.sidebarIconSlot
        icon.frame = NSRect(x: 0, y: ((bounds.height - slot) / 2).rounded(), width: slot, height: slot)
        let height = label.intrinsicContentSize.height
        let x = slot + Theme.Spacing.small
        label.frame = NSRect(
            x: x, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - x), height: height)
    }
}
