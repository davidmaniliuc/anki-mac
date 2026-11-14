import AppKit
import SwiftUI

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
    /// Set while a reload opens rows again, which isn't the user's choice to save.
    private var restoringExpansion = false
    private var selectionCount = 0
    /// The row whose name is being edited in place.
    var editing: Row?
    var cancelledEdit = false
    /// Set by the window before the view loads, for the sidebar button.
    var chrome: BrowserChrome?

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
        outline.onToggleSection = { [weak self] row in self?.toggleSection(row) }
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
        scroll.contentView = VerticalClipView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.Palette.sidebarNS
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // The band under the traffic lights, with the sidebar button beside
        // them, then the rows.
        let container = SidebarContainer()
        container.addSubview(scroll)
        var constraints = [
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Browser.chromeHeight),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        if let chrome {
            let toggle = NSHostingView(rootView: SidebarToggle(chrome: chrome))
            toggle.safeAreaRegions = []
            toggle.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(toggle)
            constraints += [
                toggle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                toggle.centerYAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Browser.chromeHeight / 2),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        view = container
        track { [weak self] in self?.show(self?.model.sidebar) }
    }

    /// A section's name folds or unfolds it, as there is no triangle before it.
    private func toggleSection(_ row: Row) {
        if outline.isItemExpanded(row) {
            outline.animator().collapseItem(row)
        } else {
            outline.animator().expandItem(row)
        }
    }

    /// A typed search replaces the sidebar's.
    func clearSelection() {
        outline.deselectAll(nil)
    }

    /// Shows the sections again after a change, keeping what was expanded and
    /// selected. A header or parent that gained its first children opens, and
    /// the row the change made or renamed is revealed and selected.
    private func show(_ sections: [SidebarSection]?) {
        // Empty until the first load: shown as a tree, it would count as
        // one with every row folded, and the load after it as a reload.
        guard let sections, !sections.isEmpty, sections != shown else { return }
        cancelEdit()
        let change = model.sidebarChange
        var kept = shown == nil ? nil : snapshot(roots)
        if let rename = change?.tagRename { kept?.renameTags(rename) }
        shown = sections
        roots = sections.map(Row.init(section:))
        outline.reloadData()
        restoringExpansion = true
        if let kept {
            restoreExpansion(roots, kept)
        } else if let saved = UserDefaults.standard.stringArray(forKey: Self.expandedKey) {
            // What was open when the browser last closed.
            let open = Set(saved)
            func expand(_ rows: [Row]) {
                for row in rows where !row.children.isEmpty && open.contains(Self.key(row)) {
                    outline.expandItem(row)
                    expand(row.children)
                }
            }
            expand(roots)
        } else {
            roots.forEach { outline.expandItem($0) }
        }
        restoringExpansion = false
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

    /// Every row keeps its outline cell: without one, the outline won't
    /// expand or collapse the row at all. A section's triangle is hidden by
    /// `SidebarOutlineView.frameOfOutlineCell` instead, and a chevron at its
    /// end under the pointer shows its state, as Finder's sidebar does.
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        showSectionState(notification)
        outline.updateHover()
        saveExpansion()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        showSectionState(notification)
        outline.updateHover()
        saveExpansion()
    }

    private static let expandedKey = "BrowserSidebarExpanded"

    /// A row's id as text, for the defaults: decks and note types by id, the
    /// rest by name, so it holds across launches.
    private static func key(_ row: Row) -> String { String(describing: row.id) }

    /// Remembers the open sections, decks and tags for the next time the
    /// browser opens. A row inside a folded one keeps its own state, as the
    /// outline does.
    private func saveExpansion() {
        guard !restoringExpansion else { return }
        let open = allRows(roots).filter { !$0.children.isEmpty && outline.isItemExpanded($0) }.map(Self.key)
        UserDefaults.standard.set(open, forKey: Self.expandedKey)
    }

    private func showSectionState(_ notification: Notification) {
        guard let row = notification.userInfo?["NSObject"] as? Row, row.item == nil else { return }
        let index = outline.row(forItem: row)
        guard index >= 0, let header = outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? SidebarHeaderCell
        else { return }
        header.expanded = outline.isItemExpanded(row)
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
            header.expanded = outlineView.isItemExpanded(row)
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

/// A section's name: an eyebrow, in Pencil, and under the pointer a chevron
/// at its end that shows whether the section is open.
final class SidebarHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarHeader")
    private let chevron = NSImageView()

    var expanded = true {
        didSet { chevron.frameCenterRotation = expanded ? -90 : 0 }
    }

    var hovered = false {
        didSet { chevron.isHidden = !hovered }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        let label = NSTextField(labelWithString: "")
        addSubview(label)
        textField = label
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: Fonts.eyebrowSize, weight: .semibold)
        chevron.contentTintColor = Theme.Palette.secondaryNS
        chevron.isHidden = true
        addSubview(chevron)
    }

    private typealias Fonts = Theme.Fonts

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
        let slot = Theme.Browser.sidebarIconSlot
        let y = (Theme.Browser.denseRowHeight - height) / 2
        label.frame = NSRect(x: 0, y: y, width: max(0, bounds.width - slot), height: height)
        chevron.frameCenterRotation = 0
        chevron.frame = NSRect(
            x: bounds.width - slot, y: ((Theme.Browser.denseRowHeight - slot) / 2).rounded(), width: slot, height: slot)
        chevron.frameCenterRotation = expanded ? -90 : 0
    }
}

