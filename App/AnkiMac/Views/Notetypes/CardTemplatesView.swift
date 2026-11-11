import AnkiKit
import SwiftUI

/// Desktop's card layout editor: the card type's templates and styling on
/// the left, the card they produce on the right.
struct CardTemplatesView: View {
    @Bindable var model: CardTemplatesModel
    let mediaFolder: URL?
    let close: () -> Void
    @State private var web = ReviewerWebController()
    @State private var prompt: Prompt?
    @State private var showsBrowserAppearance = false
    @State private var showsDeckOverride = false

    private struct Prompt: Identifiable {
        enum Kind { case rename, reposition }
        let id = UUID()
        let kind: Kind
        let title: String
        let initial: String
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                editorPane.frame(minWidth: 320)
                previewPane.frame(minWidth: 320)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(Tr.deckConfigSaveButton) { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.medium)
        }
        .frame(
            minWidth: Theme.Notetypes.cardsMinSize.width, idealWidth: Theme.Notetypes.cardsDefaultSize.width,
            minHeight: Theme.Notetypes.cardsMinSize.height, idealHeight: Theme.Notetypes.cardsDefaultSize.height)
        .task {
            web.mediaFolder = mediaFolder
            web.prepare()
            await model.loadSampleNote()
        }
        .onChange(of: model.previewVersion) { push() }
        .sheet(item: $prompt) { prompt in
            NamePromptSheet(title: prompt.title, initial: prompt.initial) { text in
                switch prompt.kind {
                case .rename: model.rename(to: text)
                case .reposition:
                    if let position = Int(text.trimmingCharacters(in: .whitespaces)) { reposition(position) }
                }
            }
        }
        .sheet(isPresented: $showsBrowserAppearance) { BrowserAppearanceSheet(model: model) }
        .sheet(isPresented: $showsDeckOverride) { DeckOverrideSheet(model: model) }
        .alert(Tr.notetypesCards, isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Text(Tr.cardTemplatesCardType)
            Picker(Tr.cardTemplatesCardType, selection: $model.selected) {
                ForEach(model.draft.templates.indices, id: \.self) { index in
                    Text(model.cardTypeName(index)).tag(index)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(model.isCloze)
            Spacer()
            Menu(Tr.cardTemplatesPreviewSettings) { optionsMenu }
                .fixedSize()
        }
        .padding(Theme.Spacing.medium)
    }

    @ViewBuilder
    private var optionsMenu: some View {
        if !model.isCloze {
            Button(Tr.cardTemplatesAddCardType) { addCardType() }
            Button(Tr.cardTemplatesRemoveCardType) { removeCardType() }
                .disabled(model.draft.templates.count < 2)
            Button(Tr.cardTemplatesRenameCardType) {
                prompt = Prompt(kind: .rename, title: Tr.actionsNewName, initial: model.template?.name ?? "")
            }
            Button(Tr.cardTemplatesRepositionCardType) {
                prompt = Prompt(
                    kind: .reposition,
                    title: Tr.cardTemplatesEnterNewCardPosition1(val: String(model.draft.templates.count)),
                    initial: String(model.selected + 1))
            }
            .disabled(model.draft.templates.count < 2)
            Divider()
        }
        let override = (model.template?.config.targetDeckID ?? 0) != 0
        Button(Tr.cardTemplatesDeckOverride + (override ? Tr.cardTemplatesOn : Tr.cardTemplatesOff)) { showsDeckOverride = true }
        Button(Tr.cardTemplatesBrowserAppearance) { showsBrowserAppearance = true }
        if !model.isCloze {
            Button(Tr.cardTemplatesFlip) { flip() }
        }
        if model.original.config.originalStockKind != .unknown {
            Divider()
            Button("\(Tr.cardTemplatesRestoreToDefault)…") { restore() }
        }
    }

    // MARK: Panes

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Picker(Tr.cardTemplatesTemplateBox, selection: $model.editor) {
                Text(Tr.cardTemplatesFrontTemplate).tag(CardTemplatesModel.Editor.front)
                Text(Tr.cardTemplatesBackTemplate).tag(CardTemplatesModel.Editor.back)
                Text(Tr.cardTemplatesTemplateStyling).tag(CardTemplatesModel.Editor.styling)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            CodeTextEditor(text: $model.text)
                .border(Theme.Editor.fieldBorder)
                .frame(minHeight: Theme.Notetypes.editorMinHeight)
            HStack {
                Text(Tr.cardTemplatesChangesWillAffectNotes(count: Int(model.useCount)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu(Tr.fieldsAddField) {
                    ForEach(model.draft.fields.map(\.name), id: \.self) { name in
                        Button(name) { model.insertField(name) }
                    }
                }
                .fixedSize()
                .disabled(model.editor == .styling)
            }
        }
        .padding(Theme.Spacing.medium)
    }

    private var previewPane: some View {
        VStack(spacing: Theme.Spacing.small) {
            HStack {
                Picker(Tr.cardTemplatesPreviewBox, selection: $model.showsAnswer) {
                    Text(Tr.cardTemplatesFrontPreview).tag(false)
                    Text(Tr.cardTemplatesBackPreview).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Menu(Tr.cardTemplatesPreviewSettings) {
                    Toggle(Tr.cardTemplatesFillEmpty, isOn: $model.fillEmpty)
                    Toggle(Tr.cardTemplatesNightMode, isOn: $model.nightMode)
                    Toggle(Tr.cardTemplatesAddMobileClass, isOn: $model.mobileClass)
                }
                .fixedSize()
            }
            if let view = web.webView {
                CardWebView(webView: view)
                    .border(Theme.Editor.fieldBorder)
            } else {
                Spacer()
            }
        }
        .padding(Theme.Spacing.medium)
    }

    // MARK: Actions

    private func push() {
        web.setNightMode(model.nightMode)
        web.emulateMobile(model.mobileClass)
        if model.previewIsAnswer {
            web.showQuestion("", answer: model.previewHTML, bodyClass: model.previewBodyClass)
            web.showAnswer(model.previewHTML)
        } else {
            web.showQuestion(model.previewHTML, answer: "", bodyClass: model.previewBodyClass)
        }
    }

    private func addCardType() {
        Task {
            if model.useCount > 0,
               !(await NotetypeAlerts.confirm(Tr.cardTemplatesThisWillCreateCardProceed(count: Int(model.useCount))))
            { return }
            model.addCardType()
        }
    }

    private func removeCardType() {
        guard model.draft.templates.count > 1 else {
            Task { await NotetypeAlerts.inform(Tr.cardTemplatesAtLeastOneCardTypeIs) }
            return
        }
        Task {
            let count = await model.cardCount(ofTemplate: model.selected)
            let message = Tr.cardTemplatesDeleteTheAsCardTypeAnd(
                template: model.template?.name ?? "", cards: Tr.cardTemplatesCardCount(count: count))
            if await NotetypeAlerts.confirm(message, confirm: Tr.actionsDelete, destructive: true) {
                model.removeCardType()
            }
        }
    }

    private func reposition(_ position: Int) { model.reposition(to: position) }

    private func flip() {
        if !model.flip() {
            Task { await NotetypeAlerts.inform(Tr.cardTemplatesAnkiCouldntFindTheLineBetween) }
        }
    }

    private func restore() {
        Task {
            guard await NotetypeAlerts.confirm(Tr.cardTemplatesRestoreToDefaultConfirmation, confirm: Tr.cardTemplatesRestoreToDefault, destructive: true) else { return }
            if await model.restoreToDefault() {
                close()
                await NotetypeAlerts.inform(Tr.cardTemplatesRestoredToDefault)
            }
        }
    }

    private func cancel() {
        guard model.isEdited else { close(); return }
        Task { if await NotetypeAlerts.confirm(Tr.cardTemplatesDiscardChanges, confirm: "Discard", destructive: true) { close() } }
    }

    private func save() {
        Task { if await model.save() { close() } }
    }
}

/// Desktop's Browser Appearance dialog: the question and answer formats the
/// browser's columns use, and a font override.
private struct BrowserAppearanceSheet: View {
    let model: CardTemplatesModel
    @State private var question = ""
    @State private var answer = ""
    @State private var overridesFont = false
    @State private var font = "Arial"
    @State private var size = 12
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.cardTemplatesBrowserAppearance).font(.headline)
            TextField(Tr.cardTemplatesFrontTemplate, text: $question)
            TextField(Tr.cardTemplatesBackTemplate, text: $answer)
            Toggle(Tr.fieldsEditingFont, isOn: $overridesFont)
            HStack {
                TextField(Tr.fieldsFont, text: $font)
                Stepper("\(size)", value: $size, in: 6...72)
            }
            .disabled(!overridesFont)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Notetypes.optionsSheetSize.width)
        .onAppear {
            guard let config = model.template?.config else { return }
            question = config.qFormatBrowser
            answer = config.aFormatBrowser
            overridesFont = !config.browserFontName.isEmpty
            font = config.browserFontName.isEmpty ? "Arial" : config.browserFontName
            size = config.browserFontSize == 0 ? 12 : Int(config.browserFontSize)
        }
    }

