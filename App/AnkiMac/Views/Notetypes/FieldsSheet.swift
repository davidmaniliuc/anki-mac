import AnkiKit
import AppKit
import SwiftUI

/// Desktop's Fields dialog (aqt/fields.py), drawn as Deck Options'
/// settings: the fields as a list on the left, named in their rows, then
/// the chosen field's settings as rows under hairlines, and at the foot
/// what can't be done as a caption beside Cancel and Save.
struct FieldsSheet: View {
    private struct Row: Identifiable {
        let id = UUID()
        var field: Anki_Notetypes_Notetype.Field
    }

    private enum Editing: Equatable { case add, rename(UUID) }

    let original: Anki_Notetypes_Notetype
    let useCount: UInt32
    /// Writes the edited note type; true when it was saved.
    let save: (Anki_Notetypes_Notetype) async -> Bool
    @State private var rows: [Row]
    @State private var selection: UUID?
    @State private var sortID: UUID?
    @State private var editing: Editing?
    @State private var draft = ""
    @State private var repositioning = false
    /// Desktop's refusal (the last field, a required one), until the next change.
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    init(notetype: Anki_Notetypes_Notetype, useCount: UInt32, save: @escaping (Anki_Notetypes_Notetype) async -> Bool) {
        original = notetype
        self.useCount = useCount
        self.save = save
        let rows = notetype.fields.map { Row(field: $0) }
        _rows = State(initialValue: rows)
        _selection = State(initialValue: rows.first?.id)
        let sort = Int(notetype.config.sortFieldIdx)
        _sortID = State(initialValue: rows.indices.contains(sort) ? rows[sort].id : rows.first?.id)
    }

