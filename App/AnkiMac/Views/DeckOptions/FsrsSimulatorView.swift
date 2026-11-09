import Charts
import SwiftUI

/// The simulator sheet: its settings, the runs so far as one line each, and
/// a pointer readout of every run at the hovered day or retention.
struct FsrsSimulatorView: View {
    @Bindable var simulator: FsrsSimulator
    let close: () -> Void
    @State private var hovered: Double?
    @State private var confirmingSave = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                settings
                chart
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if simulator.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(Tr.actionsClose, action: close)
                    .keyboardShortcut(.cancelAction)
                Button(Tr.deckConfigSimulate) { simulator.simulate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(simulator.busy)
            }
            .padding(Theme.Spacing.large)
        }
        .frame(
            minWidth: Theme.DeckOptions.simulatorMinSize.width, idealWidth: Theme.DeckOptions.simulatorSize.width,
            minHeight: Theme.DeckOptions.simulatorMinSize.height, idealHeight: Theme.DeckOptions.simulatorSize.height)
        .alert(
            simulator.errorMessage ?? "",
            isPresented: Binding { simulator.errorMessage != nil } set: { if !$0 { simulator.errorMessage = nil } }
        ) {
            Button("OK") {}
        }
        .alert(Tr.deckConfigSaveOptionsToPresetConfirm, isPresented: $confirmingSave) {
            Button("Cancel", role: .cancel) {}
            Button(Tr.deckConfigSaveOptionsToPreset) { simulator.saveToPreset() }
        }
    }

    // MARK: Settings

    @ViewBuilder private var settings: some View {
        Section {
            OptionRow(title: Tr.deckConfigDaysToSimulate) {
                NumberField(value: $simulator.daysToSimulate, range: 1...3650)
            }
            OptionRow(title: Tr.deckConfigAdditionalNewCardsToSimulate) {
                NumberField(value: $simulator.additionalNewCards, range: 0...100_000)
            }
            if !simulator.workload {
                OptionRow(title: Tr.deckConfigDesiredRetention) {
                    NumberField(value: $simulator.desiredRetention, range: 0.7...0.99, step: 0.01, percent: true)
                }
            }
            OptionRow(title: Tr.schedulingNewCardsday) {
                NumberField(value: $simulator.newLimit)
            }
            OptionRow(title: Tr.schedulingMaximumReviewsday) {
                NumberField(value: $simulator.reviewLimit)
            }
            DisclosureGroup(Tr.deckConfigEasyDaysTitle) {
                EasyDaysSliders(values: $simulator.easyDays)
            }
            DisclosureGroup(Tr.deckConfigAdvancedSettings) {
                OptionRow(title: Tr.schedulingMaximumInterval) {
                    NumberField(value: $simulator.maxInterval, range: 1...36500)
                }
                OptionRow(title: Tr.deckConfigReviewSortOrder) {
                    Picker(Tr.deckConfigReviewSortOrder, selection: $simulator.reviewOrder) {
                        ForEach(reviewOrderChoices(fsrs: true), id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                OptionRow(title: Tr.deckConfigNewCardsIgnoreReviewLimit) {
                    Toggle("", isOn: $simulator.newCardsIgnoreReviewLimit).labelsHidden().toggleStyle(.switch)
                }
                OptionRow(title: Tr.deckConfigSmoothGraph) {
                    Toggle("", isOn: $simulator.smooth).labelsHidden().toggleStyle(.switch)
                }
                OptionRow(title: Tr.deckConfigSuspendLeeches) {
                    Toggle("", isOn: $simulator.suspendLeeches).labelsHidden().toggleStyle(.switch)
                }
                if simulator.suspendLeeches {
                    OptionRow(title: Tr.schedulingLeechThreshold) {
                        NumberField(value: $simulator.leechThreshold, range: 1...9999)
                    }
                }
            }
            if !simulator.workload {
                DisclosureGroup(Tr.deckConfigComputeOptimalRetention) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        Text(markdown(Tr.deckConfigComputeOptimalRetentionTooltip4))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(simulator.computingRetention ? Tr.actionsCancel : Tr.deckConfigComputeButton) {
                                simulator.computeRetention()
                            }
                            .disabled(simulator.simulating)
                            if let iterations = simulator.retentionIterations, simulator.computingRetention {
                                Text(Tr.deckConfigIterations(count: String(iterations)))
                                    .font(.callout).foregroundStyle(.secondary)
                            } else if let optimal = simulator.optimalRetention {
                                Text(Tr.deckConfigPredictedOptimalRetention(
                                    num: optimal.formatted(.number.precision(.fractionLength(2)))))
                            }
                        }
                        if let optimal = simulator.optimalRetention, optimal - simulator.desiredRetention >= 0.01 {
                            OptionWarning(text: Tr.deckConfigDesiredRetentionBelowOptimal)
                        }
                    }
                }
            }
        } header: {
            Text(simulator.workload
                ? Tr.deckConfigFsrsSimulateDesiredRetentionExperimental : Tr.deckConfigFsrsSimulatorExperimental)
        }
    }

    // MARK: Chart

    @ViewBuilder private var chart: some View {
        Section {
            Picker("Graph", selection: $simulator.graph) {
                ForEach(simulator.graphs) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if simulator.points.isEmpty {
                Text("Run a simulation to see its graph here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: Theme.DeckOptions.chartHeight)
            } else {
                plot.frame(height: Theme.DeckOptions.chartHeight)
                if let hovered { readout(at: hovered) }
            }
            HStack {
                Button(Tr.deckConfigClearLastSimulate) { simulator.clearLast() }
                    .disabled(simulator.busy || simulator.runCount == 0)
                Spacer()
                Button(Tr.deckConfigSaveOptionsToPreset + "…") { confirmingSave = true }
                    .disabled(simulator.busy)
            }
        }
    }

    @ViewBuilder private var plot: some View {
        if simulator.workload {
            chart(x: { $0.x }, hoveredX: hovered) { location, proxy in
                proxy.value(atX: location, as: Double.self)?.rounded()
            }
            .chartXScale(domain: 70...99)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text((percent / 100).formatted(.percent.precision(.fractionLength(0))))
                        }
                    }
                }
            }
        } else {
            chart(x: { date($0.x) }, hoveredX: hovered.map(date)) { location, proxy in
                proxy.value(atX: location, as: Date.self).map { ($0.timeIntervalSince(Self.today) / 86_400).rounded() }
            }
        }
    }

    /// One line per run, with the hovered position marked.
    private func chart<X: Plottable>(
        x: @escaping (FsrsSimulator.Point) -> X, hoveredX: X?,
        hover: @escaping (CGFloat, ChartProxy) -> Double?
    ) -> some View {
        let points = simulator.plotted
        let xTitle = simulator.workload ? Tr.deckConfigDesiredRetention : "Date"
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value(xTitle, x(point)), y: .value(simulator.yAxisTitle, simulator.y(point)))
                    .foregroundStyle(by: .value("Run", "#\(point.run)"))
                    .interpolationMethod(.monotone)
            }
            if simulator.workload, simulator.graph == .memorized, let start = points.first?.reviewlessEndMemorized {
                RuleMark(y: .value("Without reviews", start))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            if let hoveredX {
                RuleMark(x: .value(xTitle, hoveredX)).foregroundStyle(.secondary)
            }
        }
        .chartYAxisLabel(simulator.yAxisTitle)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(simulator.graph == .time ? FsrsSimulator.duration(number) : number.formatted())
                    }
                }
            }
        }
        .chartOverlay { proxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hovered = hover(location.x, proxy)
                    case .ended: hovered = nil
                    }
                }
        }
    }

    /// Each run's value at the hovered day or retention, as desktop's tooltip.
    private func readout(at x: Double) -> some View {
        let points = simulator.plotted.filter { $0.x == x }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Text(simulator.workload
                ? "\(Tr.deckConfigDesiredRetention): \(Int(x))%"
                : date(x).formatted(date: .abbreviated, time: .omitted))
                .font(.callout.weight(.semibold))
            ForEach(points) { point in
                Text("#\(point.run): \(simulator.describe(simulator.y(point)))")
                    .font(.callout.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let today = Calendar.current.startOfDay(for: Date())

    private func date(_ day: Double) -> Date {
        Self.today.addingTimeInterval(day * 86_400)
    }
}
