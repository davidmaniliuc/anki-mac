import AppKit
import SwiftUI

/// Note type and deck, the fields, the tags, and Add, as desktop's window.
struct AddCardsView: View {
    @Bindable var model: AddCardsModel
    let actions: AddCardsActions

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(Tr.notetypesType, selection: Binding { model.notetypeID } set: { id in
                    Task { await model.changeNotetype(to: id) }
                }) {
                    ForEach(model.notetypes) { Text($0.name).tag($0.id) }
                }
                Picker(Tr.decksDeck, selection: $model.deckID) {
                    ForEach(model.decks) { Text($0.name).tag($0.id) }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            NoteEditorView(
                editor: model.editor,
                sticky: (isOn: model.isSticky, toggle: model.toggleSticky),
                duplicateField: model.problem == .duplicate ? 0 : nil,
                cardLayout: actions.cardLayout)
            hints
            Divider()
            TagRow(tags: $model.tags, complete: model.completeTags)
                .padding(Theme.Spacing.medium)
        }
        .overlay(alignment: .bottom) {
            if let added = model.addedMessage {
                Text(added)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .background(.regularMaterial, in: Capsule())
                    .padding(Theme.AddCards.toastInset)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.default, value: model.addedMessage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if model.history.isEmpty {
                        Text("No notes added yet")
                    }
                    ForEach(model.history.reversed()) { entry in
                        Button(Tr.addingEdit(val: entry.text)) { actions.showInBrowser("nid:\(entry.id)") }
                    }
                } label: {
                    Label(Tr.addingHistory, systemImage: "clock")
                }
                .help(Tr.addingHistory)
            }
            ToolbarItem(placement: .primaryAction) {
                Button(Tr.actionsAdd, systemImage: "plus") { actions.add() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("\(Tr.actionsAdd) (\u{2318}\u{21A9})")
            }
        }
        .alert(
            model.message ?? "", isPresented: Binding { model.message != nil } set: { if !$0 { model.message = nil } }
        ) {
            Button("OK") {}
        }
        .alert(Tr.addingYouHaveAClozeDeletionNote, isPresented: $model.confirmingMissingCloze) {
            Button("Cancel", role: .cancel) {}
            Button(Tr.actionsAdd) { Task { _ = await model.add(confirmedCloze: true) } }
        }
    }

    /// Desktop's notes under the fields: duplicates and misplaced clozes.
    @ViewBuilder private var hints: some View {
        if let problem = model.problem {
            HStack {
                if problem == .duplicate {
                    Button(Tr.editingShowDuplicates) { actions.showInBrowser(model.duplicateSearch) }
                        .buttonStyle(.link)
                } else {
                    OptionWarning(text: problem.hint)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.bottom, Theme.Spacing.small)
        }
    }
}

/// The editors' tags: a tag symbol before the field, with no box of its own.
struct TagRow: View {
    @Binding var tags: [String]
    let complete: (String) -> [String]

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "tag")
                .font(Theme.Editor.tagSymbol)
                .foregroundStyle(Theme.Palette.secondary)
                .accessibilityHidden(true)
            TagField(tags: $tags, complete: complete, borderless: true)
        }
    }
}
