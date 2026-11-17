import Charts
import SwiftUI

// MARK: Hover and click

/// Tracks the pointer over a chart's plot: `hit` turns its x value into a
/// bar, which gets a tooltip and, when `tap` is given, opens a search.
private struct ChartHover<Tip: View>: View {
    let proxy: ChartProxy
    let hit: (Double) -> Int?
    @ViewBuilder let tip: (Int) -> Tip
    let tap: ((Int) -> Void)?
    @Binding var hovered: Int?
    @State private var location: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        location = point
                        hovered = proxy.value(atX: point.x - plot.minX, as: Double.self).flatMap(hit)
                    case .ended:
                        hovered = nil
                    }
                }
                .gesture(SpatialTapGesture().onEnded { event in
                    guard let tap, let index = proxy.value(atX: event.location.x - plot.minX, as: Double.self).flatMap(hit)
                    else { return }
                    tap(index)
                })
                .overlay(alignment: .topLeading) {
                    if let hovered {
                        let pointer = location, bounds = geometry.size
                        let offset = Theme.Statistics.tooltipOffset
                        // Beside the pointer, on whichever side has room.
                        ChartTooltip { tip(hovered) }
                            .alignmentGuide(.leading) { size in
                                let x = pointer.x > bounds.width / 2 ? pointer.x - offset - size.width : pointer.x + offset
                                return -min(max(x, plot.minX), max(plot.maxX - size.width, plot.minX))
                            }
                            .alignmentGuide(.top) { size in
                                -max(min(pointer.y + offset, bounds.height - size.height), plot.minY)
                            }
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

/// The floating box beside the pointer.
struct ChartTooltip<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(Theme.Statistics.tooltipFont)
            .fixedSize()
            .padding(Theme.Spacing.small)
            .foregroundStyle(Theme.Palette.text)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Statistics.tooltipRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.Statistics.tooltipRadius).strokeBorder(Theme.Palette.hairline))
            .shadow(radius: 4, y: 2)
    }
}

/// Which bar of `bounds` contains `x`.
private func barIndex(_ x: Double, in bounds: [(Double, Double)]) -> Int? {
    bounds.firstIndex { x >= $0.0 && x < $0.1 } ?? (bounds.last.map { x == $0.1 } == true ? bounds.count - 1 : nil)
}

/// A colour key beside a label in a table or tooltip.
struct Swatch: View {
    let colour: Color

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Statistics.swatchRadius)
            .fill(colour)
            .strokeBorder(Theme.Palette.hairline)
            .frame(width: Theme.Statistics.swatchSize, height: Theme.Statistics.swatchSize)
            .accessibilityHidden(true)
    }
}

// MARK: Accessibility

extension EnvironmentValues {
    /// The graph a chart is drawn for, which names it to VoiceOver.
    @Entry var graphTitle = ""
}

/// What VoiceOver and Audio Graphs read for a chart: one value per bar,
/// each with the words its tooltip shows.
struct BarsDescriptor: AXChartDescriptorRepresentable {
    struct Point {
        let x: String
        let value: Double
        let label: String
    }

    let title: String
    let points: [Point]
    var valueLabel: (Double) -> String = { localizedNumber($0) }

