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
                if deck.filtered {
                    Button(Tr.actionsRebuild) { model.rebuildFilteredDeck(deck.id) }
                        .help("\(Tr.actionsRebuild) (R)")
                    Button(Tr.studyingEmpty) { model.emptyFilteredDeck(deck.id) }
                        .help("\(Tr.studyingEmpty) (E)")
                }
            }
        }
        .padding(Theme.Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
