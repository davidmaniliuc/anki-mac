import SwiftUI

/// The sheet for a `BrowserPrompt`, drawn as the study prompts: the
/// command as a Headline, its rows under hairlines, then Cancel and the
/// action named for what it does, in desktop's words.
struct BrowserPromptSheet: View {
    let prompt: BrowserPrompt
    let model: BrowserModel

    var body: some View {
        switch prompt {
        case .setDueDate(let cards, let days):
            SetDueDatePrompt(days: days, context: context(cards: cards)) { model.setDueDate(days: $0) }
        case .forget(let cards, let restorePosition, let resetCounts):
            ResetCardPrompt(restorePosition: restorePosition, resetCounts: resetCounts, context: context(cards: cards)) {
                model.forget(restorePosition: $0, resetCounts: $1)
            }
        case .reposition(let cards, let top, let bottom, let randomize, let shift):
            RepositionPrompt(
                queueTop: top, queueBottom: bottom, randomize: randomize, shift: shift, context: context(cards: cards)
            ) {
                model.reposition(start: $0, step: $1, randomize: $2, shift: $3)
            }
        case .changeDeck(let cards, let decks, let current):
            ChangeDeckSheet(model: model, cards: cards, decks: decks, selection: current)
        case .tags(let adding, let notes, let known):
            TagsSheet(model: model, adding: adding, notes: notes, known: known)
        case .findAndReplace(let notes, let fields):
            FindAndReplaceSheet(model: model, notes: notes, fields: fields)
        case .changeNotetype(let noteIDs, let notetypes, let info):
            ChangeNotetypeSheet(browser: model, noteIDs: noteIDs, notetypes: notetypes, info: info)
        }
    }

    private func context(cards: Int) -> SchedulePromptContext {
        SchedulePromptContext(
            cards: cards, error: model.promptError, cancel: model.cancelPrompt, edited: { model.promptError = nil })
    }
}

/// Desktop's Change Deck (its Study Deck dialog): a filter over the decks,
/// each a row with its parents after its name in Faded Pencil, as Quick
/// Find lists them. Up and Down move the choice from the filter, Return or
/// a double click moves the cards.
private struct ChangeDeckSheet: View {
    let model: BrowserModel
    let cards: Int
    let decks: [DeckChoice]
    @State var selection: Int64?
    @State private var filter = ""

    /// The chosen deck, while the filter still shows it: Move never acts on
    /// a deck the user can't see.
    private var chosen: Int64? {
        shown.contains { $0.id == selection } ? selection : nil
    }

    /// Every word of the filter somewhere in the deck's whole name, as desktop's.
    private var shown: [DeckChoice] {
        let words = filter.split(separator: " ").map(String.init)
        return words.isEmpty ? decks : decks.filter { deck in words.allSatisfy { deck.name.localizedStandardContains($0) } }
    }

    var body: some View {
        SettingsSheet(
            eyebrow: Tr.cardTemplatesCardCount(count: cards), title: Tr.browsingChangeDeck,
            width: Theme.Browser.sheetWidth
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                OptionTextField(text: $filter, prompt: Tr.actionsFilter, focusOnAppear: true)
                    .environment(\.optionTitle, Tr.actionsFilter)
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onChange(of: filter) {
                        if chosen == nil { selection = shown.first?.id }
                    }
                list
            }
        } footer: {
            Spacer()
            DialogButtons(action: Tr.browsingMoveCards, disabled: chosen == nil, cancel: model.cancelPrompt, submit: submit)
        }
    }

    private var list: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { deck in
                        DeckChoiceRow(deck: deck, selected: deck.id == selection) {
                            selection = deck.id
                        } open: {
                            selection = deck.id
                            submit()
                        }
                        .id(deck.id)
                    }
                }
            }
            .scrollEdgeEffectHidden(true, for: .vertical)
            .frame(height: Theme.Browser.deckListHeight)
            .accessibilityLabel(Tr.browsingChangeDeck)
            .onAppear {
                // The cards' current deck, in view.
                if let selection { scroller.scrollTo(selection, anchor: .center) }
            }
            .onChange(of: selection) { _, id in
                if let id { scroller.scrollTo(id) }
            }
        }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !shown.isEmpty else { return .ignored }
        let index = shown.firstIndex { $0.id == chosen }.map { $0 + step } ?? (step > 0 ? 0 : shown.count - 1)
        selection = shown[min(max(index, 0), shown.count - 1)].id
        return .handled
    }

    private func submit() {
        guard let chosen else { return }
        model.changeDeck(to: chosen)
    }
}