    func makeChartDescriptor() -> AXChartDescriptor {
        let top = max(points.map(\.value).max() ?? 0, 1)
        let x = AXCategoricalDataAxisDescriptor(title: title, categoryOrder: points.map(\.x))
        let y = AXNumericDataAxisDescriptor(title: title, range: 0...top, gridlinePositions: []) { valueLabel($0) }
        let series = AXDataSeriesDescriptor(
            name: title, isContinuous: false,
            dataPoints: points.map { AXDataPoint(x: $0.x, y: $0.value, label: $0.label) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}

/// The same for a chart of lines: each line a series by name, at most
/// `limit` of its points, since a curve is drawn from a thousand.
struct LinesDescriptor: AXChartDescriptorRepresentable {
    struct Line {
        let name: String
        let points: [(x: Double, y: Double)]
    }

    let title: String
    let xTitle: String
    let yTitle: String
    let lines: [Line]
    let xLabel: (Double) -> String
    let yLabel: (Double) -> String
    var limit = 200

    func makeChartDescriptor() -> AXChartDescriptor {
        let xs = lines.flatMap { $0.points.map(\.x) }
        let ys = lines.flatMap { $0.points.map(\.y) }
        let x = AXNumericDataAxisDescriptor(
            title: xTitle, range: (xs.min() ?? 0)...(xs.max() ?? 0), gridlinePositions: []) { xLabel($0) }
        let y = AXNumericDataAxisDescriptor(
            title: yTitle, range: (ys.min() ?? 0)...(ys.max() ?? 0), gridlinePositions: []) { yLabel($0) }
        let series = lines.map { line in
            let stride = max(1, Int((Double(line.points.count) / Double(limit)).rounded(.up)))
            return AXDataSeriesDescriptor(
                name: line.name, isContinuous: true,
                dataPoints: line.points.indices.filter { $0 % stride == 0 }.map {
                    AXDataPoint(x: line.points[$0].x, y: line.points[$0].y)
                })
        }
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: series)
    }
}

extension View {
    /// Names a chart and hands VoiceOver its lines.
    func chartAccessibility(_ lines: LinesDescriptor) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(lines.title)
            .accessibilityChartDescriptor(lines)
    }

    /// Names a chart and hands VoiceOver its bars.
    func chartAccessibility(_ title: String, _ points: [BarsDescriptor.Point],
                            valueLabel: @escaping (Double) -> String = { localizedNumber($0) }) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityChartDescriptor(BarsDescriptor(title: title, points: points, valueLabel: valueLabel))
    }
}

// MARK: Marks

/// A bar over `span`, from `bottom` up to `top`.
private func bar(_ span: (Double, Double), from bottom: Double = 0, to top: Double, _ colour: Color) -> some ChartContent {
    RectangleMark(
        xStart: .value("From", span.0), xEnd: .value("To", span.1),
        yStart: .value("Bottom", bottom), yEnd: .value("Top", top))
        .foregroundStyle(colour)
}

/// A histogram bar's span, narrowed to leave a gap beside its neighbours.
private func inset(_ span: (Double, Double)) -> (Double, Double) {
    let inset = (span.1 - span.0) * Theme.Statistics.barInset
    return (span.0 + inset, span.1 - inset)
}

/// The running total shaded behind a histogram: zero at the start of the
/// first bar, then the total so far at the end of each, times `scale`.
private struct RunningTotal: ChartContent {
    let points: [(x: Double, y: Double)]

    init(spans: [(Double, Double)], cumulative: [Double], scale: Double) {
        points = [(spans.first?.0 ?? 0, 0)] + zip(spans, cumulative).map { ($0.1, $1 * scale) }
    }

    var body: some ChartContent {
        ForEach(points.indices, id: \.self) { index in
            AreaMark(x: .value("Day", points[index].x), y: .value("Running total", points[index].y))
                .foregroundStyle(Theme.Statistics.areaFill)
                .interpolationMethod(.monotone)
        }
    }
}

// MARK: Axes

/// Upstream's y axes: about five round ticks on a domain rounded up by d3.
private struct ValueAxis {
    let max: Double
    let ticks: [Double]

    init(maxValue: Double, nice: Bool = true) {
        max = nice ? GraphScale.nice((0, maxValue)).1 : maxValue
        ticks = GraphScale.ticks(0, max, count: Theme.Statistics.yTickCount)
    }
}

@AxisContentBuilder
private func valueMarks(
    _ values: [Double], position: AxisMarkPosition, grid: Bool = true, anchor: UnitPoint? = nil,
    label: @escaping (Double) -> String
) -> some AxisContent {
    AxisMarks(position: position, values: values) { value in
        if grid { AxisGridLine().foregroundStyle(Theme.Statistics.gridLine) }
        AxisTick().foregroundStyle(Theme.Statistics.gridLine)
        // Labels that would overlap are dropped.
        AxisValueLabel(anchor: anchor, collisionResolution: .greedy) {
            if let number = value.as(Double.self) { Text(label(number)).font(Theme.Statistics.axisFont) }
        }
    }
}

// MARK: Histogram

/// Upstream's HistogramGraph: bars over a numeric axis, and optionally a
/// running total shaded behind them with its own scale on the right.
struct HistogramChart: View {
    let histogram: Histogram
    let search: (String) -> Void
    @Environment(\.graphTitle) private var title
    @State private var hovered: Int?

