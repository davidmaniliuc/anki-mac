import SwiftUI

/// The sheet for a `BrowserPrompt`: one short form, Cancel and one default
/// button named for what it does, as desktop's dialogs ask the same things.
struct BrowserPromptSheet: View {
    let prompt: BrowserPrompt
    let model: BrowserModel

    var body: some View {
        switch prompt {
        case .setDueDate(let cards, let days):
            SetDueDateSheet(model: model, cards: cards, days: days)
        case .forget(let cards, let restorePosition, let resetCounts):
            ForgetSheet(model: model, cards: cards, restorePosition: restorePosition, resetCounts: resetCounts)
        case .reposition(let cards, let top, let bottom, let randomize, let shift):
            RepositionSheet(
                model: model, cards: cards, queueTop: top, queueBottom: bottom, randomize: randomize, shift: shift)
        case .changeDeck(let cards, let decks, let current):
            ChangeDeckSheet(model: model, cards: cards, decks: decks, selection: current)
        case .tags(let adding, let notes, let known):
            TagsSheet(model: model, adding: adding, notes: notes, known: known)
        case .findAndReplace(let notes, let fields):
            FindAndReplaceSheet(model: model, notes: notes, fields: fields)
        }
    }
}

/// Title, form and the button row every prompt shares.
private struct PromptLayout<Content: View>: View {
    let title: String
    let action: String
    var canSubmit = true
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
        .frame(width: Theme.Browser.sheetWidth)
    }
}

private func cardCount(_ count: Int) -> String {
    count == 1 ? "1 card" : "\(count.formatted()) cards"
}

private func noteCount(_ count: Int) -> String {
    count == 1 ? "1 note" : "\(count.formatted()) notes"
}

private struct SetDueDateSheet: View {
    let model: BrowserModel
    let cards: Int
    @State var days: String
    @FocusState private var focused: Bool

    init(model: BrowserModel, cards: Int, days: String) {
        self.model = model
        self.cards = cards
        _days = State(initialValue: days)
    }

    var body: some View {
        PromptLayout(
            title: cards == 1 ? "Show the card in how many days?" : "Show \(cardCount(cards)) in how many days?",
            action: "Set Due Date", canSubmit: !days.trimmingCharacters(in: .whitespaces).isEmpty,
            cancel: model.cancelPrompt, submit: { model.setDueDate(days: days) }
        ) {
            TextField("Days", text: $days, prompt: Text("0"))
                .labelsHidden()
                .focused($focused)
                .onAppear { focused = true }
            // Desktop's hint, word for word.
            Text("0 = today\n1! = tomorrow + change interval to 1\n3-7 = random choice of 3-7 days")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ForgetSheet: View {
    let model: BrowserModel
    let cards: Int
    @State var restorePosition: Bool
    @State var resetCounts: Bool

    init(model: BrowserModel, cards: Int, restorePosition: Bool, resetCounts: Bool) {
        self.model = model
        self.cards = cards
        _restorePosition = State(initialValue: restorePosition)
        _resetCounts = State(initialValue: resetCounts)
    }

    var body: some View {
        PromptLayout(
            title: "Reset \(cardCount(cards)) to new?", action: "Reset", cancel: model.cancelPrompt,
            submit: { model.forget(restorePosition: restorePosition, resetCounts: resetCounts) }
        ) {
            Toggle("Restore original position where possible", isOn: $restorePosition)
            Toggle("Reset repetition and lapse counts", isOn: $resetCounts)
        }
    }
}

private struct RepositionSheet: View {
    let model: BrowserModel
    let cards: Int
    let queueTop: Int
    let queueBottom: Int
    @State var start = 0
    @FocusState private var focused: Bool
    @State var step = 1
    @State var randomize: Bool
    @State var shift: Bool

    init(model: BrowserModel, cards: Int, queueTop: Int, queueBottom: Int, randomize: Bool, shift: Bool) {
        self.model = model
        self.cards = cards
        self.queueTop = queueTop
        self.queueBottom = queueBottom
        _randomize = State(initialValue: randomize)
        _shift = State(initialValue: shift)
    }

    var body: some View {
        PromptLayout(
            title: "Reposition \(cardCount(cards))", action: "Reposition", cancel: model.cancelPrompt,
            submit: { model.reposition(start: start, step: step, randomize: randomize, shift: shift) }
        ) {
            Text("Only new cards move. The new queue runs from \(queueTop) to \(queueBottom).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Start position:", value: $start, format: .number)
                    .focused($focused)
                    .onAppear { focused = true }
                TextField("Step:", value: $step, format: .number)
                Toggle("Randomize order", isOn: $randomize)
                Toggle("Shift position of existing cards", isOn: $shift)
            }
            .formStyle(.columns)
        }
    }
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
