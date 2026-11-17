import AnkiKit
import Charts
import SwiftUI

/// Retrievability over time since the first review, solid up to now and dashed
/// after, coloured red below the preset's desired retention and green above.
struct ForgettingCurveChart: View {
    let stats: Anki_Stats_CardStatsResponse
    @State private var chosenRange: ForgettingCurve.Range?
    @State private var hoveredDate: Date?

    private var filtered: [ForgettingCurve.Entry] { ForgettingCurve.filter(stats.revlog) }
    private var allTimeDays: Double { ForgettingCurve.maxDays(filtered, range: .allTime) }
    private var range: ForgettingCurve.Range { chosenRange ?? .defaultRange(maxDays: allTimeDays) }
    private var desiredRetention: Double { Double(stats.hasDesiredRetention ? stats.desiredRetention : 0.9) * 100 }

    var body: some View {
        let maxDays = ForgettingCurve.maxDays(filtered, range: range)
        let points = ForgettingCurve.points(
            filtered, maxDays: maxDays, decay: ForgettingCurve.decay(params: stats.fsrsParams))
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            let ranges = ForgettingCurve.Range.available(maxDays: allTimeDays)
            if !ranges.isEmpty {
                QuietSegments(selection: Binding(get: { range }, set: { chosenRange = $0 }), choices: ranges) { $0.label }
                    // The first word lines up with the title, the chosen one's wash reaching past it.
                    .padding(.leading, -Theme.Layout.segmentPadding)
            }
            if points.isEmpty {
                NoData(height: Theme.CardInfo.curveHeight)
            } else {
                chart(points, maxDays: maxDays)
            }
        }
        .onChange(of: stats.cardID) { chosenRange = nil }
    }

    private func chart(_ points: [ForgettingCurve.Point], maxDays: Double) -> some View {
        let now = Date()
        let past = points.filter { $0.date <= now }
        let future = points.filter { $0.date >= now }
        let lowest = points.map(\.retrievability).min() ?? 0
        let bottom = max(0, 100 - 1.2 * (100 - lowest))
        let hovered = hoveredDate.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        return Chart {
            ForEach(past) { line($0, series: "past", gradient: gradient(past), dashed: false) }
            ForEach(future) { line($0, series: "future", gradient: gradient(future), dashed: true) }
            if desiredRetention > bottom {
                RuleMark(y: .value(Tr.cardStatsFsrsForgettingCurveDesiredRetention, desiredRetention))
                    .foregroundStyle(Theme.CardInfo.curveTarget)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: Theme.CardInfo.curveDash))
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered.date))
                    .foregroundStyle(Theme.Palette.hairline)
                    .annotation(
                        position: .top, spacing: Theme.Spacing.xSmall,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) { tooltip(hovered, maxDays: maxDays) }
                PointMark(x: .value("Date", hovered.date), y: .value(Tr.cardStatsFsrsRetrievability, hovered.retrievability))
                    .symbolSize(Theme.CardInfo.hoverPointSize)
                    .foregroundStyle(color(at: hovered.retrievability))
            }
        }
        .chartYScale(domain: bottom...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: Int(Theme.Statistics.xTickCount))) { _ in
                AxisTick().foregroundStyle(Theme.Statistics.gridLine)
                AxisValueLabel(collisionResolution: .greedy).font(Theme.Statistics.axisFont)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: Int(Theme.Statistics.yTickCount))) { value in
                AxisGridLine().foregroundStyle(Theme.Statistics.gridLine)
                AxisTick().foregroundStyle(Theme.Statistics.gridLine)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text("\(Int(v))%").font(Theme.Statistics.axisFont) }
                }
            }
        }
        .chartXSelection(value: $hoveredDate)
        .frame(height: Theme.CardInfo.curveHeight)
        .padding(.top, Theme.Spacing.large)
        .chartAccessibility(LinesDescriptor(
            title: Tr.cardStatsFsrsForgettingCurveTitle, xTitle: Tr.cardStatsReviewLogDate,
            yTitle: Tr.cardStatsFsrsRetrievability,
            lines: [.init(
                name: Tr.cardStatsFsrsRetrievability,
                points: points.map { (x: $0.date.timeIntervalSince1970, y: $0.retrievability) })],
            xLabel: { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) },
            yLabel: { "\(Int($0.rounded()))%" }))
    }

    private func line(_ point: ForgettingCurve.Point, series: String, gradient: LinearGradient, dashed: Bool) -> some ChartContent {
        LineMark(
            x: .value("Date", point.date), y: .value(Tr.cardStatsFsrsRetrievability, point.retrievability),
            series: .value("Series", series)
        )
        .foregroundStyle(gradient)
        .lineStyle(StrokeStyle(lineWidth: Theme.CardInfo.curveWidth, dash: dashed ? Theme.CardInfo.curveDash : []))
    }

    private func tooltip(_ point: ForgettingCurve.Point, maxDays: Double) -> some View {
        let date = maxDays >= 365
            ? point.date.formatted(date: .numeric, time: .omitted)
            : point.date.formatted(date: .numeric, time: .shortened)
        return ChartTooltip {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text(date)
                Text("\(Tr.cardStatsReviewLogElapsedTime): \(CardInfoFormat.timeSpan(point.elapsedDays * 86400))")
                Text("\(Tr.cardStatsFsrsRetrievability): \(String(format: "%.2f", point.retrievability))%")
                Text("\(Tr.cardStatsFsrsStability): \(CardInfoFormat.timeSpan(point.stability * 86400))")
                if abs(point.retrievability - desiredRetention) < 5 {
                    Text("\(Tr.cardStatsFsrsForgettingCurveDesiredRetention): \(String(format: "%.0f", desiredRetention))%")
                }
            }
        }
    }

    /// Red up to the desired retention, then blue, then green at 100%, placed
    /// along the series' own value range, since a gradient spans its line.
    private func gradient(_ series: [ForgettingCurve.Point]) -> LinearGradient {
        let values = series.map(\.retrievability)
        guard let low = values.min(), let high = values.max(), high > low else {
            return LinearGradient(colors: [color(at: values.first ?? 100)], startPoint: .bottom, endPoint: .top)
        }
        var marks = [low, high]
        if desiredRetention > low, desiredRetention < high { marks.insert(desiredRetention, at: 1) }
        return LinearGradient(
            stops: marks.map { .init(color: color(at: $0), location: ($0 - low) / (high - low)) },
            startPoint: .bottom, endPoint: .top)
    }

    private func color(at value: Double) -> Color {
        let desired = max(desiredRetention, 0.001)
        if value <= desired {
            return Theme.CardInfo.curveLow.mix(with: Theme.CardInfo.curveTarget, by: value / desired)
        }
        return Theme.CardInfo.curveTarget.mix(
            with: Theme.CardInfo.curveHigh, by: (value - desired) / max(100 - desired, 0.001))
    }
}
