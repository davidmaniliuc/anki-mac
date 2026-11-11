import AnkiKit
import SwiftUI

/// Desktop's Fields dialog (aqt/fields.py): add, delete, rename and reposition
/// fields, choose the sort field, and set each field's editing options.
struct FieldsSheet: View {
    private struct Row: Identifiable {
        let id = UUID()
        var field: Anki_Notetypes_Notetype.Field
    }

    let original: Anki_Notetypes_Notetype
    let useCount: UInt32
    /// Writes the edited note type; true when it was saved.
    let save: (Anki_Notetypes_Notetype) async -> Bool
    @State private var rows: [Row]
    @State private var selection: UUID?
    @State private var sortID: UUID?
    @State private var prompt: Prompt?
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    private struct Prompt: Identifiable {
        enum Kind { case add, rename, reposition }
        let id = UUID()
        let kind: Kind
        let title: String
        let initial: String
    }

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
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(rows) { row in Text(row.field.name).tag(row.id) }
                            .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .frame(width: Theme.Notetypes.fieldListWidth)
                    Divider()
                    listButtons
                }
                Divider()
                if let index = selectedIndex {
                    options(index)
                } else {
                    Spacer()
                }
            }
            Divider()
            HStack {
                Text(Tr.fieldsFieldsFor(val: original.name)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(Tr.deckConfigSaveButton) { commit() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.medium)
        }
        .frame(width: Theme.Notetypes.fieldsSheetSize.width, height: Theme.Notetypes.fieldsSheetSize.height)
        .sheet(item: $prompt) { prompt in
            NamePromptSheet(title: prompt.title, initial: prompt.initial) { text in apply(prompt.kind, text) }
        }
        .alert(Tr.notetypesFields, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private var listButtons: some View {
        HStack(spacing: Theme.Spacing.small) {
            Button(Tr.actionsAdd) { prompt = Prompt(kind: .add, title: Tr.fieldsFieldName, initial: "") }
            Button(Tr.actionsDelete) { delete() }.disabled(selectedIndex == nil)
            Menu {
                Button(Tr.actionsRename) { if let i = selectedIndex { prompt = Prompt(kind: .rename, title: Tr.actionsNewName, initial: rows[i].field.name) } }
                Button("\(Tr.actionsReposition)…") {
                    if let i = selectedIndex { prompt = Prompt(kind: .reposition, title: Tr.fieldsNewPosition1(val: String(rows.count)), initial: String(i + 1)) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(selectedIndex == nil)
        }
        .padding(Theme.Spacing.small)
    }

    // MARK: Options

    @ViewBuilder
    private func options(_ index: Int) -> some View {
        let field = Binding(get: { rows[index].field }, set: { rows[index].field = $0 })
        Form {
            Section {
                LabeledContent(Tr.fieldsField) { Text(field.name.wrappedValue) }
                Toggle(Tr.fieldsSortByThisFieldInThe, isOn: Binding(
                    get: { sortID == rows[index].id },
                    set: { if $0 { sortID = rows[index].id } }))
            }
            Section(Tr.fieldsEditingFont) {
                TextField(Tr.fieldsFont, text: field.config.fontName)
                Stepper(value: field.config.fontSize, in: 6...200) {
                    LabeledContent(Tr.fieldsSize) { Text("\(field.config.fontSize.wrappedValue)").monospacedDigit() }
                }
            }
            Section {
                Toggle(Tr.fieldsReverseTextDirectionRtl, isOn: field.config.rtl)
                Toggle(Tr.fieldsHtmlByDefault, isOn: field.config.plainText)
                Toggle(Tr.fieldsCollapseByDefault, isOn: field.config.collapsed)
                Toggle(Tr.fieldsExcludeFromSearch, isOn: field.config.excludeFromSearch)
            }
            Section(Tr.fieldsDescription) {
                TextField(Tr.fieldsDescription, text: field.config.description_p, prompt: Text(Tr.fieldsDescriptionPlaceholder), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...4)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Actions

    private func apply(_ kind: Prompt.Kind, _ text: String) {
        switch kind {
        case .add:
            guard let name = validName(text, excluding: nil) else { return }
            var field = Anki_Notetypes_Notetype.Field()
            field.name = name
            field.config.fontName = "Arial"
            field.config.fontSize = 20
            let row = Row(field: field)
            rows.append(row)
            selection = row.id
        case .rename:
            guard let index = selectedIndex, let name = validName(text, excluding: index) else { return }
            rows[index].field.name = name
        case .reposition:
            guard let index = selectedIndex, let position = Int(text.trimmingCharacters(in: .whitespaces)),
                  (1...rows.count).contains(position) else { return }
            let row = rows.remove(at: index)
            rows.insert(row, at: position - 1)
        }
    }

    /// Desktop's checks on a field name, with its messages.
    private func validName(_ text: String, excluding index: Int?) -> String? {
        let name = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let first = name.first, "#^/".contains(first) {
            message = Tr.fieldsNameFirstLetterNotValid
            return nil
        }
        if name.contains(where: { ":\"{}".contains($0) }) {
            message = Tr.fieldsNameInvalidLetter
            return nil
        }
        if rows.enumerated().contains(where: { $0.offset != index && $0.element.field.name.caseInsensitiveCompare(name) == .orderedSame }) {
            message = Tr.fieldsThatFieldNameIsAlreadyUsed
            return nil
        }
        return name
    }

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
            guard await NotetypeAlerts.confirm(Tr.fieldsDeleteFieldFrom(val: Tr.browsingNoteCount(count: Int(useCount))), confirm: Tr.actionsDelete, destructive: true),
                  let index = selectedIndex else { return }
            let removed = rows.remove(at: index)
            if sortID == removed.id { sortID = rows.first?.id }
            selection = rows[min(index, rows.count - 1)].id
        }
    }

    private func cancel() {
        guard isEdited else { dismiss(); return }
        Task { if await NotetypeAlerts.confirm(Tr.cardTemplatesDiscardChanges, confirm: "Discard", destructive: true) { dismiss() } }
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
