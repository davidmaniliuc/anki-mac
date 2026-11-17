import AnkiKit
import AppKit

/// The browser's table: an NSTableView, because SwiftUI's `Table` took seconds
/// to re-sort or replace 47,000 rows where this takes tens of milliseconds,
/// and it can tint whole rows.
///
/// It holds no rows itself: it asks the model for each visible row by index.
final class BrowserTableController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private let model: BrowserModel
    private let table = NSTableView()
    private let rowMenu = NSMenu()
    private let headerMenu = NSMenu()

    private var shownIDs = -1
    private var shownRows = -1
    private var shownMode: BrowserMode?
    private var shownColumns: [String] = []
    private var settingSort = false

    init(model: BrowserModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        table.style = .plain
        table.rowSizeStyle = .custom
        table.rowHeight = Theme.Browser.denseRowHeight
        // Cells pad their own text (`Theme.Browser.cellPadding`), so a
        // column is as wide as its cell and the wash can reach the edge.
        table.intercellSpacing = .zero
        // No stripes and no grid: hairlines and the selection wash tell rows
        // apart. The table's own alternating colours were drawn on the CPU
        // across the whole clip view, about 120 ms of the browser's first
        // paint, and the row views stay clear on the scroll view's canvas.
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.headerView = BrowserHeaderView(
            frame: NSRect(x: 0, y: 0, width: 0, height: Theme.Browser.headerHeight))
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        // The last column takes what the others leave, so the table always
        // reaches the editor, as Finder's list view does.
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        // Typing jumps to a row by its first column, which means little when
        // that column is a due date; desktop has no type-select either.
        table.allowsTypeSelect = false
        // Rows drag onto the sidebar's decks, tags and flags, and nowhere else.
        table.setDraggingSourceOperationMask([.move, .generic], forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.dataSource = self
        table.delegate = self
        rowMenu.delegate = self
        headerMenu.delegate = self
        table.menu = rowMenu
        table.headerView?.menu = headerMenu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.Palette.canvasNS
        // The band above keeps it clear of the toolbar; its safe area would
        // otherwise push the header down.
        scroll.automaticallyAdjustsContentInsets = false
        view = scroll
        model.selectRow = { [weak self] row in
            self?.table.selectRowIndexes([row], byExtendingSelection: false)
            self?.table.scrollRowToVisible(row)
        }
        track { [weak self] in
            guard let self else { return }
            update(
                idsVersion: model.idsVersion, rowsVersion: model.rowsVersion, mode: model.mode,
                columns: model.columns.map(\.key), sort: model.sort)
        }
    }

    private func update(idsVersion: Int, rowsVersion: Int, mode: BrowserMode, columns: [String], sort: BrowserSort) {
        if mode != shownMode || columns != shownColumns {
            rebuildColumns(table, mode: mode, keys: columns)
            table.reloadData()
        }
        showSortIndicator(table, sort)
        if idsVersion != shownIDs {
            shownIDs = idsVersion
            shownRows = rowsVersion
            let keep = model.takeSelectionToRestore()
            refreshRows(table)
            table.selectRowIndexes(keep, byExtendingSelection: false)
            table.scrollRowToVisible(keep.first ?? 0)
            reportPaint(table, idsVersion: idsVersion)
        } else if rowsVersion != shownRows {
            shownRows = rowsVersion
            refreshRows(table)
        }
    }

    /// Puts the current rows into the views already on screen. Cheaper
    /// than `reloadData`, which removes every cell view and adds it back,
    /// and that churn cost more than fetching and drawing the rows.
    private func refreshRows(_ table: NSTableView) {
        table.noteNumberOfRowsChanged()
        table.enumerateAvailableRowViews { rowView, row in
            (rowView as? BrowserRowView)?.color = model.row(at: row)?.color ?? .default
            for column in 0..<table.numberOfColumns {
                if let cell = table.view(atColumn: column, row: row, makeIfNecessary: false) as? BrowserCell {
                    configure(cell, row: row, column: table.tableColumns[column])
                }
            }
        }
    }

    private func configure(_ cell: BrowserCell, row: Int, column: NSTableColumn) {
        guard let index = shownColumns.firstIndex(of: column.identifier.rawValue),
            let data = model.row(at: row), data.cells.indices.contains(index)
        else {
            cell.showMissing()
            return
        }
        let content = data.cells[index]
        let column = model.columns[safe: index]
        // A deck's path reads as the main window writes it, "M1 › FSGBD".
        let text = column?.key == "deck" ? content.text.replacing("::", with: " › ") : content.text
        cell.show(
            text, elide: content.elideMode, centered: column?.alignment == .center,
            numeric: column?.isNumeric(shownMode ?? model.mode) ?? false)
    }

    private func rebuildColumns(_ table: NSTableView, mode: BrowserMode, keys: [String]) {
        shownMode = mode
        shownColumns = keys
        // Autosave restores widths and order when the name is set, so the
        // columns must be in place first; clearing it stops the removals
        // below from being saved as the user's choice.
        table.autosaveName = nil
        table.tableColumns.forEach(table.removeTableColumn)
        for key in keys {
            guard let column = model.columns.first(where: { $0.key == key }) else { continue }
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            tableColumn.headerCell = BrowserHeaderCell(textCell: column.label(mode))
            tableColumn.headerToolTip = column.tooltip(mode)
            tableColumn.width = Theme.Browser.columnWidth
            tableColumn.minWidth = Theme.Browser.columnMinWidth
            // A title lines up with its column's text: on the trailing edge
            // over counts and dates, wherever upstream sets them, or centred.
            if column.isNumeric(mode) {
                tableColumn.headerCell.alignment = .right
            } else if column.alignment == .center {
                tableColumn.headerCell.alignment = .center
            }
            if column.sorting(mode) != .none {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            }
            table.addTableColumn(tableColumn)
        }
        table.autosaveTableColumns = true
        table.autosaveName = "Browser.\(mode.rawValue)"
        table.sizeLastColumnToFit()
    }

    private func showSortIndicator(_ table: NSTableView, _ sort: BrowserSort) {
        let descriptor = NSSortDescriptor(key: sort.column, ascending: !sort.reverse)
        guard table.sortDescriptors.first != descriptor else { return }
        settingSort = true
        table.sortDescriptors = shownColumns.contains(sort.column) ? [descriptor] : []
        settingSort = false
    }

    /// For the bench: reports once the new rows are drawn. Forcing the
    /// window's layout and display here does what the end of this run
    /// loop turn would do anyway, so the point it marks is observable
    /// rather than earlier than the real paint.
    private func reportPaint(_ table: NSTableView, idsVersion: Int) {
        guard model.onRowsPainted != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = table.window else { return }
            window.displayIfNeeded()
            CATransaction.flush()
            let visible = table.rows(in: table.visibleRect)
            let laidOut = (visible.lowerBound..<visible.upperBound).filter {
                table.view(atColumn: 0, row: $0, makeIfNecessary: false) != nil
            }.count
            model.onRowsPainted?(idsVersion, laidOut)
        }
    }

    // MARK: Data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.ids.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let cell = tableView.makeView(withIdentifier: BrowserCell.identifier, owner: nil) as? BrowserCell ?? BrowserCell()
        configure(cell, row: row, column: tableColumn)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: BrowserRowView.identifier, owner: nil) as? BrowserRowView
            ?? BrowserRowView()
        view.color = model.row(at: row)?.color ?? .default
        return view
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard model.ids.indices.contains(row) else { return nil }
        return BrowserDrag.item(model.mode, id: model.ids[row])
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !settingSort, let first = tableView.sortDescriptors.first, let key = first.key else { return }
        model.sortRequested(column: key, ascending: first.ascending)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        model.selectionChanged(table.selectedRowIndexes, current: table.selectedRow >= 0 ? table.selectedRow : nil)
    }

    // MARK: Menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === headerMenu {
            buildHeaderMenu(menu)
        } else {
            buildRowMenu(menu)
        }
    }

    /// Every column the mode offers, checked when shown.
    private func buildHeaderMenu(_ menu: NSMenu) {
        let mode = model.mode
        let shown = Set(shownColumns)
        for column in model.allColumns.sorted(by: { $0.label(mode).localizedStandardCompare($1.label(mode)) == .orderedAscending }) {
            let key = column.key
            let item = menuItem(column.label(mode)) { [weak self] in self?.model.toggleColumn(key) }
            item.state = shown.contains(key) ? .on : .off
            // A table needs at least one column.
            item.isEnabled = !(shown.contains(key) && shown.count == 1)
            menu.addItem(item)
        }
    }

    private final class Action {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    private func menuItem(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Action(run)
        return item
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        (sender.representedObject as? Action)?.run()
    }

    /// The Cards menu's commands, for the clicked rows.
    private func buildRowMenu(_ menu: NSMenu) {
        guard table.clickedRow >= 0 else { return }
        // As Mail and Finder: right-clicking outside the selection acts on the clicked row.
        if !table.selectedRowIndexes.contains(table.clickedRow) {
            table.selectRowIndexes([table.clickedRow], byExtendingSelection: false)
        }
        let card = model.commandCard
        let flags = NSMenu()
        for flag in CardFlag.assignable {
            let item = menuItem(flag.title) { [weak self] in self?.model.toggleFlag(flag) }
            item.state = card?.flag == flag ? .on : .off
            flags.addItem(item)
        }
        let flagItem = NSMenuItem(title: Tr.browsingFlag, action: nil, keyEquivalent: "")
        flagItem.submenu = flags
        menu.addItem(flagItem)

        let suspend = menuItem(Tr.actionsSuspendCard) { [weak self] in self?.model.toggleSuspend() }
        suspend.state = card?.isSuspended == true ? .on : .off
        menu.addItem(suspend)
        let bury = menuItem(Tr.studyingBuryCard) { [weak self] in self?.model.toggleBury() }
        bury.state = card?.isBuried == true ? .on : .off
        menu.addItem(bury)
        menu.addItem(menuItem("Change Deck…") { [weak self] in self?.model.askChangeDeck() })
        menu.addItem(menuItem("Set Due Date…") { [weak self] in self?.model.askSetDueDate() })
        menu.addItem(menuItem("Reset…") { [weak self] in self?.model.askForget() })
        menu.addItem(menuItem("Reposition…") { [weak self] in self?.model.askReposition() })
        menu.addItem(.separator())
        let mark = menuItem("Mark Note") { [weak self] in self?.model.toggleMark() }
        mark.state = card?.isMarked == true ? .on : .off
        menu.addItem(mark)
        menu.addItem(menuItem("Add Tags…") { [weak self] in self?.model.askTags(adding: true) })
        menu.addItem(menuItem("Remove Tags…") { [weak self] in self?.model.askTags(adding: false) })
        menu.addItem(menuItem("Find and Replace…") { [weak self] in self?.model.askFindAndReplace() })
        menu.addItem(menuItem("Change Note Type…") { [weak self] in self?.model.askChangeNotetype() })
        menu.addItem(.separator())
        menu.addItem(menuItem("Delete Notes…") { [weak self] in self?.model.deleteNotes() })
    }
}

