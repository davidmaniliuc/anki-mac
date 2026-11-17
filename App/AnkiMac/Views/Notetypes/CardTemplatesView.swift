import AnkiKit
import AppKit
import SwiftUI

/// Desktop's card layout editor, with Add's chrome: the band holds the
/// note type's name, the card type as a quiet menu that also holds
/// desktop's card type commands, and Save. Under it the template as code
/// on the left and the card it makes on the right, split by a hairline.
struct CardTemplatesView: View {
    @Bindable var model: CardTemplatesModel
    let chrome: BandChrome
    let mediaFolder: URL?
    let save: () -> Void
    let close: () -> Void
    @State private var web = ReviewerWebController()
    @State private var prompt: Prompt?
    @State private var showsBrowserAppearance = false
    @State private var showsDeckOverride = false
    @Environment(\.colorScheme) private var colorScheme

    private enum Prompt: Identifiable {
        case rename, reposition
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            band
            HStack(spacing: 0) {
                editorPane.frame(minWidth: Theme.Notetypes.paneMinWidth)
                Theme.Palette.hairline.frame(width: 1)
                previewPane.frame(minWidth: Theme.Notetypes.paneMinWidth)
            }
        }
        .background(Theme.Palette.canvas)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .background { shortcuts }
        .task {
            // Night Mode starts as the window looks, as desktop's follows its theme.
            model.nightMode = colorScheme == .dark
            web.mediaFolder = mediaFolder
            web.prepare()
            await model.loadSampleNote()
        }
        .onChange(of: model.previewVersion) { push() }
        .sheet(item: $prompt) { prompt in
            switch prompt {
            case .rename:
                TextPromptSheet(
                    title: sheetTitle(Tr.cardTemplatesRenameCardType), label: rowTitle(Tr.actionsNewName),
                    action: Tr.actionsRename, initial: model.template?.name ?? ""
                ) { model.rename(to: $0) }
            case .reposition:
                let count = model.draft.templates.count
                TextPromptSheet(
                    title: sheetTitle(Tr.cardTemplatesRepositionCardType),
                    label: rowTitle(Tr.cardTemplatesEnterNewCardPosition1(val: String(count))),
                    action: Tr.actionsReposition, initial: String(model.selected + 1), number: true,
                    problem: { Int($0).map { (1...count).contains($0) } == true ? nil : "" }
                ) { text in
                    if let position = Int(text) { model.reposition(to: position) }
                }
            }
        }
        .sheet(isPresented: $showsBrowserAppearance) { BrowserAppearanceSheet(model: model) }
        .sheet(isPresented: $showsDeckOverride) { DeckOverrideSheet(model: model) }
        .alert(
            model.failure?.title ?? "",
            isPresented: Binding { model.failure != nil } set: { if !$0 { model.failure = nil } }
        ) {
            Button(Tr.customStudyOk) {}
        } message: {
            Text(verbatim: model.failure?.detail ?? "")
        }
    }

    // MARK: Band

    /// The note type's name after the traffic lights, then the card type
    /// as a quiet menu, and Save, the window's one prominent action.
    private var band: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(model.original.name)
                .font(Theme.Band.titleFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
            cardTypeMenu
                .layoutPriority(-1)
            Spacer(minLength: Theme.Spacing.small)
            Button(action: save) {
                HStack(spacing: Theme.Layout.keyCapGap) {
                    Text(Tr.actionsSave)
                    KeyCap("\u{2318}S", onAccent: true)
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            // File › Save holds ⌘S, for this window while it is key.
            .help("\(Tr.actionsSave) (\u{2318}S)")
            .padding(.leading, Theme.Spacing.xSmall)
        }
        // Clear of the traffic lights, which in full screen come down over
        // the band in a pill of their own.
        .padding(.leading, chrome.fullScreen ? Theme.Spacing.medium : Theme.Band.leading)
        .padding(.trailing, Theme.Spacing.medium)
        .frame(height: Theme.Band.height)
        .titleBarBand()
    }

    /// The card types, then desktop's Options commands, so the band holds
    /// one menu, as Deck Options' preset menu holds its gear's commands.
    private var cardTypeMenu: some View {
        let title = rowTitle(Tr.cardTemplatesCardType)
        return Menu {
            if !model.isCloze {
                Picker(title, selection: $model.selected) {
                    ForEach(model.draft.templates.indices, id: \.self) { index in
                        Text(model.cardTypeName(index)).tag(index)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Section {
                    Button(Tr.cardTemplatesAddCardType) { addCardType() }
                    // Off with one card type left, which desktop refuses to remove.
                    Button(Tr.cardTemplatesRemoveCardType) { removeCardType() }
                        .disabled(model.draft.templates.count < 2)
                    Button(Tr.cardTemplatesRenameCardType) { prompt = .rename }
                    Button(Tr.cardTemplatesRepositionCardType) { prompt = .reposition }
                        .disabled(model.draft.templates.count < 2)
                }
            }
            Section {
                let override = (model.template?.config.targetDeckID ?? 0) != 0
                Button(Tr.cardTemplatesDeckOverride + " " + (override ? Tr.cardTemplatesOn : Tr.cardTemplatesOff)) {
                    showsDeckOverride = true
                }
                Button(Tr.cardTemplatesBrowserAppearance) { showsBrowserAppearance = true }
                if !model.isCloze {
                    Button(Tr.cardTemplatesFlip) { flip() }
                }
            }
            if model.original.config.originalStockKind != .unknown {
                Section {
                    Button("\(Tr.cardTemplatesRestoreToDefault)…") { restore() }
                }
            }
        } label: {
            QuietMenuLabel(title: title, value: model.cardTypeName(model.selected))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(title)
        .accessibilityValue(model.cardTypeName(model.selected))
    }

    // MARK: Panes

    /// Front, Back and Styling as quiet segments with Add Field at their
    /// end, the code as an unboxed block, and what it affects under it.
    private var editorPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                QuietSegments(
                    selection: $model.editor, choices: [.front, .back, .styling],
                    help: { "\(Self.title($0)) (\u{2318}\(Self.editors.firstIndex(of: $0)! + 1))" }
                ) { Self.title($0) }
                .accessibilityLabel(Tr.cardTemplatesTemplateBox)
                Spacer(minLength: 0)
                Menu {
                    ForEach(model.draft.fields.map(\.name), id: \.self) { name in
                        Button(name) { model.insertField(name) }
                    }
                } label: {
                    QuietMenuLabel(value: Tr.fieldsAddField)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, -Theme.Layout.menuPadding)
                .disabled(model.editor == .styling)
            }
            CodeBlock(text: $model.text, label: Self.title(model.editor))
            Text(figures(Tr.cardTemplatesChangesWillAffectNotes(count: Int(model.useCount))))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(2)
        }
        .padding(Theme.Spacing.medium)
    }

    /// Front and Back as quiet segments, the preview's options as a quiet
    /// menu, then the card on the canvas, as the study screen shows it.
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                QuietSegments(selection: $model.showsAnswer, choices: [false, true]) {
                    $0 ? Tr.cardTemplatesBackPreview : Tr.cardTemplatesFrontPreview
                }
                .accessibilityLabel(Tr.cardTemplatesPreviewBox)
                if model.isCloze, !model.clozeNumbers.isEmpty {
                    clozeMenu
                }
                Spacer(minLength: 0)
                Menu {
                    Toggle(Tr.cardTemplatesFillEmpty, isOn: $model.fillEmpty)
                    Toggle(Tr.cardTemplatesNightMode, isOn: $model.nightMode)
                    Toggle(Tr.cardTemplatesAddMobileClass, isOn: $model.mobileClass)
                } label: {
                    QuietMenuLabel(value: Tr.cardTemplatesPreviewSettings)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, -Theme.Layout.menuPadding)
            }
            .padding(Theme.Spacing.medium)
            if let view = web.webView {
                CardWebView(webView: view)
            } else {
                Spacer()
            }
        }
    }

    /// A cloze note type's cards, by their number, as desktop's box beside
    /// the preview.
    private var clozeMenu: some View {
        let name = { (number: Int) in Tr.cardTemplatesCard(val: String(number)) }
        return Menu {
            Picker(name(model.clozeOrd + 1), selection: $model.clozeOrd) {
                ForEach(model.clozeNumbers, id: \.self) { Text(name($0)).tag($0 - 1) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            QuietMenuLabel(value: name(model.clozeOrd + 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityValue(name(model.clozeOrd + 1))
    }

    /// Desktop's keys: ⌘1, ⌘2 and ⌘3 for the template's three parts (its
    /// Ctrl+1 to 3), and F3 and F4 for the card type before and after.
    private var shortcuts: some View {
        Group {
            ForEach(Self.editors.indices, id: \.self) { index in
                Button("") { model.editor = Self.editors[index] }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Button("") { stepCardType(-1) }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF3FunctionKey)!)), modifiers: [])
            Button("") { stepCardType(1) }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF4FunctionKey)!)), modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private static let editors: [CardTemplatesModel.Editor] = [.front, .back, .styling]

    private static func title(_ editor: CardTemplatesModel.Editor) -> String {
        switch editor {
        case .front: Tr.cardTemplatesFrontTemplate
        case .back: Tr.cardTemplatesBackTemplate
        case .styling: Tr.cardTemplatesTemplateStyling
        }
    }

    private func stepCardType(_ offset: Int) {
        guard !model.isCloze, model.draft.templates.indices.contains(model.selected + offset) else { return }
        model.selected += offset
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
               !(await NotetypeAlerts.confirm(
                   Tr.cardTemplatesThisWillCreateCardProceed(count: Int(model.useCount)),
                   confirm: sheetTitle(Tr.cardTemplatesAddCardType)))
            { return }
            model.addCardType()
        }
    }

    private func removeCardType() {
        Task {
            let count = await model.cardCount(ofTemplate: model.selected)
            let message = Tr.cardTemplatesDeleteTheAsCardTypeAnd(
                template: model.template?.name ?? "", cards: Tr.cardTemplatesCardCount(count: count))
            if await NotetypeAlerts.confirm(message, confirm: Tr.actionsDelete, destructive: true) {
                model.removeCardType()
            }
        }
    }

    private func flip() {
        if !model.flip() {
            Task { await NotetypeAlerts.inform(Tr.cardTemplatesAnkiCouldntFindTheLineBetween) }
        }
    }

    /// Restoring writes the note type at once, so the window closes, then
    /// says so, as desktop does.
    private func restore() {
        Task {
            guard await NotetypeAlerts.confirm(
                Tr.cardTemplatesRestoreToDefaultConfirmation, confirm: Tr.cardTemplatesRestoreToDefault,
                destructive: true)
            else { return }
            if await model.restoreToDefault() {
                close()
                await NotetypeAlerts.inform(Tr.cardTemplatesRestoredToDefault)
            }
        }
    }
}

