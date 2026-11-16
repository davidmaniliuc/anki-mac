import AnkiKit
import AppKit
import SwiftUI

/// The sidebar's context menu and what its actions ask before they run. The
/// menu's contents come from `SidebarKind.actionGroups`; the changes
/// themselves are in BrowserModel+Sidebar.
extension BrowserSidebarController: NSMenuDelegate, NSTextFieldDelegate {
    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard outline.clickedRow >= 0, let clicked = outline.item(atRow: outline.clickedRow) as? Row else { return }
        let rows = clicked.item == nil ? [] : rowsActedOn(clicked)
        let items = rows.compactMap(\.item)
        for group in clicked.kind.actionGroups {
            let actions = group.filter { $0.isAvailable(for: items) }
            if actions.isEmpty { continue }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            for action in actions {
                if action == .search && items.count > 1 {
                    menu.addItem(searchSubmenu(items))
                } else {
                    let item = actionItem(action.title) { [weak self] in self?.perform(action, on: rows) }
                    item.isEnabled = isEnabled(action)
                    menu.addItem(item)
                }
            }
        }
    }

    /// The selected rows when the click landed on one of them, else just the
    /// clicked row, as in Finder.
    private func rowsActedOn(_ clicked: Row) -> [Row] {
        outline.selectedRowIndexes.contains(outline.clickedRow) ? selectedRows.filter { $0.item != nil } : [clicked]
    }

    private func actionItem(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuHandler(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = MenuHandler(handler)
        return item
    }

    @objc private func runMenuHandler(_ item: NSMenuItem) {
        (item.representedObject as? MenuHandler)?.run()
    }

    private func isEnabled(_ action: SidebarAction) -> Bool {
        switch action {
        case .addToSelectedNotes, .removeFromSelectedNotes: model.selection != nil
        default: true
        }
    }

    private func searchSubmenu(_ items: [SidebarItem]) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.addItem(actionItem(Tr.actionsAllSelected) { [weak self] in
            self?.model.search(items, joiner: .and)
        })
        submenu.addItem(actionItem(Tr.actionsAnySelected) { [weak self] in
            self?.model.search(items, joiner: .or)
        })
        let parent = NSMenuItem(title: Tr.actionsSearch, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    func deleteSelection() {
        let rows = selectedRows
        guard let kind = rows.first?.kind, kind.actionGroups.joined().contains(.delete),
            SidebarAction.delete.isAvailable(for: rows.compactMap(\.item))
        else { return }
        perform(.delete, on: rows)
    }

    // MARK: Actions

    private func perform(_ action: SidebarAction, on rows: [Row]) {
        let items = rows.compactMap(\.item)
        switch action {
        case .search:
            model.search(items, joiner: .and)
        case .rename:
            if let row = rows.first { beginRename(row) }
        case .renameWithParents:
            if let item = items.first { renameWithParents(item) }
        case .delete:
            delete(items)
        case .saveCurrentSearch:
            ask(
                sheetTitle(Tr.browsingSidebarSaveCurrentSearch), label: Tr.browsingPleaseGiveYourFilterAName,
                action: Tr.actionsSave
            ) { [weak self] name in
                guard let self else { return }
                model.saveCurrentSearch(as: name, update: false, confirmOverwrite: confirmOverwrite)
            }
        case .updateSavedSearch:
            if case .savedSearch(let name, _)? = items.first {
                model.saveCurrentSearch(as: name, update: true, confirmOverwrite: confirmOverwrite)
            }
        case .clearUnusedTags:
            model.clearUnusedTags()
        case .addToSelectedNotes, .removeFromSelectedNotes:
            let tags = items.compactMap { item -> String? in
                if case .tag(let name) = item { name } else { nil }
            }
            if let selection = model.selection {
                model.changeTags(of: selection, adding: action == .addToSelectedNotes, tags: tags.joined(separator: " "))
            }
        case .manageNotetypes:
            var id: Int64?
            if case .notetype(let notetypeID, _)? = items.first { id = notetypeID }
            NotetypeManagerWindowController.show(collection: model.collection, selecting: id)
        case .addNotes:
            if case .deck(let id, _)? = items.first {
                AddCardsWindowController.show(collection: model.collection, deckID: id)
            }
        }
    }

    private func delete(_ items: [SidebarItem]) {
        switch items.first?.kind {
        case .savedSearch:
            model.deleteSavedSearches(items.compactMap { if case .savedSearch(let name, _) = $0 { name } else { nil } })
        case .deck:
            model.deleteDecks(items.compactMap { if case .deck(let id, _) = $0 { id } else { nil } })
        case .tag:
            model.removeTags(items.compactMap { if case .tag(let name) = $0 { name } else { nil } })
        default:
            break
        }
    }

    // MARK: Renaming

    /// Edits the row's name where it is. For a deck or tag that is its last
    /// part; the parents stay, as desktop's in-place edit.
    private func beginRename(_ row: Row) {
        let index = outline.row(forItem: row)
        guard index >= 0, let cell = outline.view(atColumn: 0, row: index, makeIfNecessary: true) as? SidebarCell
        else { return }
        editing = row
        cancelledEdit = false
        cell.beginEditing(delegate: self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelledEdit = true
        control.window?.makeFirstResponder(outline)
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let row = editing else { return }
        editing = nil
        let index = outline.row(forItem: row)
        if index >= 0 {
            (outline.view(atColumn: 0, row: index, makeIfNecessary: false) as? SidebarCell)?.endEditing(title: row.title)
        }
        if !cancelledEdit { rename(row, to: field.stringValue) }
        Task { @MainActor in
            if outline.window?.firstResponder !== outline { outline.window?.makeFirstResponder(outline) }
        }
    }

    /// Drops an edit in progress, when a reload is about to replace its row.
    func cancelEdit() {
        guard editing != nil else { return }
        cancelledEdit = true
        outline.window?.makeFirstResponder(outline)
        editing = nil
    }

    /// `text` replaces the row's own name, whatever the kind. Quotes are
    /// dropped, as desktop does. An empty flag name brings back the default.
    private func rename(_ row: Row, to text: String) {
        let name = text.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let item = row.item else { return }
        if case .flag(let flag) = item {
            if name != row.title { model.renameFlag(flag, to: name) }
            return
        }
        guard !name.isEmpty, name != row.title else { return }
        switch item {
        case .deck(let id, _): model.renameDeck(id, to: item.namePrefix + name)
        case .tag(let full): model.renameTag(full, to: item.namePrefix + name)
        case .savedSearch(let old, _): model.renameSavedSearch(old, to: name, confirmOverwrite: confirmOverwrite)
        case .cardState, .flag, .notetype: break
        }
    }

    private func renameWithParents(_ item: SidebarItem) {
        guard let fullName = item.fullName else { return }
        let title = item.kind == .tag ? Tr.actionsRenameTag : Tr.actionsRenameDeck
        ask(title, label: Tr.actionsNewName, action: Tr.actionsRename, initial: fullName) { [weak self] text in
            let name = text.replacingOccurrences(of: "\"", with: "")
            guard let self, !name.isEmpty, name != fullName else { return }
            switch item {
            case .deck(let id, _): model.renameDeck(id, to: name)
            case .tag(let full): model.renameTag(full, to: name)
            default: break
            }
        }
    }

    // MARK: Prompts

    /// Desktop's one-line prompt as a sheet on the Browser, drawn as the
    /// note types' prompts: the command as the Headline, desktop's question
    /// as the row's title, and the action named for what it does.
    private func ask(
        _ title: String, label: String, action: String, initial: String = "", then submit: @escaping (String) -> Void
    ) {
        guard let content = outline.window?.contentViewController, content.presentedViewControllers?.isEmpty ?? true
        else { return }
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        host.rootView = AnyView(TextPromptSheet(
            title: title, label: rowTitle(label), action: action, initial: initial,
            close: { [weak host] in host?.dismiss(nil) }, submit: submit))
        host.sizingOptions = .preferredContentSize
        content.presentAsSheet(host)
    }

    private func confirmOverwrite(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = Tr.browsingConfirmSavedSearchOverwrite(name: name)
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: Tr.actionsCancel)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private final class MenuHandler {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}