private final class BrowserCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("BrowserCell")
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.font = Theme.Browser.cellFont
        label.textColor = Theme.Palette.textNS
        addSubview(label)
        textField = label
    }

    // Frames, not constraints: Auto Layout in every cell cost more than the
    // rest of a reload.
    override func layout() {
        super.layout()
        let padding = Theme.Browser.cellPadding - Theme.Browser.labelInset
        let height = Self.lineHeight
        label.frame = NSRect(
            x: padding, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 2 * padding),
            height: height)
    }

    private static let lineHeight = {
        let field = NSTextField(labelWithString: "Xg")
        field.font = Theme.Browser.cellFont
        return field.intrinsicContentSize.height
    }()

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ text: String, elide: Anki_Search_BrowserRow.Cell.TextElideMode, centered: Bool, numeric: Bool) {
        label.stringValue = text
        // A figure is in the rounded face; words in a column of figures
        // ("New #198", "(learning)") aren't.
        setFont(numeric && text.first?.isNumber == true ? Theme.Browser.numberFont : Theme.Browser.cellFont)
        label.textColor = Theme.Palette.textNS
        // Counts and dates keep to the trailing edge, so their digits line up.
        label.alignment = numeric ? .right : centered ? .center : .natural
        label.lineBreakMode = switch elide {
        case .elideLeft: .byTruncatingHead
        case .elideMiddle: .byTruncatingMiddle
        default: .byTruncatingTail
        }
    }

    /// The card or note was deleted since the search ran.
    func showMissing() {
        label.stringValue = "(deleted)"
        setFont(Theme.Browser.cellFont)
        label.textColor = Theme.Palette.secondaryNS
        label.alignment = .natural
    }

    private func setFont(_ font: NSFont) {
        if label.font !== font { label.font = font }
    }
}