    var body: some View {
        let bins = histogram.bins
        let axis = ValueAxis(maxValue: bins.map(\.value).max() ?? 0)
        let cumulative = histogram.cumulative
        let area = ValueAxis(maxValue: histogram.total)
        let areaScale = area.max > 0 ? axis.max / area.max : 0
        let spans = bins.map { ($0.x0, $0.x1) }
        Chart {
            if histogram.showArea, areaScale > 0 {
                RunningTotal(spans: spans, cumulative: cumulative, scale: areaScale)
            }
            // Over the running total, which would otherwise hide it.
            if let hovered { bar(spans[hovered], to: axis.max, Theme.Statistics.hoverColumn) }
            ForEach(bins.indices, id: \.self) { index in
                bar(inset(spans[index]), to: bins[index].value, histogram.colour(bins[index].x1))
            }
        }
        .chartXScale(domain: histogram.domain.0...histogram.domain.1)
        .chartYScale(domain: 0...max(axis.max, 1))
        .chartXAxis {
            valueMarks(
                GraphScale.ticks(histogram.domain.0, histogram.domain.1, count: Theme.Statistics.xTickCount),
                position: .bottom, grid: false, anchor: .top, label: histogram.xTickFormat)
        }
        .chartYAxis {
            valueMarks(axis.ticks, position: .leading) { localizedNumber($0) }
            if histogram.showArea, areaScale > 0 {
                valueMarks(area.ticks.map { $0 * areaScale }, position: .trailing, grid: false) {
                    localizedNumber($0 / areaScale)
                }
            }
        }
        .chartOverlay { proxy in
            ChartHover(
                proxy: proxy, hit: { barIndex($0, in: spans) },
                tip: { index in
                    let percent = histogram.showArea && histogram.total > 0 ? cumulative[index] / histogram.total * 100 : 0
                    Text(histogram.hoverText(bins[index], cumulative[index], percent))
                },
                tap: { index in
                    if !bins[index].points.isEmpty { search(histogram.search(bins[index])) }
                },
                hovered: $hovered)
        }
        .frame(height: Theme.Statistics.chartHeight)
        .chartAccessibility(title, bins.indices.map { index in
            let percent = histogram.showArea && histogram.total > 0 ? cumulative[index] / histogram.total * 100 : 0
            return .init(
                x: histogram.xTickFormat(bins[index].x0), value: bins[index].value,
                label: histogram.hoverText(bins[index], cumulative[index], percent))
        })
    }
}

// MARK: Reviews

/// Upstream's Reviews graph: each bar stacks the five kinds of review.
struct ReviewsChart: View {
    let graph: ReviewsGraph
    @Environment(\.graphTitle) private var title
    @State private var hovered: Int?

    var body: some View {
        let bars = graph.bars
        let axis = ValueAxis(maxValue: bars.map(\.sum).max() ?? 0)
        let cumulative = graph.cumulative
        let area = ValueAxis(maxValue: cumulative.last ?? 0)
        let areaScale = area.max > 0 ? axis.max / area.max : 0
        let spans = bars.map { ($0.x0, $0.x1) }
        Chart {
            if areaScale > 0 { RunningTotal(spans: spans, cumulative: cumulative, scale: areaScale) }
            if let hovered { bar(spans[hovered], to: axis.max, Theme.Statistics.hoverColumn) }
            ForEach(bars) { segments($0) }
        }
        .chartXScale(domain: graph.domain.0...graph.domain.1)
        .chartYScale(domain: 0...max(axis.max, 1))
        .chartXAxis {
            valueMarks(
                GraphScale.ticks(graph.domain.0, graph.domain.1, count: Theme.Statistics.xTickCount),
                position: .bottom, grid: false, anchor: .top) { localizedNumber($0) }
        }
        .chartYAxis {
            valueMarks(axis.ticks, position: .leading, label: graph.tickLabel)
            if areaScale > 0 {
                valueMarks(area.ticks.map { $0 * areaScale }, position: .trailing, grid: false) {
                    graph.tickLabel($0 / areaScale)
                }
            }
        }
        .chartOverlay { proxy in
            ChartHover(
                proxy: proxy, hit: { barIndex($0, in: spans) },
                tip: { index in tooltip(bars[index], cumulative: cumulative[index]) },
                tap: nil, hovered: $hovered)
        }
        .frame(height: Theme.Statistics.chartHeight)
        .chartAccessibility(title, bars.map { bar in
            let kinds = ReviewKind.allCases.reversed().map { "\($0.label) \(graph.valueLabel(bar.totals[$0.rawValue]))" }
            return .init(x: graph.dayRange(bar), value: bar.sum, label: kinds.joined(separator: ", "))
        }, valueLabel: graph.valueLabel)
    }