    private var selectedIndex: Int? { rows.firstIndex { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Tr.fieldsFieldsFor(val: original.name))
                .font(Theme.Fonts.panelTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Theme.DeckOptions.margin)
                .padding(.top, Theme.DeckOptions.margin)
                .padding(.bottom, Theme.Spacing.medium)
            HStack(spacing: 0) {
                fieldList
                    .frame(width: Theme.Notetypes.fieldListWidth)
                Theme.Palette.hairline.frame(width: 1)
                if let index = selectedIndex {
                    settings(index)
                } else {
                    Spacer()
                }
            }
            Theme.Palette.hairline.frame(height: 1)
            foot
        }
        .frame(width: Theme.Notetypes.fieldsSheetSize.width, height: Theme.Notetypes.fieldsSheetSize.height)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onChange(of: rows.map(\.field)) { message = nil }
        .onChange(of: selection) { message = nil }
        .sheet(isPresented: $repositioning) {
            TextPromptSheet(
                title: Tr.actionsReposition, label: rowTitle(Tr.fieldsNewPosition1(val: String(rows.count))),
                action: Tr.actionsReposition, initial: String((selectedIndex ?? 0) + 1), number: true,
                problem: { position(in: $0) == nil ? "" : nil }
            ) { text in
                if let index = selectedIndex, let position = position(in: text) {
                    rows.insert(rows.remove(at: index), at: position - 1)
                }
            }
        }
    }

    // MARK: List

    /// The fields in their order, which a drag changes; the sort field
    /// carries a small sort glyph. Under them, the Mac's + and − and a
    /// menu with Rename and Reposition.
    private var fieldList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(rows) { row in
                    Group {
                        if editing == .rename(row.id) {
                            nameField
                        } else {
                            FieldRow(
                                name: row.field.name, sorts: row.id == sortID, selected: row.id == selection,
                                editing: editing != nil
                            ) {
                                selection = row.id
                            } rename: {
                                if editing == nil { begin(.rename(row.id)) }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(
                        top: 0, leading: Theme.Layout.washOutset, bottom: 0, trailing: Theme.Layout.washOutset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                if editing == .add {
                    nameField
                        .listRowInsets(EdgeInsets(
                            top: 0, leading: Theme.Layout.washOutset, bottom: 0, trailing: Theme.Layout.washOutset))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, Theme.Notetypes.fieldRowHeight)
            .accessibilityLabel(Tr.notetypesFields)
            // Up, Down and Delete as shortcuts, as the note type list's;
            // Return stays Save's. Off while a name is typed, so the field
            // has them.
            .background {
                Group {
                    Button("") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                    Button("") { step(1) }.keyboardShortcut(.downArrow, modifiers: [])
                    Button("") { delete() }.keyboardShortcut(.delete, modifiers: [])
                }
                .opacity(0)
                .accessibilityHidden(true)
                .disabled(editing != nil || selectedIndex == nil)
            }
            HStack(spacing: Theme.Spacing.xxSmall) {
                IconButton("plus", help: Tr.fieldsAddField) { begin(.add) }
                IconButton("minus", help: Tr.actionsDelete) { delete() }
                    .disabled(selectedIndex == nil)
                Menu {
                    Button(Tr.actionsRename) { if let selection { begin(.rename(selection)) } }
                    Button("\(Tr.actionsReposition)…") { repositioning = true }
                        .disabled(rows.count < 2)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(Theme.Notetypes.addSymbol)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(width: Theme.Notetypes.addSize.width, height: Theme.Notetypes.addSize.height)
                        .modifier(MenuHover(shape: RoundedRectangle(cornerRadius: Theme.Layout.rowRadius), inset: 0))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(selectedIndex == nil)
                .help(Tr.actionsOptions)
                .accessibilityLabel(Tr.actionsOptions)
                Spacer()
            }
            .disabled(editing != nil)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.xSmall)
        }
    }

    private var nameField: some View {
        RowNameField(
            name: $draft, problem: problem, font: Theme.DeckOptions.rowFont, height: Theme.Notetypes.fieldRowHeight,
            prompt: rowTitle(Tr.fieldsFieldName), end: finishEditing)
    }

    // MARK: Settings

    /// Desktop's options for one field, as Deck Options' rows: sorting,
    /// the editor's font, the editor's switches, then the description.
    private func settings(_ index: Int) -> some View {
        let field = Binding { rows[index].field } set: { rows[index].field = $0 }
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.DeckOptions.sectionGap) {
                OptionSection {
                    OptionRow(title: Tr.fieldsSortByThisFieldInThe, revertible: false) {
                        SwitchControl(
                            title: Tr.fieldsSortByThisFieldInThe,
                            isOn: Binding { sortID == rows[index].id } set: { if $0 { sortID = rows[index].id } })
                        // One field always sorts: choosing another moves it.
                        .disabled(sortID == rows[index].id)
                    }
                }
                OptionSection(title: Tr.fieldsEditingFont) {
                    OptionRow(title: rowTitle(Tr.fieldsFont), revertible: false) {
                        OptionPicker(selection: field.config.fontName, choices: fontFamilies(keeping: field.config.fontName.wrappedValue))
                            .frame(maxWidth: Theme.Notetypes.fontMenuMaxWidth, alignment: .trailing)
                    }
                    OptionRow(title: rowTitle(Tr.fieldsSize), revertible: false) {
                        NumberField(
                            value: Binding { Double(field.config.fontSize.wrappedValue) } set: {
                                field.config.fontSize.wrappedValue = UInt32($0)
                            },
                            range: 6...200)
                    }
                }
                OptionSection {
                    switchRow(Tr.fieldsReverseTextDirectionRtl, field.config.rtl)
                    switchRow(Tr.fieldsHtmlByDefault, field.config.plainText)
                    switchRow(Tr.fieldsCollapseByDefault, field.config.collapsed)
                    switchRow(Tr.fieldsExcludeFromSearch, field.config.excludeFromSearch)
                }
                OptionSection {
                    OptionRow(title: Tr.fieldsDescription, help: Tr.fieldsDescriptionPlaceholder, revertible: false) {
                        OptionTextField(text: field.config.description_p, prompt: Tr.fieldsDescriptionPlaceholder)
                            .frame(width: Theme.Notetypes.descriptionFieldWidth)
                    }
                }
            }
            .padding(.horizontal, Theme.DeckOptions.margin)
            .padding(.vertical, Theme.Spacing.small)
        }
        .scrollEdgeEffectHidden(true, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        // Each field's settings start at the top.
        .id(rows[index].id)
    }

    private func switchRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        OptionRow(title: title, revertible: false) { SwitchControl(title: title, isOn: isOn) }
    }

    // MARK: Foot

    private var foot: some View {
        HStack(spacing: Theme.Spacing.small) {
            if let message {
                OptionWarning(text: message, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            // Off while a name is typed, so Return and Esc are the field's.
            DialogButtons(
                action: Tr.actionsSave, disabled: editing != nil, cancelDisabled: editing != nil,
                cancel: cancel, submit: commit)
        }
        .padding(.horizontal, Theme.DeckOptions.margin)
        .padding(.vertical, Theme.Spacing.medium)
    }

    // MARK: Actions

    /// Up and Down move the selection, stopping at the ends.
    private func step(_ offset: Int) {
        guard let index = selectedIndex else { return }
        selection = rows[min(max(index + offset, 0), rows.count - 1)].id
    }

    private func begin(_ kind: Editing) {
        switch kind {
        case .add: draft = ""
        case .rename(let id): draft = rows.first { $0.id == id }?.field.name ?? ""
        }
        editing = kind
    }

    /// Why the typed name can't be used, as it is typed: desktop's checks
    /// and its words. Nothing while it's empty.
    private var problem: String? {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let editing, !name.isEmpty else { return nil }
        if let first = name.first, "#^/".contains(first) { return Tr.fieldsNameFirstLetterNotValid }
        if name.contains(where: { ":\"{}".contains($0) }) { return Tr.fieldsNameInvalidLetter }
        let renamed: UUID? = if case .rename(let id) = editing { id } else { nil }
        if rows.contains(where: { $0.id != renamed && $0.field.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return Tr.fieldsThatFieldNameIsAlreadyUsed
        }
        return nil
    }

    /// Return keeps the name, unless it has a problem, which stays under it
    /// with the typing kept; clicking away keeps it only if it can be used,
    /// and Esc puts things back.
    private func finishEditing(_ ending: RowNameField.Ending) {
        guard let kind = editing else { return }
        if ending == .submit, problem != nil {
            NSSound.beep()
            return
        }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = problem == nil && !name.isEmpty
        editing = nil
        guard ending != .cancel, usable else { return }
        switch kind {
        case .add:
            var field = Anki_Notetypes_Notetype.Field()
            field.name = name
            field.config.fontName = "Arial"
            field.config.fontSize = 20
            let row = Row(field: field)
            rows.append(row)
            selection = row.id
        case .rename(let id):
            if let index = rows.firstIndex(where: { $0.id == id }) { rows[index].field.name = name }
        }
    }

    private func position(in text: String) -> Int? {
        guard let position = Int(text.trimmingCharacters(in: .whitespaces)), (1...rows.count).contains(position)
        else { return nil }
        return position
    }

    /// Desktop's refusals stay at the foot; a real deletion asks first.
    private func delete() {
        guard let index = selectedIndex else { return }
        if rows.count < 2 {
            message = Tr.fieldsNotesRequireAtLeastOneField
            return
        }
        if rows[index].field.config.preventDeletion {
            message = Tr.fieldsFieldIsRequired
            return
        }
        Task {
            guard await NotetypeAlerts.confirm(
                Tr.fieldsDeleteFieldFrom(val: Tr.browsingNoteCount(count: Int(useCount))),
                confirm: Tr.actionsDelete, destructive: true),
                let index = selectedIndex
            else { return }
            let removed = rows.remove(at: index)
            if sortID == removed.id { sortID = rows.first?.id }
            selection = rows[min(index, rows.count - 1)].id
        }
    }

    private func cancel() {
        guard isEdited else { dismiss(); return }
        Task {
            if await NotetypeAlerts.confirm(Tr.cardTemplatesDiscardChanges, confirm: Tr.actionsDiscard, destructive: true) {
                dismiss()
            }
        }
    }

    private var isEdited: Bool { edited != original }

    private var edited: Anki_Notetypes_Notetype {
        var edited = original
        edited.fields = rows.map(\.field)
        edited.config.sortFieldIdx = UInt32(rows.firstIndex { $0.id == sortID } ?? 0)
        return edited
    }

    private func commit() {
        let edited = edited
        Task {
            if await save(edited) { dismiss() }
        }
    }
}

/// A field in the list, as a sidebar row: its name in Ink, a sort glyph
/// on the sort field, the selection wash on the chosen one. A click
/// selects it, a double click renames it.
private struct FieldRow: View {
    let name: String
    let sorts: Bool
    let selected: Bool
    let editing: Bool
    let select: () -> Void
    let rename: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Text(name)
                .font(Theme.DeckOptions.rowFont)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if sorts {
                Image(systemName: "arrow.up.arrow.down")
                    .font(Theme.DeckOptions.globeSymbol)
                    .foregroundStyle(Theme.Palette.secondary)
                    .help(Tr.fieldsSortByThisFieldInThe)
            }
        }
        .listRow(
            height: Theme.Notetypes.fieldRowHeight,
            wash: editing ? .clear : selected ? Theme.Palette.selection : hovered ? Theme.Palette.hover : .clear)
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onClick(select, doubleClick: rename)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(sorts ? Tr.fieldsSortByThisFieldInThe : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: Tr.actionsRename, rename)
    }
}
