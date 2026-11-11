import AnkiKit
import SwiftUI

/// Desktop's Manage Note Types dialog (aqt/models.py).
struct NotetypeManagerView: View {
    @Bindable var model: NotetypeManager
    let collection: CollectionModel
    @State private var prompt: NamePrompt?
    @State private var optionsFor: Anki_Notetypes_Notetype?
    @State private var fieldsFor: Anki_Notetypes_Notetype?

    private struct NamePrompt: Identifiable {
        let id = UUID()
        let title: String
        let initial: String
        let action: (String) -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            List(model.entries, selection: $model.selectedID) { entry in
                HStack {
                    Text(entry.name)
                    Spacer()
                    Text(Tr.browsingNoteCount(count: Int(entry.useCount)))
                        .foregroundStyle(.secondary)
                }
                .tag(entry.id)
                .contextMenu { rowMenu(entry) }
            }
            .contextMenu(forSelectionType: Int64.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first { rename(id) }
            }
            Divider()
            HStack {
                addMenu
                Button(Tr.actionsRename) { if let id = model.selectedID { rename(id) } }
                Button(Tr.actionsDelete) { if let id = model.selectedID { delete(id) } }
                Spacer()
                Button("\(Tr.notetypesFields)…") { load { fieldsFor = $0 } }
                Button("\(Tr.notetypesCards)…") { openCards() }
                Button("\(Tr.notetypesOptions)…") { load { optionsFor = $0 } }
            }
            .disabled(model.selected == nil)
            .padding(Theme.Spacing.medium)
        }
        .frame(minWidth: Theme.Notetypes.managerMinSize.width, minHeight: Theme.Notetypes.managerMinSize.height)
        .task { await model.refresh() }
        .alert(Tr.notetypesNoteTypes, isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: $prompt) { prompt in
            NamePromptSheet(title: prompt.title, initial: prompt.initial, action: prompt.action)
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

    // MARK: Menus

    private var addMenu: some View {
        Menu(Tr.actionsAdd) {
            ForEach(NotetypeManager.Stock.allCases, id: \.self) { stock in
                Button(Tr.notetypesAdd(val: stock.name)) { add(stock) }
            }
            Divider()
            ForEach(model.entries) { entry in
                Button(Tr.notetypesClone(val: entry.name)) { clone(entry.id) }
            }
        }
        .menuIndicator(.visible)
        .fixedSize()
    }

    @ViewBuilder
    private func rowMenu(_ entry: NotetypeManager.Entry) -> some View {
        Button(Tr.actionsRename) { rename(entry.id) }
        Button(Tr.actionsDelete) { delete(entry.id) }
    }

    // MARK: Actions

    private func add(_ stock: NotetypeManager.Stock) {
        // Image Occlusion has a fixed name, so it is added without asking.
        if stock == .imageOcclusion {
            Task { await model.add(stock, name: stock.name) }
            return
        }
        prompt = NamePrompt(title: Tr.notetypesAddNoteType, initial: stock.name) { name in
            Task { await model.add(stock, name: name) }
        }
    }

    private func clone(_ id: Int64) {
        prompt = NamePrompt(title: Tr.notetypesAddNoteType, initial: model.defaultName(cloning: id)) { name in
            Task { await model.clone(id, name: name) }
        }
    }

    private func rename(_ id: Int64) {
        guard let entry = model.entries.first(where: { $0.id == id }) else { return }
        prompt = NamePrompt(title: Tr.actionsNewName, initial: entry.name) { name in
            Task { await model.rename(id, to: name) }
        }
    }

    private func delete(_ id: Int64) {
        guard let entry = model.entries.first(where: { $0.id == id }) else { return }
        Task {
            if model.entries.count < 2 {
                await NotetypeAlerts.inform(Tr.notetypesPleaseAddAnotherNoteTypeFirst)
                return
            }
            let question = entry.useCount > 0 ? Tr.notetypesDeleteThisNoteTypeAndAll : Tr.notetypesDeleteThisUnusedNoteType
            guard await NotetypeAlerts.confirm(question, confirm: Tr.actionsDelete, destructive: true) else { return }
            if !(await model.schemaAlreadyChanged()),
               !(await NotetypeAlerts.confirm(NotetypeAlerts.schemaChange, confirm: "Continue"))
            { return }
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
            do { present(try await model.notetype(id)) } catch { model.errorMessage = "\(error)" }
        }
    }
}

extension Anki_Notetypes_Notetype: @retroactive Identifiable {}

/// Desktop's one-line `getText` prompt.
struct NamePromptSheet: View {
    let title: String
    @State var name: String
    let action: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String, action: @escaping (String) -> Void) {
        self.title = title
        _name = State(initialValue: initial)
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(title).font(.headline)
            TextField(title, text: $name)
                .labelsHidden()
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Notetypes.nameSheetWidth)
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        action(name)
        dismiss()
    }
}

/// Desktop's note type Options: the LaTeX header and footer, and SVG output.
struct NotetypeOptionsSheet: View {
    @State var notetype: Anki_Notetypes_Notetype
    let save: (Anki_Notetypes_Notetype) -> Void
    @Environment(\.dismiss) private var dismiss

    init(notetype: Anki_Notetypes_Notetype, save: @escaping (Anki_Notetypes_Notetype) -> Void) {
        _notetype = State(initialValue: notetype)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.actionsOptionsFor(val: notetype.name)).font(.headline)
            Text(Tr.notetypesHeader)
            TextEditor(text: $notetype.config.latexPre)
                .font(Theme.Notetypes.editorFont)
                .border(Theme.Editor.fieldBorder)
            Text(Tr.notetypesFooter)
            TextEditor(text: $notetype.config.latexPost)
                .font(Theme.Notetypes.editorFont)
                .border(Theme.Editor.fieldBorder)
            Toggle(Tr.notetypesCreateScalableImagesWithDvisvgm, isOn: $notetype.config.latexSvg)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(Tr.deckConfigSaveButton) {
                    save(notetype)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Notetypes.optionsSheetSize.width, height: Theme.Notetypes.optionsSheetSize.height)
    }
}
