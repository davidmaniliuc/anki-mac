import AnkiKit
import SwiftUI

/// Notes › Change Note Type: pick the new note type, then for each of its
/// fields and card types say which current one it takes its content from.
/// Upstream's page for desktop (ts/routes/change-notetype) does the same;
/// here it is drawn as Deck Options' settings, each new field or card type
/// a row holding the current one as a quiet menu.
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
        SettingsSheet(
            title: Tr.browsingChangeNotetype, width: Theme.Browser.changeNotetypeWidth,
            maxHeight: Theme.Browser.changeNotetypeMaxHeight
        ) {
            OptionSection {
                OptionRow(title: Tr.changeNotetypeCurrent, revertible: false) {
                    Text(model.oldNotetypeName)
                        .font(Theme.DeckOptions.rowFont)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                OptionRow(title: Tr.changeNotetypeNew, revertible: false) {
                    OptionPicker(
                        selection: Binding { model.newNotetypeID } set: { model.chooseNotetype($0) },
                        choices: model.notetypes.map { ($0.id, $0.name) })
                }
            }
            OptionSection(title: Tr.changeNotetypeFields) {
                ForEach(Array(model.info.newFieldNames.enumerated()), id: \.offset) { index, name in
                    if model.fields.indices.contains(index) {
                        mapping(
                            name, oldNames: model.info.oldFieldNames,
                            selection: Binding { model.field(index) } set: { model.setField(index, to: $0) })
                    }
                }
                discarded(Tr.changeNotetypeWillDiscardContent, model.discardedFields)
            }
            OptionSection(title: Tr.changeNotetypeTemplates) {
                if model.templates.isEmpty {
                    Text(Tr.changeNotetypeToFromCloze)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Theme.DeckOptions.rowPadding)
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
            .disabled(saving)
        } footer: {
            if saving || model.isLoading {
                ProgressView().controlSize(.small)
            } else if let failure = browser.promptError ?? model.failure?.detail {
                OptionWarning(text: failure, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(
                action: Tr.actionsSave, disabled: model.isUnchanged || model.isLoading || saving, cancelDisabled: saving,
                cancel: browser.cancelPrompt, submit: save)
        }
        .onChange(of: model.request) {
            browser.promptError = nil
            model.failure = nil
        }
    }

    /// One new field or card type, and the current one it takes its content from.
    private func mapping(_ newName: String, oldNames: [String], selection: Binding<Int32>) -> some View {
        OptionRow(title: newName, revertible: false) {
            OptionPicker(
                selection: selection,
                choices: oldNames.enumerated().map { (Int32($0), $1) } + [(ChangeNotetypeModel.nothing, Tr.changeNotetypeNothing)])
        }
    }

    @ViewBuilder
    private func discarded(_ message: String, _ names: [String]) -> some View {
        if !names.isEmpty {
            OptionWarning(text: message + " " + names.formatted(.list(type: .and, width: .narrow)))
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