    /// One bar's five kinds, stacked mature first.
    private func segments(_ reviews: ReviewsGraph.Bar) -> some ChartContent {
        ForEach(ReviewKind.allCases) { kind in
            bar(
                inset((reviews.x0, reviews.x1)), from: reviews.top(kind) - reviews.totals[kind.rawValue],
                to: reviews.top(kind), kind.colour)
        }
    }

    private func tooltip(_ bar: ReviewsGraph.Bar, cumulative: Double) -> some View {
        Grid(alignment: .leading, verticalSpacing: Theme.Spacing.xxSmall) {
            GridRow {
                Text(graph.dayRange(bar))
                Text(graph.valueLabel(bar.sum)).gridColumnAlignment(.trailing)
            }
            ForEach(ReviewKind.allCases.reversed()) { kind in
                GridRow {
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Swatch(colour: kind.colour)
                        Text(kind.label)
                    }
                    Text(graph.valueLabel(bar.totals[kind.rawValue]))
                }
            }
            GridRow {
                Text(Tr.statisticsRunningTotal).padding(.leading, Theme.Statistics.swatchIndent)
                Text(graph.valueLabel(cumulative))
            }
        }
    }
}

// MARK: Hourly Breakdown

/// Reviews per hour of the day, with the share answered correctly as a
/// shaded curve on a 0-100% scale.
struct HoursChart: View {
    let graph: HoursGraph
    @Environment(\.graphTitle) private var title
    @State private var hovered: Int?

    var body: some View {
        let axis = ValueAxis(maxValue: Double(graph.maxTotal))
        let pad = Theme.Statistics.bandPadding / 2
        let span = { (hour: Int) in (Double(hour) + pad, Double(hour + 1) - pad) }
        Chart {
            if let hovered { bar(span(hovered), to: Double(graph.maxTotal), Theme.Statistics.hoverColumn) }
            ForEach(graph.hours.filter { $0.total > 0 }) { hour in
                AreaMark(x: .value("Hour", Double(hour.id) + 0.5), y: .value("Correct", hour.ratio * axis.max))
                    .foregroundStyle(Theme.Statistics.areaFill)
                    .interpolationMethod(.monotone)
            }
            ForEach(graph.hours) { hour in
                bar(span(hour.id), to: Double(hour.total), graph.colour(hour))
            }
        }
        .chartXScale(domain: 0.0...24.0)
        .chartYScale(domain: 0...max(axis.max, 1))
        .chartXAxis {
            valueMarks((0..<24).map { Double($0) + 0.5 }, position: .bottom, grid: false, anchor: .top) { String(Int($0)) }
        }
        .chartYAxis {
            valueMarks(axis.ticks, position: .leading) { localizedNumber($0) }
            valueMarks(GraphScale.ticks(0, 1, count: Theme.Statistics.yTickCount).map { $0 * axis.max },
                       position: .trailing, grid: false) { "\(Int(($0 / axis.max * 100).rounded()))%" }
        }
        .chartOverlay { proxy in
            ChartHover(
                proxy: proxy, hit: { (0..<24).contains(Int(floor($0))) ? Int(floor($0)) : nil },
                tip: { tooltip(graph.hours[$0]) }, tap: nil, hovered: $hovered)
        }
        .frame(height: Theme.Statistics.chartHeight)
        .chartAccessibility(title, graph.hours.map {
            .init(x: String($0.id), value: Double($0.total), label: graph.tooltip($0))
        })
    }

