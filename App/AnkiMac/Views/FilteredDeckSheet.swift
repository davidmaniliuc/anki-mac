import AnkiKit
import SwiftUI

/// Desktop's filtered deck dialog as a sheet on the main window, drawn as
/// Deck Options' settings: the name, one or two searches, rescheduling and
/// the preview delays, then Build (or Rebuild for an existing deck).
struct FilteredDeckSheet: View {
    @Bindable var deck: FilteredDeckModel
    let cancel: () -> Void
    let built: (Int64) -> Void
    let showInBrowser: (String) -> Void

    var body: some View {
        SettingsSheet(
            title: deck.title, width: Theme.FilteredDeck.width, maxHeight: Theme.FilteredDeck.maxHeight
        ) {
            OptionSection {
                OptionRow(title: label(Tr.actionsName), revertible: false) {
                    OptionTextField(text: $deck.name)
                        .frame(width: Theme.FilteredDeck.textColumnWidth)
                }
            }
            OptionSection(title: Tr.actionsFilter) {
                searchRows($deck.first, field: deck.firstField, focusOnAppear: true)
                OptionActions {
                    Button(Tr.decksUnmovableCards) { show { try deck.excludedCardsSearch() } }
                        .help(Tr.searchViewInBrowser)
                }
            }
            OptionSection(title: Tr.decksFilter2) {
                OptionRow(title: Tr.decksEnableSecondFilter, revertible: false) {
                    SwitchControl(title: Tr.decksEnableSecondFilter, isOn: $deck.secondEnabled)
                }
                if deck.secondEnabled {
                    searchRows($deck.second, field: deck.secondField)
                }
            }
            OptionSection(title: Tr.actionsOptions) {
                OptionRow(title: Tr.decksRescheduleCardsBasedOnMyAnswers, revertible: false) {
                    SwitchControl(title: Tr.decksRescheduleCardsBasedOnMyAnswers, isOn: $deck.reschedule)
                }
                if !deck.reschedule {
                    delay(Tr.studyingAgain, $deck.previewAgain)
                    delay(Tr.studyingHard, $deck.previewHard)
                    delay(Tr.studyingGood, $deck.previewGood)
                    Text(Tr.decksZeroMinutesHint)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .optionNote()
                }
                OptionRow(title: Tr.decksCreateEvenIfEmpty, revertible: false) {
                    SwitchControl(title: Tr.decksCreateEvenIfEmpty, isOn: $deck.allowEmpty)
                }
            }
        } footer: {
            if deck.building {
                ProgressView().controlSize(.small)
            } else if let error = deck.error {
                OptionWarning(text: error, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(
                action: deck.isNew ? Tr.decksBuild : Tr.actionsRebuild,
                disabled: deck.building || deck.name.trimmingCharacters(in: .whitespaces).isEmpty,
                cancelDisabled: deck.building, cancel: cancel,
                submit: { Task { if let id = await deck.build() { built(id) } } })
        }
        .task { await deck.loadSidebar() }
    }

    /// A filter's search in the Browser's field, chips and suggestions and
    /// all, with a quiet button that shows it in the Browser, then how many
    /// cards it takes and in what order.
    @ViewBuilder
    private func searchRows(
        _ search: Binding<FilteredSearch>, field: FilteredSearchField, focusOnAppear: Bool = false
    ) -> some View {
        OptionRow(title: Tr.actionsSearch, revertible: false) {
            HStack(spacing: Theme.Spacing.xxSmall) {
                BrowserSearchField(model: field, focusOnAppear: focusOnAppear)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Tr.actionsSearch)
                IconButton("arrow.up.forward.app", help: Tr.searchViewInBrowser) {
                    show { try deck.normalisedSearch(search.wrappedValue.search) }
                }
                // Its hover room hangs past the edge, so the glyph ends
                // where the controls below do.
                .padding(.trailing, -Theme.Spacing.small)
            }
            .frame(width: Theme.FilteredDeck.textColumnWidth)
        }
        OptionRow(title: Tr.decksLimitTo, revertible: false) {
            NumberField(
                value: Binding { Double(search.wrappedValue.limit) } set: { search.wrappedValue.limit = Int($0) },
                range: 1...99999)
        }
        OptionRow(title: sentenceStart(Tr.decksCardsSelectedBy), revertible: false) {
            OptionPicker(selection: search.order, choices: deck.orders.map { ($0.order, $0.label) })
        }
    }

    private func delay(_ button: String, _ seconds: Binding<Int>) -> some View {
        OptionRow(title: Tr.decksDelayForButton(button: button), revertible: false) {
            NumberField(
                value: Binding { Double(seconds.wrappedValue) } set: { seconds.wrappedValue = Int($0) },
                range: 0...99999, unit: Tr.schedulingSeconds)
        }
    }

    /// Opens a search in the browser, or says why it isn't valid.
    private func show(_ search: () throws -> String) {
        do {
            showInBrowser(try search())
        } catch {
            deck.error = ActionFailure.reason(error)
        }
    }

    /// "Name:" as a row's title.
    private func label(_ text: String) -> String {
        text.hasSuffix(":") ? String(text.dropLast()) : text
    }

    /// "cards selected by" as a title of its own.
    private func sentenceStart(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
