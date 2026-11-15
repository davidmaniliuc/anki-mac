import SwiftUI

/// The sheet for a `BrowserPrompt`: one short form, Cancel and one default
/// button named for what it does, as desktop's dialogs ask the same things.
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

/// Title, form and the button row every prompt shares.
struct PromptLayout<Content: View>: View {
    let title: String
    let action: String
    var canSubmit = true
    var width = Theme.Browser.sheetWidth
    let cancel: () -> Void
    let submit: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(title).font(.headline)
            content
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(action, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: width)
    }
}

func cardCount(_ count: Int) -> String {
    count == 1 ? "1 card" : "\(count.formatted()) cards"
}

private func noteCount(_ count: Int) -> String {
    count == 1 ? "1 note" : "\(count.formatted()) notes"
}

private struct ChangeDeckSheet: View {
    let model: BrowserModel
    let cards: Int
    let decks: [DeckChoice]
    @State var selection: Int64?
    @State private var filter = ""
    @FocusState private var focused: Bool

    /// The chosen deck, while the filter still shows it: Move never acts on
    /// a deck the user can't see.
    private var chosen: Int64? {
        shown.contains { $0.id == selection } ? selection : nil
    }

    private var shown: [DeckChoice] {
        filter.isEmpty ? decks : decks.filter { $0.name.localizedStandardContains(filter) }
    }

    var body: some View {
        PromptLayout(
            title: "Move \(cardCount(cards)) to:", action: "Move", canSubmit: chosen != nil,
            cancel: model.cancelPrompt, submit: submit
        ) {
            TextField("Filter", text: $filter, prompt: Text("Filter Decks"))
                .labelsHidden()
                .focused($focused)
                .onSubmit { if shown.count == 1 { selection = shown[0].id } }
            ScrollViewReader { scroller in
                List(shown, selection: $selection) { deck in
                    Text(deck.name).tag(deck.id)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: Int64.self) { _ in } primaryAction: { _ in submit() }
                .frame(height: Theme.Browser.deckListHeight)
                .onAppear {
                    focused = true
                    // The cards' current deck, in view.
                    if let selection { scroller.scrollTo(selection, anchor: .center) }
                }
            }
        }
    }

    private func submit() {
        guard let chosen else { return }
        model.changeDeck(to: chosen)
    }
}

private struct TagsSheet: View {
    let model: BrowserModel
    let adding: Bool
    let notes: Int
    let known: [String]
    @State private var tags = ""
    @FocusState private var focused: Bool

    /// Completes the word being typed from the collection's tags.
    private var suggestions: [String] {
        let word = tags.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        guard !word.isEmpty else { return [] }
        let matches = known.filter { $0.localizedStandardRange(of: word)?.lowerBound == $0.startIndex && $0 != word }
        return Array(matches.prefix(Theme.Browser.tagSuggestions))
    }

    var body: some View {
        PromptLayout(
            title: adding ? "Add tags to \(noteCount(notes))" : "Remove tags from \(noteCount(notes))",
            action: adding ? "Add Tags" : "Remove Tags", canSubmit: !tags.trimmingCharacters(in: .whitespaces).isEmpty,
            cancel: model.cancelPrompt, submit: { model.changeTags(adding: adding, tags: tags) }
        ) {
            TextField("Tags", text: $tags, prompt: Text("Separate tags with spaces"))
                .labelsHidden()
                .focused($focused)
                .onAppear { focused = true }
                .textInputSuggestions {
                    ForEach(suggestions, id: \.self) { tag in
                        Text(tag).textInputCompletion(completed(with: tag))
                    }
                }
        }
    }

    private func completed(with tag: String) -> String {
        var words = tags.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        words[words.count - 1] = tag
        return words.joined(separator: " ") + " "
    }
}

private struct FindAndReplaceSheet: View {
    let model: BrowserModel
    let notes: Int
    let fields: [String]
    @State private var find = ""
    @State private var replacement = ""
    @State private var target = ReplaceTarget.allFields
    @State private var selectedOnly = true
    @FocusState private var focused: Bool
    @AppStorage("FindAndReplace.regex") private var regex = false
    @AppStorage("FindAndReplace.ignoreCase") private var ignoreCase = true

    var body: some View {
        PromptLayout(
            title: "Find and Replace", action: "Replace All", canSubmit: !find.isEmpty, cancel: model.cancelPrompt,
            submit: {
                model.findAndReplace(
                    find: find, replacement: replacement, in: target, selectedOnly: selectedOnly, regex: regex,
                    matchCase: !ignoreCase)
            }
        ) {
            Form {
                TextField("Find:", text: $find)
                    .focused($focused)
                    .onAppear { focused = true }
                TextField("Replace with:", text: $replacement)
                Picker("In:", selection: $target) {
                    Text("All Fields").tag(ReplaceTarget.allFields)
                    Text("Tags").tag(ReplaceTarget.tags)
                    if !fields.isEmpty {
                        Divider()
                        ForEach(fields, id: \.self) { Text($0).tag(ReplaceTarget.field($0)) }
                    }
                }
                Toggle("Selected notes only (\(noteCount(notes)))", isOn: $selectedOnly)
                Toggle("Ignore case", isOn: $ignoreCase)
                Toggle("Treat input as regular expression", isOn: $regex)
            }
            .formStyle(.columns)
        }
    }
}