/// Desktop's Browser Appearance dialog, drawn as the study prompts: the
/// question and answer formats the Browser's columns use, and a font
/// override, as rows under hairlines.
private struct BrowserAppearanceSheet: View {
    let model: CardTemplatesModel
    @State private var question = ""
    @State private var answer = ""
    @State private var overridesFont = false
    @State private var font = "Arial"
    @State private var size = 12.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsSheet(
            eyebrow: model.template?.name ?? "", title: sheetTitle(Tr.cardTemplatesBrowserAppearance),
            width: Theme.Notetypes.optionsWidth
        ) {
            OptionSection {
                OptionRow(title: rowTitle(Tr.browsingOverrideFrontTemplate), revertible: false) {
                    OptionTextField(text: $question, font: Theme.Editor.sourceFont, focusOnAppear: true)
                        .frame(width: Theme.Notetypes.appearanceFieldWidth)
                }
                OptionRow(title: rowTitle(Tr.browsingOverrideBackTemplate), revertible: false) {
                    OptionTextField(text: $answer, font: Theme.Editor.sourceFont)
                        .frame(width: Theme.Notetypes.appearanceFieldWidth)
                }
            }
            OptionSection {
                OptionRow(title: rowTitle(Tr.browsingOverrideFont), revertible: false) {
                    SwitchControl(title: rowTitle(Tr.browsingOverrideFont), isOn: $overridesFont)
                }
                if overridesFont {
                    OptionRow(title: rowTitle(Tr.fieldsFont), revertible: false) {
                        OptionPicker(selection: $font, choices: fontFamilies(keeping: font))
                            .frame(maxWidth: Theme.Notetypes.fontMenuMaxWidth, alignment: .trailing)
                    }
                    OptionRow(title: rowTitle(Tr.fieldsSize), revertible: false) {
                        NumberField(value: $size, range: 6...72)
                    }
                }
            }
        } footer: {
            Spacer()
            DialogButtons(action: Tr.customStudyOk, cancel: { dismiss() }, submit: apply)
        }
        .onAppear {
            guard let config = model.template?.config else { return }
            question = config.qFormatBrowser
            answer = config.aFormatBrowser
            overridesFont = !config.browserFontName.isEmpty
            font = config.browserFontName.isEmpty ? "Arial" : config.browserFontName
            size = config.browserFontSize == 0 ? 12 : Double(config.browserFontSize)
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

/// Desktop's Deck Override: the deck new cards of this card type go to,
/// as a quiet menu with "(off)" first, under desktop's question.
private struct DeckOverrideSheet: View {
    let model: CardTemplatesModel
    @State private var decks: [(id: Int64, name: String)] = []
    @State private var deckID: Int64 = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsSheet(
            eyebrow: model.template?.name ?? "", title: sheetTitle(Tr.cardTemplatesDeckOverride),
            width: Theme.Notetypes.promptWidth
        ) {
            OptionSection {
                Text(Tr.cardTemplatesEnterDeckToPlaceNew(val: model.template?.name ?? ""))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .optionNote()
                OptionRow(title: Tr.decksDeck, revertible: false) {
                    OptionPicker(
                        selection: $deckID,
                        choices: [(Int64(0), Tr.cardTemplatesOff)]
                            + decks.map { ($0.id, $0.name.replacingOccurrences(of: "::", with: " \u{203A} ")) })
                }
            }
        } footer: {
            Spacer()
            DialogButtons(action: Tr.customStudyOk, cancel: { dismiss() }) {
                if model.draft.templates.indices.contains(model.selected) {
                    model.draft.templates[model.selected].config.targetDeckID = deckID
                }
                dismiss()
            }
        }
        .task {
            deckID = model.template?.config.targetDeckID ?? 0
            decks = await model.deckNames()
        }
    }
}
