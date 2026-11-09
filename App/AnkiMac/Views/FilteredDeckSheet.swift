import AnkiKit
import SwiftUI

/// Desktop's filtered deck dialog as a sheet on the main window: name, one
/// or two searches, rescheduling and the preview delays, then Build (or
/// Rebuild for an existing deck).
struct FilteredDeckSheet: View {
    @Bindable var deck: FilteredDeckModel
    let cancel: () -> Void
    let built: (Int64) -> Void
    let showInBrowser: (String) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(label(Tr.actionsName), text: $deck.name)
                }
                searchSection(Tr.actionsFilter, $deck.first)
                    .focused($searchFocused)
                Section {
                    Toggle(Tr.decksEnableSecondFilter, isOn: $deck.secondEnabled)
                }
                if deck.secondEnabled {
                    searchSection(Tr.decksFilter2, $deck.second)
                }
                Section {
                    Toggle(Tr.decksRescheduleCardsBasedOnMyAnswers, isOn: $deck.reschedule)
                    if !deck.reschedule {
                        delay(Tr.studyingAgain, $deck.previewAgain)
                        delay(Tr.studyingHard, $deck.previewHard)
                        delay(Tr.studyingGood, $deck.previewGood)
                    }
                    Toggle("Create or update this deck even if empty", isOn: $deck.allowEmpty)
                } header: {
                    Text("Options")
                } footer: {
                    HStack {
                        if !deck.reschedule {
                            Text(Tr.decksZeroMinutesHint).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(Tr.decksUnmovableCards) { show { try deck.excludedCardsSearch() } }
                            .buttonStyle(.link)
                            .help(Tr.searchViewInBrowser)
                    }
                    .font(.callout)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(deck.isNew ? Tr.decksBuild : Tr.actionsRebuild) {
                    Task { if let id = await deck.build() { built(id) } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(deck.building || deck.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Theme.Spacing.large)
        }
        .frame(width: Theme.FilteredDeck.sheetWidth, height: Theme.FilteredDeck.sheetHeight)
        .navigationTitle(Tr.actionsOptionsFor(val: deck.name))
        .onAppear { searchFocused = true }
        .alert(
            deck.error ?? "", isPresented: Binding { deck.error != nil } set: { if !$0 { deck.error = nil } }
        ) {
            Button("OK") {}
        }
    }

    private func searchSection(_ title: String, _ search: Binding<FilteredSearch>) -> some View {
        Section {
            HStack {
                TextField("Search", text: search.search)
                Button("Search", systemImage: "magnifyingglass") {
                    show { try deck.normalisedSearch(search.wrappedValue.search) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(Tr.searchViewInBrowser)
            }
            TextField(Tr.decksLimitTo, value: search.limit, format: .number)
            Picker(sentenceStart(Tr.decksCardsSelectedBy), selection: search.order) {
                ForEach(deck.orders, id: \.order) { order in
                    Text(order.label).tag(order.order)
                }
            }
        } header: {
            Text(title)
        }
    }

    private func delay(_ button: String, _ seconds: Binding<Int>) -> some View {
        LabeledContent(Tr.decksDelayForButton(button: button)) {
            HStack(spacing: Theme.Spacing.xSmall) {
                TextField(Tr.decksDelayForButton(button: button), value: seconds, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: Theme.FilteredDeck.secondsWidth)
                Text(Tr.schedulingSeconds).foregroundStyle(.secondary)
            }
        }
    }

    /// Opens a search in the browser, or says why it isn't valid.
    private func show(_ search: () throws -> String) {
        do {
            showInBrowser(try search())
        } catch {
            deck.error = FilteredDeckModel.message(error)
        }
    }

    /// "Name:" as a form label.
    private func label(_ text: String) -> String {
        text.hasSuffix(":") ? String(text.dropLast()) : text
    }

    /// "cards selected by" as a label of its own.
    private func sentenceStart(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