    private func apply() {
        guard model.draft.templates.indices.contains(model.selected) else { return }
        var config = model.draft.templates[model.selected].config
        config.qFormatBrowser = question.trimmingCharacters(in: .whitespaces)
        config.aFormatBrowser = answer.trimmingCharacters(in: .whitespaces)
        config.browserFontName = overridesFont ? font : ""
        config.browserFontSize = overridesFont ? UInt32(size) : 0
        model.draft.templates[model.selected].config = config
        dismiss()
    }
}

/// Desktop's Deck Override: the deck new cards of this card type go to.
private struct DeckOverrideSheet: View {
    let model: CardTemplatesModel
    @State private var decks: [(id: Int64, name: String)] = []
    @State private var deckID: Int64 = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.cardTemplatesEnterDeckToPlaceNew(val: model.template?.name ?? ""))
            Picker(Tr.decksDeck, selection: $deckID) {
                Text(Tr.cardTemplatesOff).tag(Int64(0))
                ForEach(decks, id: \.id) { deck in Text(deck.name).tag(deck.id) }
            }
            .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("OK") {
                    if model.draft.templates.indices.contains(model.selected) {
                        model.draft.templates[model.selected].config.targetDeckID = deckID
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Notetypes.optionsSheetSize.width)
        .task {
            deckID = model.template?.config.targetDeckID ?? 0
            decks = await model.deckNames()
        }
    }
}
