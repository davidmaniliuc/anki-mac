import AnkiKit
import AppKit
import SwiftUI

/// Desktop's Manage Note Types dialog (aqt/models.py), drawn as the
/// profile list: "Note Types" in the band with Add as a quiet menu, the
/// note types as rows with their note counts, and desktop's buttons as
/// chips at the foot. A note type is named in its row, as a deck is in the
/// sidebar, not in desktop's prompt.
struct NotetypeManagerView: View {
    @Bindable var model: NotetypeManager
    let chrome: BandChrome
    let collection: CollectionModel
    @State private var editing: Editing?
    @State private var draft = ""
    @State private var optionsFor: Anki_Notetypes_Notetype?
    @State private var fieldsFor: Anki_Notetypes_Notetype?

    private enum Editing: Equatable {
        case add(NotetypeManager.Stock), clone(Int64), rename(Int64)
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            list
            foot
        }
        .background(Theme.Palette.canvas)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .task { await model.refresh() }
        .alert(
            model.failure?.title ?? "",
            isPresented: Binding { model.failure != nil } set: { if !$0 { model.failure = nil } }
        ) {
            Button(Tr.customStudyOk) {}
        } message: {
            Text(verbatim: model.failure?.detail ?? "")
        }
        .sheet(item: $fieldsFor) { notetype in
            FieldsSheet(notetype: notetype, useCount: model.selected?.useCount ?? 0) { edited in
                await model.confirmAndSave(old: notetype, new: edited)
            }
        }
        .sheet(item: $optionsFor) { notetype in
            NotetypeOptionsSheet(notetype: notetype) { changed in Task { await model.save(changed) } }
        }
    }

    // MARK: Band

    /// The window's name after the traffic lights, and Add at the trailing
    /// edge, where Add Cards keeps its History.
    private var band: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Text(Tr.notetypesNoteTypes)
                .font(Theme.Band.titleFont)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.small)
            addMenu
        }
        // Clear of the traffic lights, which in full screen come down over
        // the band in a pill of their own.
        .padding(.leading, chrome.fullScreen ? Theme.Spacing.medium : Theme.Band.leading)
        .padding(.trailing, Theme.Spacing.medium)
        .frame(height: Theme.Band.height)
        .titleBarBand()
    }

    /// Desktop's Add list: the stock note types, then a clone of each one.
    private var addMenu: some View {
        Menu {
            Section(Tr.notetypesAddNoteType) {
                ForEach(NotetypeManager.Stock.allCases, id: \.self) { stock in
                    Button(Tr.notetypesAdd(val: stock.name)) { add(stock) }
                }
            }
            Section {
                ForEach(model.entries) { entry in
                    Button(Tr.notetypesClone(val: entry.name)) { begin(.clone(entry.id)) }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(Theme.Notetypes.addSymbol)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(width: Theme.Notetypes.addSize.width, height: Theme.Notetypes.addSize.height)
                .modifier(MenuHover(shape: RoundedRectangle(cornerRadius: Theme.Layout.rowRadius), inset: 0))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(editing != nil)
        .help(Tr.notetypesAddNoteType)
        .accessibilityLabel(Tr.notetypesAddNoteType)
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        if editing == .rename(entry.id) {
                            nameField
                        } else {
                            NotetypeRow(
                                entry: entry, selected: entry.id == model.selectedID, editing: editing != nil
                            ) {
                                model.selectedID = entry.id
                            } rename: {
                                if editing == nil { begin(.rename(entry.id)) }
                            }
                            .contextMenu { rowMenu(entry.id) }
                        }
                    }
                    if isAdding {
                        nameField.id(Self.newRow)
                    }
                }
                .padding(.horizontal, Theme.Notetypes.margin)
                .padding(.vertical, Theme.Spacing.small)
            }
            .scrollEdgeEffectHidden(true, for: .vertical)
            .onChange(of: isAdding) { _, adding in
                if adding { scroller.scrollTo(Self.newRow, anchor: .bottom) }
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { scroller.scrollTo(id) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Tr.notetypesNoteTypes)
        // Up, Down, Return and Delete as shortcuts rather than key presses,
        // as the profile list's; off while a name is typed, so the field has them.
        .background {
            Group {
                Button("") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { step(1) }.keyboardShortcut(.downArrow, modifiers: [])
                // Return renames, as in Finder.
                Button("") { if let id = model.selectedID { begin(.rename(id)) } }
                    .keyboardShortcut(.return, modifiers: [])
                Button("") { if let id = model.selectedID { delete(id) } }
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
            .disabled(editing != nil || model.selected == nil)
        }
    }

    private static let newRow = "new"

    private var isAdding: Bool {
        switch editing {
        case .add, .clone: true
        default: false
        }
    }

    private var nameField: some View {
        RowNameField(
            name: $draft, problem: nil, font: Theme.DeckOptions.rowFont, height: Theme.Notetypes.rowHeight,
            end: finishEditing)
    }

    @ViewBuilder
    private func rowMenu(_ id: Int64) -> some View {
        Button("\(Tr.notetypesFields)…") { model.selectedID = id; load { fieldsFor = $0 } }
        Button("\(Tr.notetypesCards)…") { model.selectedID = id; openCards() }
        Button("\(Tr.notetypesOptions)…") { model.selectedID = id; load { optionsFor = $0 } }
        Divider()
        Button(Tr.actionsRename) { begin(.rename(id)) }
        // Off with one note type left, as the foot's.
        Button(Tr.actionsDelete) { delete(id) }
            .disabled(model.entries.count < 2)
    }

    // MARK: Foot

    /// Desktop's buttons: what opens an editor first, then Rename and,
    /// set a little apart, Delete. The foot stays on the canvas, as the
    /// text import sheet's does, with no hairline over it.
    private var foot: some View {
        HStack(spacing: Theme.Spacing.small) {
            Button("\(Tr.notetypesFields)…") { load { fieldsFor = $0 } }
            Button("\(Tr.notetypesCards)…") { openCards() }
            Button("\(Tr.notetypesOptions)…") { load { optionsFor = $0 } }
            Spacer(minLength: Theme.Spacing.small)
            Button(Tr.actionsRename) { if let id = model.selectedID { begin(.rename(id)) } }
                .help("\(Tr.actionsRename) (\u{21A9})")
            // Off with one note type left: desktop's reason is its help tag.
            Button(Tr.actionsDelete) { if let id = model.selectedID { delete(id) } }
                .disabled(model.entries.count < 2)
                .help(model.entries.count < 2 ? Tr.notetypesPleaseAddAnotherNoteTypeFirst : "\(Tr.actionsDelete) (\u{232B})")
                .padding(.leading, Theme.Spacing.small)
        }
        .buttonStyle(ChipButtonStyle())
        .disabled(model.selected == nil || editing != nil)
        .padding(.horizontal, Theme.Notetypes.margin)
        .padding(.vertical, Theme.Spacing.medium)
    }

    // MARK: Actions

    /// Up and Down move the selection, stopping at the ends.
    private func step(_ offset: Int) {
        let ids = model.entries.map(\.id)
        guard !ids.isEmpty else { return }
        let index = model.selectedID.flatMap { ids.firstIndex(of: $0) } ?? (offset > 0 ? -1 : ids.count)
        model.selectedID = ids[min(max(index + offset, 0), ids.count - 1)]
    }

    private func add(_ stock: NotetypeManager.Stock) {
        // Image Occlusion has a fixed name, so it is added without asking.
        if stock == .imageOcclusion {
            Task { await model.add(stock, name: stock.name) }
        } else {
            begin(.add(stock))
        }
    }

    /// The row starts with desktop's suggested name, selected, so typing
    /// replaces it.
    private func begin(_ kind: Editing) {
        switch kind {
        case .add(let stock): draft = stock.name
        case .clone(let id): draft = model.defaultName(cloning: id)
        case .rename(let id): draft = model.entries.first { $0.id == id }?.name ?? ""
        }
        editing = kind
    }

    /// Return or clicking away keeps the name; Esc puts things back.
    private func finishEditing(_ ending: RowNameField.Ending) {
        guard let kind = editing else { return }
        editing = nil
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard ending != .cancel, !name.isEmpty else { return }
        Task {
            switch kind {
            case .add(let stock): await model.add(stock, name: name)
            case .clone(let id): await model.clone(id, name: name)
            case .rename(let id):
                guard name != model.entries.first(where: { $0.id == id })?.name else { return }
                await model.rename(id, to: name)
            }
        }
    }

    /// Desktop asks whether to delete, then whether to force a full sync;
    /// one alert asks both, the sync's cost under the question.
    private func delete(_ id: Int64) {
        guard let entry = model.entries.first(where: { $0.id == id }), model.entries.count > 1 else { return }
        Task {
            let question = entry.useCount > 0 ? Tr.notetypesDeleteThisNoteTypeAndAll : Tr.notetypesDeleteThisUnusedNoteType
            let cost = await NotetypeAlerts.schemaCost(model.backend)
            guard await NotetypeAlerts.confirm(question, detail: cost, confirm: Tr.actionsDelete, destructive: true)
            else { return }
            await model.remove(id)
        }
    }

    private func openCards() {
        guard let entry = model.selected else { return }
        load { notetype in
            CardTemplatesWindowController.show(
                manager: model, notetype: notetype, useCount: entry.useCount, mediaFolder: collection.paths?.mediaFolder)
        }
    }

    /// Loads the selected note type fresh, for an editor to work on.
    private func load(_ present: @escaping (Anki_Notetypes_Notetype) -> Void) {
        guard let id = model.selectedID else { return }
        Task {
            do { present(try await model.notetype(id)) } catch { model.failure = ActionFailure("Couldn’t open the note type", error: error) }
        }
    }
}

extension Anki_Notetypes_Notetype: @retroactive Identifiable {}

/// A note type in the list: its name in Ink and how many notes use it in
/// Pencil, the number in the rounded face. A click selects it, a double
/// click renames it, as desktop's.
private struct NotetypeRow: View {
    let entry: NotetypeManager.Entry
    let selected: Bool
    let editing: Bool
    let select: () -> Void
    let rename: () -> Void
    @State private var hovered = false

    var body: some View {
        let count = Tr.browsingNoteCount(count: Int(entry.useCount))
        HStack(spacing: Theme.Spacing.small) {
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.small)
            Text(figures(count))
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .font(Theme.DeckOptions.rowFont)
        .listRow(
            height: Theme.Notetypes.rowHeight,
            wash: editing ? .clear : selected ? Theme.Palette.selection : hovered ? Theme.Palette.hover : .clear)
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onClick(select, doubleClick: rename)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.name)
        .accessibilityValue(count)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: Tr.actionsRename, rename)
    }
}