/// Selects with a wash, and tints the whole row for flags, marks, suspension
/// and burying, as desktop. The tint takes the wash's shape and goes over it,
/// so a selected flagged row still shows its flag.
private final class BrowserRowView: WashRowView {
    static let identifier = NSUserInterfaceItemIdentifier("BrowserRow")

    var color: Anki_Search_BrowserRow.Color = .default {
        didSet { if color != oldValue { needsDisplay = true } }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        // One backing store per row instead of one per cell.
        canDrawSubviewsIntoLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if let tint = Theme.Browser.rowColor(color) { fillWash(tint) }
    }
}

/// A column's title in Pencil with its sort arrow, over the canvas, with a
/// hairline under the row of them instead of the system's header material
/// and its separators.
private final class BrowserHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        guard let table = tableView else { return }
        Theme.Palette.canvasNS.setFill()
        dirtyRect.fill()
        let sort = table.sortDescriptors.first
        for index in 0..<table.numberOfColumns {
            let frame = headerRect(ofColumn: index)
            guard frame.intersects(dirtyRect), let cell = table.tableColumns[index].headerCell as? BrowserHeaderCell
            else { continue }
            let key = table.tableColumns[index].sortDescriptorPrototype?.key
            cell.sortAscending = key != nil && key == sort?.key ? sort?.ascending : nil
            cell.draw(withFrame: frame, in: self)
        }
        Theme.Palette.hairlineNS.setFill()
        NSRect(x: bounds.minX, y: isFlipped ? bounds.maxY - 1 : bounds.minY, width: bounds.width, height: 1)
            .intersection(dirtyRect).fill()
    }
}

private final class BrowserHeaderCell: NSTableHeaderCell {
    /// nil when the table isn't sorted by this column.
    var sortAscending: Bool?

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let padding = Theme.Browser.cellPadding
        var text = cellFrame.insetBy(dx: padding, dy: 0)
        let indicator = sortIndicatorRect(forBounds: cellFrame)
        if sortAscending != nil {
            text.size.width = min(text.width, indicator.minX - Theme.Browser.headerIndicatorGap - text.minX)
        }
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.Browser.headerFont, .foregroundColor: Theme.Palette.secondaryNS, .paragraphStyle: style,
        ]
        let title = stringValue as NSString
        let height = title.size(withAttributes: attributes).height
        text.origin.y += ((text.height - height) / 2).rounded()
        text.size.height = height
        title.draw(in: text, withAttributes: attributes)
        if let sortAscending {
            drawSortIndicator(withFrame: indicator, in: controlView, ascending: sortAscending, priority: 0)
        }
    }
}
