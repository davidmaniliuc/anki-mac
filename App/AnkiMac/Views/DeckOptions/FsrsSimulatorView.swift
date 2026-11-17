import Charts
import SwiftUI

/// The simulator sheet, drawn as the text import sheet: its title as a
/// Headline, its settings as Deck Options' rows with desktop's folded
/// sections under eyebrows, then the graph as one of Statistics', and at
/// the foot what's happening or what failed beside Close and Simulate.
struct FsrsSimulatorView: View {
    @Bindable var simulator: FsrsSimulator
    let close: () -> Void
    @State private var confirmingSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: simulator.workload
                ? Tr.deckConfigFsrsSimulateDesiredRetentionExperimental : Tr.deckConfigFsrsSimulatorExperimental)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.DeckOptions.sectionGap) {
                    settings
                    graph
                }
                .padding(.horizontal, Theme.DeckOptions.margin)
                .padding(.top, Theme.Spacing.small)
                .padding(.bottom, Theme.Spacing.large)
            }
            .scrollEdgeEffectHidden(true, for: .vertical)
            foot
        }
        .frame(
            minWidth: Theme.DeckOptions.simulatorMinSize.width, idealWidth: Theme.DeckOptions.simulatorSize.width,
            minHeight: Theme.DeckOptions.simulatorMinSize.height, idealHeight: Theme.DeckOptions.simulatorSize.height)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .alert(Tr.deckConfigSaveOptionsToPreset, isPresented: $confirmingSave) {
            Button(Tr.actionsCancel, role: .cancel) {}
            Button(Tr.deckConfigSaveOptionsToPreset) { simulator.saveToPreset() }
        } message: {
            Text(Tr.deckConfigSaveOptionsToPresetConfirm)
        }
        // VoiceOver hears what the foot shows: the work starting, then why it failed.
        .onChange(of: simulator.busy) { _, busy in
            if busy { AccessibilityNotification.Announcement(Tr.actionsProcessing).post() }
        }
        .onChange(of: simulator.failure) { _, failure in
            if let failure { AccessibilityNotification.Announcement(failure.detail).post() }
        }
    }

    // MARK: Settings

    @ViewBuilder private var settings: some View {
        OptionSection {
            OptionRow(title: Tr.deckConfigDaysToSimulate, revertible: false) {
                NumberField(value: $simulator.daysToSimulate, range: 1...3650)
            }
            OptionRow(title: Tr.deckConfigAdditionalNewCardsToSimulate, revertible: false) {
                NumberField(value: $simulator.additionalNewCards, range: 0...100_000)
            }
            if !simulator.workload {
                OptionRow(title: Tr.deckConfigDesiredRetention, revertible: false) {
                    NumberField(value: $simulator.desiredRetention, range: 0.7...0.99, step: 0.01, percent: true)
                }
            }
            OptionRow(title: Tr.schedulingNewCardsday, revertible: false) {
                NumberField(value: $simulator.newLimit)
            }
            OptionRow(title: Tr.schedulingMaximumReviewsday, revertible: false) {
                NumberField(value: $simulator.reviewLimit)
            }
        }
        FoldedSection(title: Tr.deckConfigEasyDaysTitle) {
            OptionSection { EasyDaysSliders(values: $simulator.easyDays, revertible: false) }
        }
        FoldedSection(title: Tr.deckConfigAdvancedSettings) {
            OptionSection {
                OptionRow(title: Tr.schedulingMaximumInterval, revertible: false) {
                    NumberField(value: $simulator.maxInterval, range: 1...36500)
                }
                OptionRow(title: Tr.deckConfigReviewSortOrder, revertible: false) {
                    OptionPicker(selection: $simulator.reviewOrder, choices: reviewOrderChoices(fsrs: true))
                }
                OptionRow(title: Tr.deckConfigNewCardsIgnoreReviewLimit, revertible: false) {
                    SwitchControl(title: Tr.deckConfigNewCardsIgnoreReviewLimit, isOn: $simulator.newCardsIgnoreReviewLimit)
                }
                OptionRow(title: Tr.deckConfigSmoothGraph, revertible: false) {
                    SwitchControl(title: Tr.deckConfigSmoothGraph, isOn: $simulator.smooth)
                }
                OptionRow(title: Tr.deckConfigSuspendLeeches, revertible: false) {
                    SwitchControl(title: Tr.deckConfigSuspendLeeches, isOn: $simulator.suspendLeeches)
                }
                if simulator.suspendLeeches {
                    OptionRow(title: Tr.schedulingLeechThreshold, revertible: false) {
                        NumberField(value: $simulator.leechThreshold, range: 1...9999)
                    }
                }
            }
        }
        if !simulator.workload {
            FoldedSection(title: Tr.deckConfigComputeOptimalRetention) { optimalRetention }
        }
    }

    /// Desktop's explanation as a caption, Compute as a chip, then how far
    /// it has got or what it found, in the rounded face.
    private var optimalRetention: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(markdown(Tr.deckConfigComputeOptimalRetentionTooltip4))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Spacing.medium) {
                Button(simulator.computingRetention ? Tr.actionsCancel : Tr.deckConfigComputeButton) {
                    simulator.computeRetention()
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(simulator.simulating)
                Group {
                    if let iterations = simulator.retentionIterations, simulator.computingRetention {
                        Text(figures(Tr.deckConfigIterations(count: String(iterations))))
                            .foregroundStyle(Theme.Palette.secondary)
                    } else if let optimal = simulator.optimalRetention {
                        Text(figures(Tr.deckConfigPredictedOptimalRetention(
                            num: optimal.formatted(.number.precision(.fractionLength(2))))))
                    }
                }
                .font(Theme.DeckOptions.rowFont)
            }
            if let optimal = simulator.optimalRetention, optimal - simulator.desiredRetention >= 0.01 {
                OptionWarning(text: Tr.deckConfigDesiredRetentionBelowOptimal)
            }
        }
        .padding(.top, Theme.Spacing.xSmall)
    }

    // MARK: Graph

    /// One of Statistics' graphs: unboxed under a hairline, its switch as
    /// quiet segments, the chart, then what can be done with the runs.
    private var graph: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            QuietSegments(selection: $simulator.graph, choices: simulator.graphs) { $0.title }
                // The first word lines up with the rows above, the chosen one's wash reaching past it.
                .padding(.leading, -Theme.Layout.segmentPadding)
            if simulator.points.isEmpty {
                NoData(height: Theme.DeckOptions.chartHeight)
            } else {
                SimulatorChart(simulator: simulator)
            }
            ActionRow {
                Button(Tr.deckConfigClearLastSimulate) { simulator.clearLast() }
                    .disabled(simulator.busy || simulator.runCount == 0)
                Button(Tr.deckConfigSaveOptionsToPreset + "…") { confirmingSave = true }
                    .disabled(simulator.busy)
            }
        }
        .padding(.top, Theme.Statistics.sectionPadding)
        .overlay(alignment: .top) { Theme.Palette.hairline.frame(height: 1) }
    }

    // MARK: Foot

    /// What's happening or what failed, then Close as a chip and Simulate,
    /// the sheet's one Primary.
    private var foot: some View {
        HStack(spacing: Theme.Spacing.small) {
            if simulator.busy {
                ProgressView().controlSize(.small).accessibilityHidden(true)
                Text(Tr.actionsProcessing)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            } else if let failure = simulator.failure {
                OptionWarning(text: failure.detail, level: .danger, verbatim: true).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            Button(Tr.actionsClose, action: close)
                .buttonStyle(ChipButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button { simulator.simulate() } label: {
                HStack(spacing: Theme.Layout.keyCapGap) {
                    Text(Tr.deckConfigSimulate)
                    KeyCap("\u{21A9}", onAccent: true)
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .keyboardShortcut(.defaultAction)
            .disabled(simulator.busy)
        }
        .padding(.horizontal, Theme.DeckOptions.margin)
        .padding(.vertical, Theme.Spacing.medium)
    }
}

/// The runs' chart, a view of its own so the pointer crossing it redraws
/// the chart and not the settings over it.
private struct SimulatorChart: View {
    let simulator: FsrsSimulator
    @State private var hovered: Double?

    var body: some View {
        let points = simulator.plotted
        plot(points)
            .frame(height: Theme.DeckOptions.chartHeight)
            .chartAccessibility(LinesDescriptor(
                title: simulator.graph.title,
                xTitle: simulator.workload ? Tr.deckConfigDesiredRetention : Tr.cardStatsReviewLogDate,
                yTitle: simulator.yAxisTitle,
                lines: Dictionary(grouping: points, by: \.run).sorted { $0.key < $1.key }.map { run, points in
                    .init(name: Self.runName(run), points: points.map { (x: $0.x, y: simulator.y($0)) })
                },
                xLabel: { [workload = simulator.workload] x in
                    workload ? "\(Int(x))%" : Self.date(x).formatted(date: .abbreviated, time: .omitted)
                },
                yLabel: { [simulator] in simulator.describe($0) }))
    }

    @ViewBuilder private func plot(_ points: [FsrsSimulator.Point]) -> some View {
        if simulator.workload {
            chart(points, x: { $0.x }, hoveredX: hovered) { location, proxy in
                proxy.value(atX: location, as: Double.self)?.rounded()
            }
            .chartXScale(domain: 70...99)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: Int(Theme.Statistics.xTickCount))) { value in
                    AxisTick().foregroundStyle(Theme.Statistics.gridLine)
                    AxisValueLabel(collisionResolution: .greedy) {
                        if let percent = value.as(Double.self) {
                            Text((percent / 100).formatted(.percent.precision(.fractionLength(0))))
                                .font(Theme.Statistics.axisFont)
                        }
                    }
                }
            }
        } else {
            chart(points, x: { Self.date($0.x) }, hoveredX: hovered.map(Self.date)) { location, proxy in
                proxy.value(atX: location, as: Date.self).map { ($0.timeIntervalSince(Self.today) / 86_400).rounded() }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: Int(Theme.Statistics.xTickCount))) { _ in
                    AxisTick().foregroundStyle(Theme.Statistics.gridLine)
                    AxisValueLabel(collisionResolution: .greedy).font(Theme.Statistics.axisFont)
                }
            }
        }
    }

    /// One line per run in desktop's category colours, and at the hovered
    /// day or retention a rule with every run's value beside it.
    private func chart<X: Plottable>(
        _ points: [FsrsSimulator.Point], x: @escaping (FsrsSimulator.Point) -> X, hoveredX: X?,
        hover: @escaping (CGFloat, ChartProxy) -> Double?
    ) -> some View {
        let xTitle = simulator.workload ? Tr.deckConfigDesiredRetention : Tr.cardStatsReviewLogDate
        let runs = (1...max(simulator.runCount, 1)).map(Self.runName)
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value(xTitle, x(point)), y: .value(simulator.yAxisTitle, simulator.y(point)))
                    .foregroundStyle(by: .value("Run", Self.runName(point.run)))
                    .lineStyle(StrokeStyle(lineWidth: Theme.DeckOptions.runLineWidth, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if simulator.workload, simulator.graph == .memorized, let start = points.first?.reviewlessEndMemorized {
                RuleMark(y: .value("Without reviews", start))
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: Theme.CardInfo.curveDash))
            }
            if let hoveredX, let hovered {
                RuleMark(x: .value(xTitle, hoveredX))
                    .foregroundStyle(Theme.Palette.tertiary)
                    .annotation(
                        position: .trailing, alignment: .top, spacing: Theme.Statistics.tooltipOffset,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) { readout(points, at: hovered) }
            }
        }
        .chartForegroundStyleScale(domain: runs, range: runs.indices.map(Self.runColour))
        .chartLegend(.hidden)
        .chartYAxisLabel {
            Text(simulator.yAxisTitle)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: Int(Theme.Statistics.yTickCount))) { value in
                AxisGridLine().foregroundStyle(Theme.Statistics.gridLine)
                AxisTick().foregroundStyle(Theme.Statistics.gridLine)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(simulator.graph == .time ? FsrsSimulator.duration(number) : number.formatted())
                            .font(Theme.Statistics.axisFont)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                // The pointer's place is the overlay's; the proxy reads the plot's.
                let plot = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hovered = hover(location.x - plot.minX, proxy)
                        case .ended: hovered = nil
                        }
                    }
            }
        }
    }

    /// Each run's value at the hovered day or retention, as desktop's
    /// tooltip, each led by its line's colour.
    private func readout(_ points: [FsrsSimulator.Point], at x: Double) -> some View {
        ChartTooltip {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text(simulator.workload
                    ? "\(Tr.deckConfigDesiredRetention): \(Int(x))%"
                    : Self.date(x).formatted(date: .abbreviated, time: .omitted))
                ForEach(points.filter { $0.x == x }) { point in
                    HStack(spacing: Theme.Spacing.xSmall) {
                        Swatch(colour: Self.runColour(point.run - 1))
                        Text("\(Self.runName(point.run)): \(simulator.describe(simulator.y(point)))")
                    }
                }
            }
        }
    }

    private static let today = Calendar.current.startOfDay(for: Date())

    private static func date(_ day: Double) -> Date {
        today.addingTimeInterval(day * 86_400)
    }

    private static func runName(_ run: Int) -> String { "#\(run)" }

    private static func runColour(_ index: Int) -> Color {
        let colours = Theme.DeckOptions.runColours
        return colours[index % colours.count]
    }
}

/// Desktop's folded settings: the eyebrow with a chevron after it, which
/// turns as the section opens, and its rows under it once open.
private struct FoldedSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { open.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.xSmall) {
                    Eyebrow(title)
                    Image(systemName: "chevron.right")
                        .font(Theme.DeckOptions.foldSymbol)
                        .foregroundStyle(Theme.Palette.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(height: Theme.DeckOptions.helpSize.height)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open { content }
        }
    }
}
