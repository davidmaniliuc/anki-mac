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
                Picker("", selection: Binding(get: { range }, set: { chosenRange = $0 })) {
                    ForEach(ranges, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if points.isEmpty {
                Text(Tr.cardStatsNoCard).foregroundStyle(.secondary)
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
                    .foregroundStyle(Theme.Statistics.curveTarget)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered.date))
                    .foregroundStyle(.secondary)
                    .annotation(
                        position: .top, spacing: Theme.Spacing.xSmall,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) { tooltip(hovered, maxDays: maxDays) }
            }
        }
        .chartYScale(domain: bottom...100)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))%") } }
            }
        }
        .chartXSelection(value: $hoveredDate)
        .frame(height: Theme.Statistics.curveHeight)
        .padding(.top, Theme.Spacing.large)
    }

    private func line(_ point: ForgettingCurve.Point, series: String, gradient: LinearGradient, dashed: Bool) -> some ChartContent {
        LineMark(
            x: .value("Date", point.date), y: .value(Tr.cardStatsFsrsRetrievability, point.retrievability),
            series: .value("Series", series)
        )
        .foregroundStyle(gradient)
        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: dashed ? [4, 4] : []))
    }

    private func tooltip(_ point: ForgettingCurve.Point, maxDays: Double) -> some View {
        let date = maxDays >= 365
            ? point.date.formatted(date: .numeric, time: .omitted)
            : point.date.formatted(date: .numeric, time: .shortened)
        return VStack(alignment: .leading) {
            Text(date)
            Text("\(Tr.cardStatsReviewLogElapsedTime): \(CardInfoFormat.timeSpan(point.elapsedDays * 86400))")
            Text("\(Tr.cardStatsFsrsRetrievability): \(String(format: "%.2f", point.retrievability))%")
            Text("\(Tr.cardStatsFsrsStability): \(CardInfoFormat.timeSpan(point.stability * 86400))")
            if abs(point.retrievability - desiredRetention) < 5 {
                Text("\(Tr.cardStatsFsrsForgettingCurveDesiredRetention): \(String(format: "%.0f", desiredRetention))%")
            }
        }
        .font(.caption)
        .padding(Theme.Spacing.small)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
            return Theme.Statistics.curveLow.mix(with: Theme.Statistics.curveTarget, by: value / desired)
        }
        return Theme.Statistics.curveTarget.mix(
            with: Theme.Statistics.curveHigh, by: (value - desired) / max(100 - desired, 0.001))
    }
}
