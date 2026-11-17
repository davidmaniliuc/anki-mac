import SwiftUI

/// What the whole collection has due today, shown when no deck is picked:
/// the total and its three queues, then each deck with cards due, those with cards in
/// learning first since they come back within minutes.
struct TodayView: View {
    @Environment(CollectionModel.self) private var model

    private struct DueDeck: Identifiable {
        let deck: DeckNode
        let path: String
        var id: Int64 { deck.id }
    }

    /// Decks without subdecks that have cards due, with the path to them.
    private var dueDecks: [DueDeck] {
        func walk(_ nodes: [DeckNode], path: [String]) -> [DueDeck] {
            nodes.flatMap { node -> [DueDeck] in
                if let children = node.children { return walk(children, path: path + [node.name]) }
                return node.dueCount > 0 ? [DueDeck(deck: node, path: path.joined(separator: " › "))] : []
            }
        }
        return walk(model.decks, path: [])
            .sorted { ($0.deck.learnCount, $0.deck.dueCount) > ($1.deck.learnCount, $1.deck.dueCount) }
    }

    /// A greeting for the time of day, then the date, both in the user's
    /// language and redrawn each minute, so they follow midnight.
    private func eyebrow(at date: Date) -> String {
        let greeting = switch Calendar.current.component(.hour, from: date) {
        case 5..<12: String(localized: "Good morning", comment: "Today's greeting before noon")
        case 12..<18: String(localized: "Good afternoon", comment: "Today's greeting from noon to 6 pm")
        default: String(localized: "Good evening", comment: "Today's greeting from 6 pm")
        }
        return greeting + " · " + date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    /// Study Now (Return), Today's one prominent action: the list's first
    /// deck, which is the one with cards in learning or else the most due.
    /// Its session ends back here, where the next deck is then first.
    private func studyButton(first deck: DeckNode) -> some View {
        Button { model.studyFromToday(deck.id) } label: {
            Text("Study Now")
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
        .fixedSize()
        .help("Study \(deck.name)")
        .accessibilityLabel("Study Now: \(deck.name)")
    }

    var body: some View {
        Page {
            TimelineView(.everyMinute) { context in
                PageTitle(eyebrow: eyebrow(at: context.date), title: Tr.statisticsTodayTitle) {
                    AnkiStar(size: 26).foregroundStyle(Theme.Palette.star)
                }
            }

            let due = dueDecks
            if due.isEmpty {
                TimelineView(.everyMinute) { context in
                    Text(nothingDue(at: context.date))
                        .font(Theme.Fonts.lead)
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                let total = (
                    new: model.decks.reduce(0) { $0 + $1.newCount },
                    learn: model.decks.reduce(0) { $0 + $1.learnCount },
                    review: model.decks.reduce(0) { $0 + $1.reviewCount })
                DueSummary(new: total.new, learn: total.learn, review: total.review)
                PageSection(Tr.browsingSidebarDueToday) {
                    ForEach(due) { DeckListRow(deck: $0.deck, path: $0.path, onToday: true) }
                    // A parent deck's limits cap its subdecks together, so the
                    // rows can add up to more than the total.
                    if due.reduce(0, { $0 + $1.deck.dueCount }) != total.new + total.learn + total.review {
                        Text("The total follows your decks’ daily limits, so it can be less than these add up to.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Theme.Spacing.small)
                    }
                }
            }
        }
        .studyBar(shown: !dueDecks.isEmpty) {
            if let first = dueDecks.first { studyButton(first: first.deck) }
        }
        .pageActions { QuickFindButton() }
    }

    /// Nothing is due now: when the next learning card comes back today,
    /// in desktop's words, or else that the day's work is done.
    private func nothingDue(at now: Date) -> String {
        guard let later = model.learnLaterToday else { return "Nothing is due. Come back tomorrow." }
        let secs = max(60, later.next.timeIntervalSince(now))
        let (unit, amount) = secs < 3_600 ? ("minutes", secs / 60) : ("hours", secs / 3_600)
        return Tr.schedulingNextLearnDue(unit: unit, amount: Int(amount.rounded()))
            + " " + Tr.schedulingLearnRemaining(remaining: later.count)
    }
}