/// A deck as the Fields sheet's rows are: the selection wash on the chosen
/// one, the hover wash under the pointer, each reaching past the text.
private struct DeckChoiceRow: View {
    let deck: DeckChoice
    let selected: Bool
    let select: () -> Void
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        let parts = deck.name.components(separatedBy: "::")
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            Text(parts.last ?? deck.name)
                .font(Theme.DeckOptions.rowFont)
                .foregroundStyle(Theme.Palette.text)
                .layoutPriority(1)
            if parts.count > 1 {
                // The parents lose their start first, as Quick Find's do.
                Text(parts.dropLast().joined(separator: " › "))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .listRow(
            height: Theme.Layout.rowHeight,
            wash: selected ? Theme.Palette.selection : hovered ? Theme.Palette.hover : .clear)
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onClick(select, doubleClick: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deck.name.replacing("::", with: " › "))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
    }
}

/// Desktop's Add Tags and Remove Tags: its question as the row's title and
/// the tags in a tag field, completing from the collection's.
private struct TagsSheet: View {
    let model: BrowserModel
    let adding: Bool
    let notes: Int
    let known: [String]
    @State private var tags: [String] = []

    var body: some View {
        let action = sheetTitle(adding ? Tr.browsingAddTags2 : Tr.browsingRemoveTags)
        let question = rowTitle(adding ? Tr.browsingEnterTagsToAdd : Tr.browsingEnterTagsToDelete)
        SettingsSheet(eyebrow: Tr.browsingNoteCount(count: notes), title: action, width: Theme.Browser.sheetWidth) {
            OptionSection {
                OptionRow(title: question, revertible: false) {
                    TagField(tags: $tags, complete: complete, focusOnAppear: true)
                        .frame(width: Theme.Browser.tagFieldWidth)
                }
            }
        } footer: {
            Spacer()
            DialogButtons(action: action, disabled: tags.isEmpty, cancel: model.cancelPrompt) {
                model.changeTags(adding: adding, tags: tags.joined(separator: " "))
            }
        }
    }

    /// The collection's tags starting with what's typed.
    private func complete(_ prefix: String) -> [String] {
        let matches = known.filter { $0.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil }
        return Array(matches.prefix(Theme.Browser.tagSuggestions))
    }
}

/// Desktop's Find and Replace: what to find and what to put in its place
/// in quiet boxes, where as a quiet menu, then its three switches.
private struct FindAndReplaceSheet: View {
    let model: BrowserModel
    let notes: Int
    let fields: [String]
    @State private var find = ""
    @State private var replacement = ""
    @State private var target = ReplaceTarget.allFields
    @State private var selectedOnly = true
    @AppStorage("FindAndReplace.regex") private var regex = false
    @AppStorage("FindAndReplace.ignoreCase") private var ignoreCase = true

    var body: some View {
        SettingsSheet(
            eyebrow: Tr.browsingNoteCount(count: notes), title: Tr.browsingFindAndReplace,
            width: Theme.Browser.sheetWidth
        ) {
            OptionSection {
                OptionRow(title: rowTitle(Tr.browsingFind), revertible: false) {
                    OptionTextField(text: $find, focusOnAppear: true)
                        .frame(width: Theme.Browser.fieldWidth)
                }
                OptionRow(title: rowTitle(Tr.browsingReplaceWith), revertible: false) {
                    OptionTextField(text: $replacement)
                        .frame(width: Theme.Browser.fieldWidth)
                }
                OptionRow(title: rowTitle(Tr.browsingIn), revertible: false) {
                    OptionPicker(
                        selection: $target,
                        choices: [(.allFields, Tr.browsingAllFields), (.tags, Tr.editingTags)]
                            + fields.map { (ReplaceTarget.field($0), $0) })
                }
                switchRow(Tr.browsingSelectedNotesOnly, $selectedOnly)
                switchRow(Tr.browsingIgnoreCase, $ignoreCase)
                switchRow(Tr.browsingTreatInputAsRegularExpression, $regex)
            }
        } footer: {
            Spacer()
            DialogButtons(action: Tr.browsingFindAndReplace, disabled: find.isEmpty, cancel: model.cancelPrompt) {
                model.findAndReplace(
                    find: find, replacement: replacement, in: target, selectedOnly: selectedOnly, regex: regex,
                    matchCase: !ignoreCase)
            }
        }
    }

    private func switchRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        OptionRow(title: title, revertible: false) {
            SwitchControl(title: title, isOn: isOn)
        }
    }
}
