import AnkiKit
import SwiftUI

/// Notes › Change Note Type: pick the new note type, then for each of its
/// fields and card types say which current one it takes its content from.
/// Upstream's page for desktop (ts/routes/change-notetype) does the same.
struct ChangeNotetypeSheet: View {
    let browser: BrowserModel
    @State private var model: ChangeNotetypeModel
    @State private var saving = false

    init(browser: BrowserModel, noteIDs: [Int64], notetypes: [NotetypeChoice], info: Anki_Notetypes_ChangeNotetypeInfo) {
        self.browser = browser
        _model = State(
            initialValue: ChangeNotetypeModel(
                noteIDs: noteIDs, notetypes: notetypes, info: info, backend: browser.collection.backend))
    }

    var body: some View {
        PromptLayout(
            title: Tr.browsingChangeNotetype, action: "Change", canSubmit: !model.isUnchanged && !model.isLoading && !saving,
            width: Theme.Browser.changeNotetypeSheetWidth, cancel: browser.cancelPrompt, submit: save
        ) {
            Form {
                LabeledContent(Tr.changeNotetypeCurrent) { Text(model.oldNotetypeName) }
                Picker(Tr.changeNotetypeNew, selection: Binding(get: { model.newNotetypeID }, set: { model.chooseNotetype($0) })) {
                    ForEach(model.notetypes) { Text($0.name).tag($0.id) }
                }
                Section(Tr.changeNotetypeFields) {
                    ForEach(Array(model.info.newFieldNames.enumerated()), id: \.offset) { index, name in
                        if model.fields.indices.contains(index) {
                            mapping(
                                name, oldNames: model.info.oldFieldNames,
                                selection: Binding { model.field(index) } set: { model.setField(index, to: $0) })
                        }
                    }
                    discarded(Tr.changeNotetypeWillDiscardContent, model.discardedFields)
                }
                Section(Tr.changeNotetypeTemplates) {
                    if model.templates.isEmpty {
                        Text(Tr.changeNotetypeToFromCloze)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(Array(model.info.newTemplateNames.enumerated()), id: \.offset) { index, name in
                            if model.templates.indices.contains(index) {
                                mapping(
                                    name, oldNames: model.info.oldTemplateNames,
                                    selection: Binding { model.template(index) } set: { model.setTemplate(index, to: $0) })
                            }
                        }
                        discarded(Tr.changeNotetypeWillDiscardCards, model.discardedTemplates)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: Theme.Browser.changeNotetypeFormHeight)
            .disabled(saving)
        }
        .alert(
            "Something went wrong", isPresented: Binding { model.errorMessage != nil } set: { _ in model.errorMessage = nil },
            actions: {}, message: { Text(model.errorMessage ?? "") })
    }

    /// One new field or card type, and the current one it takes its content from.
    private func mapping(_ newName: String, oldNames: [String], selection: Binding<Int32>) -> some View {
        Picker(newName, selection: selection) {
            ForEach(Array(oldNames.enumerated()), id: \.offset) { Text($1).tag(Int32($0)) }
            Divider()
            Text(Tr.changeNotetypeNothing).tag(ChangeNotetypeModel.nothing)
        }
    }

    @ViewBuilder
    private func discarded(_ message: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            Label {
                Text(message + " " + names.formatted(.list(type: .and, width: .narrow)))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .font(.callout)
        }
    }

    private func save() {
        saving = true
        Task {
            await browser.changeNotetype(model.request)
            saving = false
        }
    }
}