/// A sidebar row: the selection wash, and a hover wash under the pointer. A
/// selected row's label steps forward to semibold, as the main sidebar's.
private final class SidebarRowView: WashRowView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarRow")

    /// Set by the outline, which alone follows the pointer.
    var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            needsDisplay = true
            header?.hovered = hovered
        }
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

    private var header: SidebarHeaderCell? { subviews.lazy.compactMap { $0 as? SidebarHeaderCell }.first }

    /// The wash stays within the pane, whatever width the outline gives its row.
    override var washBounds: NSRect {
        guard let clip = enclosingScrollView?.contentView else { return bounds }
        var rect = bounds
        rect.size.width = min(rect.width, convert(clip.bounds, from: clip).maxX - rect.minX)
        return rect
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if hovered, !isSelected, !isGroupRowStyle { fillWash(Theme.Palette.hoverNS) }
    }
}

/// Scrolls only up and down: while the pane's width animates, the outline
/// could be left wider than it and scrolled sideways, cutting off the rows.
private final class VerticalClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        rect.origin.x = 0
        return rect
    }
}

/// Hide Sidebar, in the band beside the traffic lights.
private struct SidebarToggle: View {
    let chrome: BrowserChrome

    var body: some View {
        IconButton("sidebar.left", help: "Hide Sidebar") { chrome.toggleSidebar() }
            .padding(.leading, chrome.sidebarToggleLeading)
    }
}

/// The sidebar's view: Linen behind the band and the rows, and a band that
/// moves the window when dragged, as a title bar does.
private final class SidebarContainer: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.Palette.sidebarNS.setFill()
        dirtyRect.fill()
    }
}

/// Delete removes the selected rows, when their kind allows it. Lays out its
/// own rows: section names start on the icons' edge, and a deck's triangle
/// sits in the wash before its icon rather than in the pane's margin.
final class SidebarOutlineView: NSOutlineView {
    var onDelete: () -> Void = {}
    var onToggleSection: (BrowserSidebarController.Row) -> Void = { _ in }

    /// The triangle's slot: one level of indent, before the row's icon.
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        let frame = super.frameOfOutlineCell(atRow: row)
        guard !isSection(row), frame != .zero else { return .zero }
        let width = Theme.Layout.indent
        let x = Theme.Browser.sidebarLeading + CGFloat(max(0, level(forRow: row) - 1)) * indentationPerLevel
        return NSRect(x: x, y: frame.minY, width: width, height: frame.height)
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        let leading = Theme.Browser.sidebarLeading
        let level = CGFloat(max(0, level(forRow: row) - 1))
        let x = isSection(row) ? leading : leading + Theme.Layout.indent + level * indentationPerLevel
        return NSRect(x: x, y: frame.minY, width: max(0, bounds.width - x - leading), height: frame.height)
    }

    private func isSection(_ row: Int) -> Bool {
        (item(atRow: row) as? BrowserSidebarController.Row)?.item == nil
    }

    // MARK: Hover

    /// The one row under the pointer. Rows tracking the pointer themselves
    /// missed their exits when rows moved under it (a section folding, a
    /// reload), and kept their wash; here the row is found from the pointer.
    private var hoveredRow = -1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self))
        updateHover()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(-1)
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        updateHover()
    }

    override func reloadData() {
        super.reloadData()
        hoveredRow = -1
        updateHover()
    }

    override func didAdd(_ rowView: NSTableRowView, forRow row: Int) {
        super.didAdd(rowView, forRow: row)
        (rowView as? SidebarRowView)?.hovered = row == hoveredRow
    }

    /// Finds the row under the pointer again, after the rows moved under it.
    func updateHover(_ event: NSEvent? = nil) {
        guard let window else { return setHovered(-1) }
        let point = convert(event?.locationInWindow ?? window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(visibleRect.contains(point) && window.isKeyWindow ? row(at: point) : -1)
    }

    private func setHovered(_ row: Int) {
        // Every row view is cleared, not only the last one: a row that was
        // reused or moved may still carry an old wash.
        hoveredRow = row
        enumerateAvailableRowViews { view, index in (view as? SidebarRowView)?.hovered = index == row }
    }

    override func mouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, let section = item(atRow: row) as? BrowserSidebarController.Row, section.item == nil {
            onToggleSection(section)
        } else {
            super.mouseDown(with: event)
        }
    }

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
        icon.contentTintColor = Self.tint(item)
    }

    /// Flags keep their colour, and New, Learning and Review their queue's;
    /// every other icon is Pencil. Decks aren't rings here: a ring shows the
    /// day's progress, which a search has nothing to say about.
    private static func tint(_ item: SidebarItem) -> NSColor {
        switch item {
        case .flag(let flag): NSColor(Theme.flagColor(flag))
        case .cardState(.new): NSColor(Theme.Colors.newCards)
        case .cardState(.learn): NSColor(Theme.Colors.learnCards)
        case .cardState(.review): NSColor(Theme.Colors.reviewCards)
        default: Theme.Palette.secondaryNS
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
