import SwiftUI

/// The selected deck before studying: what's due and Study Now.
struct DeckOverview: View {
    @Environment(CollectionModel.self) private var model
    let deck: DeckNode

    var body: some View {
        VStack(spacing: Theme.Spacing.xLarge) {
            Text(deck.name)
                .font(Theme.Fonts.overviewTitle)
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.xLarge) {
                count(deck.newCount, "New", Theme.Colors.newCards)
                count(deck.learnCount, "Learning", Theme.Colors.learnCards)
                count(deck.reviewCount, "To Review", Theme.Colors.reviewCards)
            }

            if deck.dueCount > 0 {
                Button("Study Now") { model.startStudying() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Nothing is due in this deck right now.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Options…") { model.showOptions(deck) }
                Button(Tr.statisticsTitle) { StatisticsWindowController.show(collection: model) }
                    .help("\(Tr.statisticsTitle) (T)")
                if deck.filtered {
                    Button(Tr.actionsRebuild) { model.rebuildFilteredDeck(deck.id) }
                        .help("\(Tr.actionsRebuild) (R)")
                    Button(Tr.studyingEmpty) { model.emptyFilteredDeck(deck.id) }
                        .help("\(Tr.studyingEmpty) (E)")
                } else {
                    Button("\(Tr.actionsCustomStudy)…") { model.showCustomStudy(deck.id) }
                        .help("\(Tr.actionsCustomStudy) (C)")
                }
                if model.selectedBuried.any {
                    Button(model.selectedBuried.manually && model.selectedBuried.siblings
                        ? "\(Tr.studyingUnbury)…" : Tr.studyingUnbury
                    ) { model.askUnbury(deck.id) }
                        .help("\(Tr.studyingUnbury) (U)")
                }
            }
        }
        .padding(Theme.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The counts change with every refresh, so this follows unburying too.
        .task(id: deck) {
            model.selectedBuried = await model.buriedCards(in: deck)
        }
    }

    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            Text(value, format: .number)
                .font(Theme.Fonts.overviewCount)
                .foregroundStyle(value == 0 ? Theme.Colors.zeroCount : color)
            Text(label)
                .font(Theme.Fonts.overviewCountLabel)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
