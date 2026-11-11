import SwiftUI

/// Desktop's Study Deck dialog: a list of every deck narrowed by what is
/// typed, with the selected deck first. Add creates a deck and shows it.
struct StudyDeckSheet: View {
    @Environment(CollectionModel.self) private var model
    @State private var choices: [DeckChoice] = []
    @State private var filter = ""
    @State private var selection: Int64?
    @State private var newName: String?
    @FocusState private var focused: Bool

    /// Desktop's match: every word typed appears in the name, in any order.
    private var shown: [DeckChoice] {
        let words = filter.split(separator: " ")
        return choices.filter { choice in words.allSatisfy { choice.name.localizedCaseInsensitiveContains($0) } }
    }

    /// The chosen deck, while the filter still shows it.
    private var chosen: DeckChoice? {
        shown.first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.decksStudyDeck).font(.headline)
            TextField("Filter", text: $filter, prompt: Text("Filter Decks"))
                .labelsHidden()
                .focused($focused)
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.downArrow) { move(1) }
                .onSubmit(study)
            ScrollViewReader { scroller in
                List(shown, selection: $selection) { choice in
                    Text(choice.name).tag(choice.id)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: Int64.self) { _ in } primaryAction: { _ in study() }
                .onChange(of: selection) { _, id in
                    if let id { scroller.scrollTo(id) }
                }
            }
            HStack {
                Button(Tr.actionsAdd) { newName = chosen?.name ?? filter }
                Spacer()
                Button("Cancel", role: .cancel) { model.studyDeckPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(Tr.decksStudy, action: study)
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen == nil)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Browser.sheetWidth, height: Theme.StudyDeck.sheetHeight)
        .task {
            choices = await model.studyDeckChoices()
            selection = model.selectedDeckID.flatMap { id in choices.first { $0.id == id }?.id } ?? choices.first?.id
            focused = true
        }
        // Typing keeps the choice when it still matches, else takes the first match.
        .onChange(of: filter) {
            if chosen == nil { selection = shown.first?.id }
        }
        .alert(Tr.decksNewDeckName, isPresented: Binding { newName != nil } set: { if !$0 { newName = nil } }) {
            TextField(Tr.decksNewDeckName, text: Binding { newName ?? "" } set: { newName = $0 })
            Button(Tr.actionsAdd) {
                let name = (newName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { model.addDeckAndShow(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func study() {
        if let chosen { model.showOverview(of: chosen.id) }
    }

    /// Up and Down move the choice while the filter field keeps the keys, wrapping round.
    private func move(_ step: Int) -> KeyPress.Result {
        guard !shown.isEmpty else { return .handled }
        let index = shown.firstIndex { $0.id == selection } ?? (step > 0 ? -1 : 0)
        selection = shown[(index + step + shown.count) % shown.count].id
        return .handled
    }
}