    private func tooltip(_ hour: HoursGraph.Hour) -> some View {
        let lines = graph.tooltipLines(hour)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
            Text(lines.range)
            HStack(spacing: Theme.Spacing.xSmall) {
                Swatch(colour: graph.colour(hour))
                Text(lines.reviews)
            }
            HStack(spacing: Theme.Spacing.xSmall) {
                Swatch(colour: Theme.Statistics.areaFill)
                Text(lines.correct)
            }
        }
    }
}

// MARK: Answer Buttons

/// Presses of each answer button, grouped by learning, young and mature.
struct ButtonsChart: View {
    let graph: ButtonsGraph
    @Environment(\.graphTitle) private var title
    @State private var hovered: Int?

    /// d3's band scale for four buttons in a group, padded by a band each side.
    private static let step = 1 / (4 - Theme.Statistics.bandPadding + 2)

    private func span(_ bar: ButtonsGraph.Bar) -> (Double, Double) {
        let group = Double(ButtonsGraph.Group.allCases.firstIndex(of: bar.group)!)
        let start = group + Self.step * Double(bar.button)
        return (start, start + Self.step * (1 - Theme.Statistics.bandPadding))
    }

    var body: some View {
        let bars = graph.bars
        let axis = ValueAxis(maxValue: Double(graph.maxCount), nice: false)
        Chart {
            if let hovered { bar(span(bars[hovered]), to: axis.max, Theme.Statistics.hoverColumn) }
            ForEach(bars) { button in
                bar(span(button), to: Double(button.count), ButtonsGraph.colour(button.button))
            }
        }
        .chartXScale(domain: 0.0...3.0)
        .chartYScale(domain: 0...max(axis.max, 1))
        .chartXAxis {
            valueMarks([0.5, 1.5, 2.5], position: .bottom, grid: false, anchor: .top) {
                ButtonsGraph.Group.allCases[Int($0)].label
            }
        }
        .chartYAxis {
            valueMarks(axis.ticks, position: .leading) { localizedNumber($0) }
        }
        .chartOverlay { proxy in
            ChartHover(
                proxy: proxy, hit: { x in bars.firstIndex { let s = span($0); return x >= s.0 && x < s.1 } },
                tip: { Text(graph.tooltip(bars[$0])) }, tap: nil, hovered: $hovered)
        }
        .frame(height: Theme.Statistics.chartHeight)
        .chartAccessibility(title, bars.map {
            .init(x: "\($0.group.label) \($0.button)", value: Double($0.count), label: graph.tooltip($0))
        })
    }
}

// MARK: Calendar

/// A year of review counts, one square per day, a column per week. In a
/// narrow window the days keep a size that can be read and clicked, and
/// the year scrolls, starting at today.
struct CalendarChart: View {
    let graph: CalendarGraph
    let setFirstWeekday: (CalendarGraph.Weekday) -> Void
    let search: (String) -> Void
    @Environment(\.graphTitle) private var title
    @State private var hovered: CalendarGraph.Day?
    @State private var gridSize: CGSize = .zero

