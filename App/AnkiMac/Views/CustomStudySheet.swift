import SwiftUI

/// Desktop's Custom Study dialog as a sheet on the main window, drawn as
/// Deck Options' settings: the deck's path over "Custom Study", desktop's
/// six choices as rows with the chosen one's number at its trailing edge,
/// and Selective Study's two tag lists as tag fields.
struct CustomStudySheet: View {
    @Bindable var study: CustomStudyModel
    /// "Spanish::Verbs", shown as the eyebrow.
    let deckName: String
    let cancel: () -> Void
    let done: (Int64) -> Void

    var body: some View {
        SettingsSheet(
            eyebrow: deckName.replacingOccurrences(of: "::", with: " \u{203A} "), title: Tr.actionsCustomStudy,
            width: Theme.CustomStudy.width, maxHeight: Theme.CustomStudy.maxHeight
        ) {
            OptionSection {
                ForEach(CustomStudyModel.Option.allCases, id: \.self) { option in
                    ChoiceRow(title: option.title, chosen: study.option == option) {
                        study.option = option
                    } setting: {
                        number
                    }
                    if study.option == option {
                        notes
                    }
                }
            }
            // The choice's number has the focus, so Up and Down move the
            // choice, as in Quick Find; the next number then takes the focus.
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            if study.option == .cram, study.hasTags {
                tagSection
            }
        } footer: {
            if let error = study.error {
                OptionWarning(text: error, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(
                action: isLimit ? Tr.customStudyOk : Tr.decksStudy, disabled: !study.canRun, cancel: cancel,
                submit: { Task { if let deckID = await study.run() { done(deckID) } } })
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        let options = CustomStudyModel.Option.allCases
        guard let index = options.firstIndex(of: study.option) else { return .ignored }
        study.option = options[min(max(index + offset, 0), options.count - 1)]
        return .handled
    }

    private var isLimit: Bool {
        study.option == .newLimit || study.option == .reviewLimit
    }

    /// The chosen option's number at its row's trailing edge, with its
    /// unit after it. The row's title already says what it is, so desktop's
    /// sentence ("Review ahead by") is only what VoiceOver reads.
    private var number: some View {
        NumberField(
            value: Binding { Double(study.value) } set: { study.value = Int($0) },
            range: Double(study.option.range.lowerBound)...Double(study.option.range.upperBound),
            unit: study.valueLabels.after, focusOnAppear: true)
            .environment(\.optionTitle, study.valueLabels.before)
    }

    /// What's available and, for a session by state or tag, which cards.
    /// They belong to the choice, so no hairline comes between them.
    @ViewBuilder private var notes: some View {
        if let available = study.available {
            Text(available)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .optionNote()
        }
        if study.option == .cram {
            // The menu's hover room hangs past the leading edge, so its
            // words line up with the sentence above.
            OptionPicker(
                selection: $study.cramKind, choices: CustomStudyModel.CramKind.allCases.map { ($0, $0.title) })
                .padding(.leading, -Theme.Layout.menuPadding)
                .padding(.trailing, Theme.Layout.menuPadding)
                .environment(\.optionTitle, Tr.customStudyStudyByCardStateOrTag)
                .optionNote()
        }
    }

    /// Desktop's Selective Study window: tags a card must have one of, and
    /// tags it must not have, each as a tag field completing from the deck's tags.
    private var tagSection: some View {
        OptionSection(title: Tr.customStudySelectiveStudy) {
            tagsRow(Tr.customStudyRequireOneOrMoreOfThese, tags: $study.included)
            tagsRow(Tr.customStudySelectTagsToExclude, tags: $study.excluded)
        }
    }

    private func tagsRow(_ title: String, tags: Binding<[String]>) -> some View {
        OptionRow(title: label(title), revertible: false) {
            TagField(tags: tags, complete: study.completeTags)
                .frame(width: Theme.CustomStudy.tagFieldWidth)
        }
    }

    /// "Require one or more of these tags:" as a row's title.
    private func label(_ text: String) -> String {
        text.hasSuffix(":") ? String(text.dropLast()) : text
    }
}
