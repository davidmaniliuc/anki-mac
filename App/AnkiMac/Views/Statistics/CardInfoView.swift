import AnkiKit
import SwiftUI

/// Desktop's Card Info on the canvas: the band naming the window, then the
/// card's numbers as rows under hairlines, its review log as a dense table,
/// and, when FSRS has a memory state for it, the forgetting curve as a
/// Statistics graph.
struct CardInfoView: View {
    let model: CardInfoModel
    let title: String
    let close: () -> Void
    @State private var scrolled = false

    var body: some View {
        VStack(spacing: 0) {
            band
                // Once the rows scroll under the band, a hairline marks
                // where they go out of sight, as Deck Options'.
                .overlay(alignment: .bottom) {
                    Theme.Palette.hairline.frame(height: 1).opacity(scrolled && model.stats != nil ? 1 : 0)
                }
            if let stats = model.stats {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.CardInfo.sectionGap) {
                        CardStatsRows(rows: CardInfoFormat.rows(stats))
                        if !stats.revlog.isEmpty {
                            RevlogTable(rows: CardInfoFormat.revlogRows(stats.revlog))
                        }
                        if stats.hasMemoryState {
                            ForgettingCurveSection(stats: stats)
                        }
                    }
                    .frame(maxWidth: Theme.CardInfo.columnWidth)
                    .padding(.horizontal, Theme.CardInfo.margin)
                    .padding(.bottom, Theme.CardInfo.margin)
                    .frame(maxWidth: .infinity)
                }
                .scrollEdgeEffectHidden(true, for: .vertical)
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0 } action: {
                    scrolled = $1
                }
            } else {
                Text(Tr.cardStatsNoCard)
                    .font(Theme.Fonts.lead)
                    .foregroundStyle(Theme.Palette.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.Palette.canvas)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        // Esc closes the window whatever has the focus; nothing in it
        // takes any, so an exit command would never reach it.
        .background {
            Button(Tr.actionsClose, action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// The window's name after the traffic lights.
    private var band: some View {
        Text(title)
            .font(Theme.Band.titleFont)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .padding(.leading, Theme.Band.leading)
            .padding(.trailing, Theme.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: Theme.Band.height, maxHeight: Theme.Band.height, alignment: .leading)
            .titleBarBand()
    }
}

/// The card's numbers in upstream's order: each label in Pencil with its
/// value in Ink at the trailing edge, numbers in the rounded face, as
/// Statistics' tables are, under hairlines as Deck Options' rows. A name
/// (the deck, the note type) keeps its digits in its own face.
private struct CardStatsRows: View {
    let rows: [CardInfoFormat.Row]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                if row.id != rows.first?.id { Theme.Palette.hairline.frame(height: 1) }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
                    Text(row.label)
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize()
                    Spacer(minLength: Theme.Spacing.small)
                    Text(row.numeric ? figures(row.value) : AttributedString(row.value))
                        .foregroundStyle(Theme.Palette.text)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(Theme.CardInfo.font)
                .padding(.vertical, Theme.Spacing.xSmall)
                .frame(minHeight: Theme.CardInfo.rowHeight)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The review log, newest first, as dense as the Browser's table: column
/// titles in the eyebrow's face, one hairline under them, 26pt rows with no
/// grid. Figures keep to their column's trailing edge with their title, and
/// a unit after one ("months", "D:") stays in the row's face.
private struct RevlogTable: View {
    let rows: [CardInfoFormat.RevlogRow]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: Theme.CardInfo.revlogColumnGap, verticalSpacing: 0) {
                GridRow {
                    header(Tr.cardStatsReviewLogDate)
                    header(Tr.cardStatsReviewLogType)
                    header(Tr.cardStatsReviewLogRating).gridColumnAlignment(.trailing)
                    header(Tr.cardStatsInterval).gridColumnAlignment(.trailing)
                    header(Tr.cardStatsEase).gridColumnAlignment(.trailing)
                    header(Tr.cardStatsReviewLogTimeTaken).gridColumnAlignment(.trailing)
                }
                .frame(height: Theme.CardInfo.revlogHeaderHeight)
                // Room for the hairline, drawn across the whole column below.
                Color.clear.frame(height: 1)
                ForEach(rows) { row in
                    GridRow {
                        HStack(spacing: Theme.Spacing.xSmall) {
                            Text(row.date).font(Theme.CardInfo.revlogFigures)
                            Text("@ \(row.time)")
                                .font(Theme.CardInfo.revlogFigures)
                                .foregroundStyle(Theme.Palette.secondary)
                        }
                        Text(row.kindLabel)
                            .foregroundStyle(color(row.kind))
                        Text(String(row.rating))
                            .font(Theme.CardInfo.revlogFigures)
                            .foregroundStyle(row.rating == 1 ? Theme.CardInfo.revlogRelearn : Theme.Palette.text)
                        Text(figures(row.interval, font: Theme.CardInfo.revlogFigures))
                        Text(figures(row.ease, font: Theme.CardInfo.revlogFigures))
                        Text(figures(row.taken, font: Theme.CardInfo.revlogFigures))
                    }
                    .font(Theme.CardInfo.font)
                    .lineLimit(1)
                    .frame(height: Theme.CardInfo.revlogRowHeight)
                    .accessibilityElement(children: .combine)
                }
            }
            .fixedSize()
            .textSelection(.enabled)
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // Under the titles, as wide as the rows' hairlines however narrow the table.
        .overlay(alignment: .top) {
            Theme.Palette.hairline.frame(height: 1).offset(y: Theme.CardInfo.revlogHeaderHeight)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(Theme.Fonts.eyebrow)
            .foregroundStyle(Theme.Palette.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func color(_ kind: Anki_Stats_RevlogEntry.ReviewKind) -> Color {
        switch kind {
        case .learning: Theme.CardInfo.revlogLearn
        case .review: Theme.CardInfo.revlogReview
        case .relearning: Theme.CardInfo.revlogRelearn
        default: Theme.Palette.text
        }
    }
}

/// The forgetting curve as one of Statistics' graphs: unboxed under a
/// hairline, its title, its ranges as quiet segments, then the chart.
private struct ForgettingCurveSection: View {
    let stats: Anki_Stats_CardStatsResponse

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.cardStatsFsrsForgettingCurveTitle)
                .font(Theme.Fonts.panelTitle)
                .accessibilityAddTraits(.isHeader)
            ForgettingCurveChart(stats: stats)
        }
        .padding(.top, Theme.Statistics.sectionPadding)
        .overlay(alignment: .top) {
            Theme.Palette.hairline.frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
