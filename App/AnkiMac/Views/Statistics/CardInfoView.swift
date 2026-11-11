import AnkiKit
import SwiftUI

/// Desktop's Card Info as a grouped form: the card's numbers, its review log,
/// and, when FSRS has a memory state for it, the forgetting curve.
struct CardInfoView: View {
    let model: CardInfoModel

    var body: some View {
        if let stats = model.stats {
            Form {
                Section {
                    ForEach(CardInfoFormat.rows(stats)) { row in
                        LabeledContent(row.label) { Text(row.value).textSelection(.enabled) }
                    }
                }
                if !stats.revlog.isEmpty {
                    Section { RevlogTable(rows: CardInfoFormat.revlogRows(stats.revlog)) }
                }
                if stats.hasMemoryState {
                    Section(Tr.cardStatsFsrsForgettingCurveTitle) { ForgettingCurveChart(stats: stats) }
                }
            }
            .formStyle(.grouped)
        } else {
            Text(Tr.cardStatsNoCard)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The review log, newest first: date, type, rating, interval, ease or difficulty, time taken.
private struct RevlogTable: View {
    let rows: [CardInfoFormat.RevlogRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.medium, verticalSpacing: Theme.Spacing.xSmall) {
            GridRow {
                Text(Tr.cardStatsReviewLogDate)
                Text(Tr.cardStatsReviewLogType)
                Text(Tr.cardStatsReviewLogRating)
                Text(Tr.cardStatsInterval).gridColumnAlignment(.trailing)
                Text(Tr.cardStatsEase)
                Text(Tr.cardStatsReviewLogTimeTaken).gridColumnAlignment(.trailing)
            }
            .fontWeight(.semibold)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(rows) { row in
                GridRow {
                    HStack(spacing: 0) {
                        Text(row.date).fontWeight(.semibold)
                        Text(" @ \(row.time)")
                    }
                    Text(row.kindLabel).foregroundStyle(color(row.kind))
                    Text(String(row.rating)).foregroundStyle(row.rating == 1 ? Theme.Statistics.revlogRelearn : .primary)
                    Text(row.interval)
                    Text(row.ease)
                    Text(row.taken)
                }
            }
        }
        .monospacedDigit()
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func color(_ kind: Anki_Stats_RevlogEntry.ReviewKind) -> Color {
        switch kind {
        case .learning: Theme.Statistics.revlogLearn
        case .review: Theme.Statistics.revlogReview
        case .relearning: Theme.Statistics.revlogRelearn
        default: .primary
        }
    }
}