    var body: some View {
        let byPosition = Dictionary(graph.days.map { ($0.week * 7 + $0.weekday, $0) }) { first, _ in first }
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let weeks = Theme.Statistics.calendarWeeks
        let gap = Theme.Statistics.calendarGap
        let minWidth = Theme.Statistics.calendarLabelWidth + CGFloat(weeks) * (Theme.Statistics.calendarMinCell + gap)
        ScrollView(.horizontal) {
            Grid(horizontalSpacing: gap, verticalSpacing: gap) {
                ForEach(0..<7, id: \.self) { row in
                    GridRow {
                        weekday(graph.weekdays[row], symbols: symbols)
                        ForEach(0..<weeks, id: \.self) { week in
                            if let day = byPosition[week * 7 + row] {
                                cell(day)
                            } else {
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
            .containerRelativeFrame(.horizontal) { width, _ in max(width, minWidth) }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { gridSize = $0 }
            // One hover for the grid, the day found from where the pointer is:
            // each day's own onHover keeps its place from before the year
            // scrolled to today, and lights a day far from the pointer.
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = day(at: point, in: byPosition)
                case .ended: hovered = nil
                }
            }
            .pointerStyle((hovered?.count ?? 0) > 0 ? .link : nil)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .defaultScrollAnchor(.trailing)
        // Drawn outside the scroll view, which would clip it at the top row.
        .overlayPreferenceValue(HoveredDayKey.self) { anchor in
            GeometryReader { geometry in
                if let anchor, let hovered {
                    let cell = geometry[anchor], bounds = geometry.size
                    let offset = Theme.Statistics.calendarTooltipGap
                    ChartTooltip { Text(tooltip(hovered)) }
                        .alignmentGuide(.leading) { size in
                            -min(max(cell.midX - size.width / 2, 0), max(bounds.width - size.width, 0))
                        }
                        .alignmentGuide(.top) { size in size.height + offset - cell.minY }
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .accessibilityChartDescriptor(BarsDescriptor(title: title, points: graph.days.filter { $0.count > 0 }.map {
            let date = $0.date.formatted(date: .abbreviated, time: .omitted)
            return .init(x: date, value: Double($0.count), label: "\(date), \(Tr.statisticsReviews(reviews: $0.count))")
        }))
    }

    private var summary: String {
        Tr.statisticsReviews(reviews: graph.days.reduce(0) { $0 + $1.count })
    }

    /// A weekday's letter, which makes that day start the week when clicked.
    @ViewBuilder private func weekday(_ weekday: Int, symbols: [String]) -> some View {
        let label = Text(symbols[weekday])
            .font(Theme.Statistics.axisFont)
            .foregroundStyle(Theme.Palette.secondary)
            .frame(width: Theme.Statistics.calendarLabelWidth, alignment: .trailing)
        if let choice = CalendarGraph.Weekday(rawValue: weekday) {
            Button { setFirstWeekday(choice) } label: { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[weekday])
                .accessibilityAddTraits(weekday == graph.weekdays.first ? .isSelected : [])
        } else {
            label
        }
    }

    /// The day under a point in the grid: the weekday letters take the
    /// first column, then a column per week, each day owning the gap after it.
    private func day(at point: CGPoint, in byPosition: [Int: CalendarGraph.Day]) -> CalendarGraph.Day? {
        let weeks = Theme.Statistics.calendarWeeks, gap = Theme.Statistics.calendarGap
        let label = Theme.Statistics.calendarLabelWidth + gap
        let column = (gridSize.width - label + gap) / CGFloat(weeks)
        let row = (gridSize.height + gap) / 7
        guard point.x >= label, column > 0, row > 0 else { return nil }
        let week = Int((point.x - label) / column), weekday = Int(point.y / row)
        guard (0..<weeks).contains(week), (0..<7).contains(weekday) else { return nil }
        return byPosition[week * 7 + weekday]
    }

    private func tooltip(_ day: CalendarGraph.Day) -> String {
        "\(day.date.formatted(date: .complete, time: .omitted))\n\(Tr.statisticsReviews(reviews: day.count))"
    }

    private func cell(_ day: CalendarGraph.Day) -> some View {
        let isHovered = hovered?.id == day.id
        return RoundedRectangle(cornerRadius: Theme.Statistics.calendarRadius)
            .fill(graph.colour(day.count))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: Theme.Statistics.calendarRadius)
                        .strokeBorder(Theme.Palette.text, lineWidth: Theme.Statistics.calendarHoverBorder)
                }
            }
            .anchorPreference(key: HoveredDayKey.self, value: .bounds) { isHovered ? $0 : nil }
            .onTapGesture { if day.count > 0 { search("\"prop:rated=\(day.day)\"") } }
    }
}

/// Where the hovered day sits, for its tooltip.
private struct HoveredDayKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: Card Counts

/// A pie of the card states beside a table, each row searching its cards.
struct CardCountsChart: View {
    let graph: CardCountsGraph
    let search: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xLarge) { pie; table }
            VStack(alignment: .leading, spacing: Theme.Spacing.large) { pie; table }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pie: some View {
        Chart(graph.rows) { row in
            SectorMark(angle: .value("Cards", row.count))
                .foregroundStyle(row.colour)
        }
        .chartLegend(.hidden)
        .frame(width: Theme.Statistics.pieSize, height: Theme.Statistics.pieSize)
        .opacity(graph.total > 0 ? 1 : 0)
        // The table beside it reads the same counts, as buttons.
        .accessibilityHidden(true)
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.large, verticalSpacing: Theme.Spacing.xSmall) {
            ForEach(graph.rows.filter(\.shown)) { row in
                GridRow {
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Swatch(colour: row.colour)
                        Button(row.label) { search(row.search) }
                            .buttonStyle(.link)
                            .foregroundStyle(Theme.Palette.text)
                    }
                    Text(localizedNumber(Double(row.count))).font(Theme.Statistics.figures).gridColumnAlignment(.trailing)
                    Text(graph.percent(row))
                        .font(Theme.Statistics.figures)
                        .foregroundStyle(Theme.Palette.secondary)
                        .gridColumnAlignment(.trailing)
                }
            }
            GridRow {
                Text(Tr.statisticsCountsTotalCards)
                    .foregroundStyle(Theme.Palette.secondary)
                    .padding(.leading, Theme.Statistics.swatchIndent)
                Text(localizedNumber(Double(graph.total))).font(Theme.Statistics.figures)
                Text("")
            }
        }
        .font(Theme.Statistics.tableFont)
        .fixedSize()
    }
}

// MARK: True Retention

struct TrueRetentionTable: View {
    let graph: TrueRetentionGraph
    let mode: TrueRetentionGraph.Mode

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: Theme.Spacing.large, verticalSpacing: Theme.Spacing.xSmall) {
            switch mode {
            case .summary:
                header([
                    (Tr.statisticsTrueRetentionYoung, Theme.Statistics.youngRetention),
                    (Tr.statisticsTrueRetentionMature, Theme.Statistics.matureRetention),
                    (Tr.statisticsTrueRetentionTotal, Theme.Palette.text),
                    (Tr.statisticsTrueRetentionCount, Theme.Palette.secondary),
                ])
                ForEach(graph.rows) { row in
                    let passed = row.youngPassed + row.maturePassed, failed = row.youngFailed + row.matureFailed
                    GridRow {
                        Text(row.title).font(Theme.Statistics.tableFont).gridColumnAlignment(.leading)
                        Text(TrueRetentionGraph.retention(passed: row.youngPassed, failed: row.youngFailed))
                            .foregroundStyle(Theme.Statistics.youngRetention)
                        Text(TrueRetentionGraph.retention(passed: row.maturePassed, failed: row.matureFailed))
                            .foregroundStyle(Theme.Statistics.matureRetention)
                        Text(TrueRetentionGraph.retention(passed: passed, failed: failed))
                        Text(localizedNumber(Double(passed + failed))).foregroundStyle(Theme.Palette.secondary)
                    }
                }
            case .young, .mature:
                header([
                    (Tr.statisticsTrueRetentionPass, Theme.Statistics.pass),
                    (Tr.statisticsTrueRetentionFail, Theme.Statistics.fail),
                    (Tr.statisticsTrueRetentionRetention, Theme.Palette.text),
                ])
                ForEach(graph.rows) { row in
                    let passed = mode == .young ? row.youngPassed : row.maturePassed
                    let failed = mode == .young ? row.youngFailed : row.matureFailed
                    GridRow {
                        Text(row.title).font(Theme.Statistics.tableFont).gridColumnAlignment(.leading)
                        Text(localizedNumber(Double(passed))).foregroundStyle(Theme.Statistics.pass)
                        Text(localizedNumber(Double(failed))).foregroundStyle(Theme.Statistics.fail)
                        Text(TrueRetentionGraph.retention(passed: passed, failed: failed))
                    }
                }
            }
        }
        .font(Theme.Statistics.figures)
        .foregroundStyle(Theme.Palette.text)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ columns: [(String, Color)]) -> some View {
        GridRow {
            Text("")
            ForEach(columns, id: \.0) { title, colour in
                Text(title).font(Theme.Statistics.tableFont.weight(.semibold)).foregroundStyle(colour)
            }
        }
    }
}

// MARK: Tables

/// The label: value lines under a graph.
struct GraphTable: View {
    let rows: [TableRow]

    var body: some View {
        if !rows.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.medium, verticalSpacing: Theme.Spacing.xSmall) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        Text(row.label).foregroundStyle(Theme.Palette.secondary)
                        Text(row.value).foregroundStyle(Theme.Palette.text).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(Theme.Statistics.tableFont)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
