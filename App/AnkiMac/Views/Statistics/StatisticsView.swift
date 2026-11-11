import Charts
import SwiftUI

/// Desktop's graphs, in its order. Each case is one card of the window: its
/// title, when it applies, and (in `GraphCard`) its switches and chart.
enum StatisticsGraph: CaseIterable, Identifiable {
    case today, futureDue, calendar, reviews, cardCounts, intervals, stability, ease, difficulty
    case retrievability, trueRetention, hours, buttons, added

    var id: Self { self }

    var title: String {
        switch self {
        case .today: Tr.statisticsTodayTitle
        case .futureDue: Tr.statisticsFutureDueTitle
        case .calendar: Tr.statisticsCalendarTitle
        case .reviews: Tr.statisticsReviewsTitle
        case .cardCounts: Tr.statisticsCountsTitle
        case .intervals: Tr.statisticsIntervalsTitle
        case .stability: Tr.statisticsCardStabilityTitle
        case .ease: Tr.statisticsCardEaseTitle
        case .difficulty: Tr.statisticsCardDifficultyTitle
        case .retrievability: Tr.statisticsCardRetrievabilityTitle
        case .trueRetention: Tr.statisticsTrueRetentionTitle
        case .hours: Tr.statisticsHoursTitle
        case .buttons: Tr.statisticsAnswerButtonsTitle
        case .added: Tr.statisticsAddedTitle
        }
    }

    func subtitle(_ controls: GraphControls) -> String? {
        switch self {
        case .today, .calendar, .cardCounts: nil
        case .futureDue: Tr.statisticsFutureDueSubtitle
        case .reviews: controls.reviewsShowTime ? Tr.statisticsReviewsTimeSubtitle : Tr.statisticsReviewsCountSubtitle
        case .intervals: Tr.statisticsIntervalsSubtitle
        case .stability: Tr.statisticsCardStabilitySubtitle
        case .ease: Tr.statisticsCardEaseSubtitle
        case .difficulty: Tr.statisticsCardDifficultySubtitle2
        case .retrievability: Tr.statisticsRetrievabilitySubtitle
        case .trueRetention: Tr.statisticsTrueRetentionSubtitle
        case .hours: Tr.statisticsHoursSubtitle
        case .buttons: Tr.statisticsAnswerButtonsSubtitle
        case .added: Tr.statisticsAddedSubtitle
        }
    }

    /// FSRS collections get stability, difficulty and retrievability in
    /// place of ease, as desktop.
    func applies(fsrs: Bool) -> Bool {
        switch self {
        case .stability, .difficulty, .retrievability: fsrs
        case .ease: !fsrs
        default: true
        }
    }
}

/// The window's content: the graphs in one to three columns.
struct StatisticsView: View {
    @Bindable var model: StatisticsModel
    let savePDF: () -> Void
    /// Opens the browser on a search, for clicks on bars and table rows.
    let browse: (String) -> Void
    /// One to three, as desktop's grid at the window's width.
    @State private var columns = 1

    var body: some View {
        ScrollView {
            if let data = model.data {
                let graphs = StatisticsGraph.allCases.filter { $0.applies(fsrs: data.fsrs) }
                let rows = stride(from: 0, to: graphs.count, by: columns).map { graphs[$0..<min($0 + columns, graphs.count)] }
                Grid(horizontalSpacing: Theme.Spacing.large, verticalSpacing: Theme.Spacing.large) {
                    ForEach(rows, id: \.first) { row in
                        GridRow {
                            ForEach(row) { GraphCard(graph: $0, model: model, data: data, browse: browse) }
                        }
                    }
                }
                .padding(Theme.Spacing.large)
            }
        }
        .onGeometryChange(for: Int.self) { proxy in
            let room = proxy.size.width - Theme.Spacing.large
            return max(1, min(3, Int(room / (Theme.Statistics.graphMinWidth + Theme.Spacing.large))))
        } action: { columns = $0 }
        .overlay {
            if model.data == nil {
                if let error = model.errorMessage {
                    ContentUnavailableView(Tr.statisticsTitle, systemImage: "chart.bar", description: Text(error))
                } else {
                    ProgressView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker(Tr.statisticsTitle, selection: $model.scope) {
                Text(Tr.statisticsRangeDeck).tag(StatisticsScope.deck)
                Text(Tr.statisticsRangeCollection).tag(StatisticsScope.collection)
                Text(Tr.statisticsRangeSearch).tag(StatisticsScope.search)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        ToolbarItem(placement: .principal) {
            TextField(Tr.statisticsRangeSearch, text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: Theme.Statistics.searchWidth)
                .onSubmit { model.submitSearch() }
        }
        ToolbarItem(placement: .primaryAction) {
            Picker(Tr.statisticsTitle, selection: $model.history) {
                Text(Tr.statisticsRange1YearHistory).tag(RevlogHistory.year)
                Text(Tr.statisticsRangeAllHistory).tag(RevlogHistory.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        // Only while loading: a hidden one still widens the Save PDF capsule.
        if model.loading {
            ToolbarItem(placement: .primaryAction) {
                ProgressView().controlSize(.small)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: savePDF) {
                Label(Tr.statisticsSavePdf, systemImage: "square.and.arrow.down")
            }
            .help(Tr.statisticsSavePdf)
            .disabled(model.data == nil)
        }
    }
}

/// What a saved PDF leaves out: the switches, which can't be used on paper.
private struct PrintingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var statisticsPrinting: Bool {
        get { self[PrintingKey.self] }
        set { self[PrintingKey.self] = newValue }
    }
}

/// Every graph in one column, for Save PDF.
struct StatisticsPrintView: View {
    let model: StatisticsModel
    let data: GraphsResponse

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            ForEach(StatisticsGraph.allCases.filter { $0.applies(fsrs: data.fsrs) }) { graph in
                GraphCard(graph: graph, model: model, data: data, browse: { _ in })
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Statistics.pdfWidth)
        .groupBoxStyle(PrintedCard())
        .environment(\.statisticsPrinting, true)
    }
}

/// A card ImageRenderer can draw: the system GroupBox is an AppKit box, which
/// it leaves out, keeping only the titles.
private struct PrintedCard: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            configuration.label
            configuration.content
        }
        .padding(Theme.Spacing.medium)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Theme.Statistics.printedCardRadius))
    }
}

// MARK: Cards

/// One graph: its title, subtitle, switches, chart and table, or desktop's
/// "no data" when the range has nothing to show.
private struct GraphCard: View {
    let graph: StatisticsGraph
    @Bindable var model: StatisticsModel
    let data: GraphsResponse
    let browse: (String) -> Void
    @Environment(\.statisticsPrinting) private var printing

    var body: some View {
        GroupBox {
            VStack(spacing: Theme.Spacing.medium) {
                if let subtitle = graph.subtitle(model.controls) {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if !printing { controls }
                content
            }
            .padding(Theme.Spacing.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } label: {
            Text(graph.title).font(.headline)
        }
    }

    private func search(_ query: String) {
        browse(model.search.isEmpty ? query : "\(model.search) \(query)")
    }

    // MARK: Switches

    @ViewBuilder private var controls: some View {
        let history = model.history
        switch graph {
        case .futureDue:
            HStack {
                if data.futureDue.haveBacklog {
                    Toggle(Tr.statisticsBacklogCheckbox, isOn: $model.preferences.futureDueShowBacklog)
                }
                RangePicker(selection: $model.controls.futureDueRange, choices: GraphRange.choices(.all))
            }
        case .calendar:
            let years = CalendarGraph.years(history, current: Calendar.current.component(.year, from: .now))
            HStack {
                Button { model.controls.calendarYear -= 1 } label: { Image(systemName: "chevron.left") }
                    .disabled(model.controls.calendarYear <= years.lowerBound)
                Text(String(model.controls.calendarYear)).monospacedDigit()
                Button { model.controls.calendarYear += 1 } label: { Image(systemName: "chevron.right") }
                    .disabled(model.controls.calendarYear >= years.upperBound)
            }
            .buttonStyle(.borderless)
        case .reviews:
            HStack {
                Toggle(Tr.statisticsReviewsTimeCheckbox, isOn: $model.controls.reviewsShowTime)
                RangePicker(selection: $model.controls.reviewsRange, choices: GraphRange.choices(history))
            }
        case .cardCounts:
            Toggle(Tr.statisticsCountsSeparateSuspendedBuriedCards, isOn: $model.preferences.cardCountsSeparateInactive)
        case .intervals:
            RangePicker(selection: $model.controls.intervalsRange, choices: IntervalRange.allCases)
        case .stability:
            RangePicker(selection: $model.controls.stabilityRange, choices: IntervalRange.allCases)
        case .difficulty:
            RangePicker(selection: $model.controls.difficultyRange, choices: PercentageRange.allCases)
        case .retrievability:
            RangePicker(selection: $model.controls.retrievabilityRange, choices: PercentageRange.allCases)
        case .trueRetention:
            RangePicker(selection: $model.controls.trueRetentionMode, choices: TrueRetentionGraph.Mode.allCases)
        case .hours:
            RangePicker(selection: $model.controls.hoursRange, choices: GraphRange.choices(history))
        case .buttons:
            RangePicker(selection: $model.controls.buttonsRange, choices: GraphRange.choices(history))
        case .added:
            RangePicker(selection: $model.controls.addedRange, choices: GraphRange.choices(.all))
        case .today, .ease:
            EmptyView()
        }
    }

    // MARK: Charts

    @ViewBuilder private var content: some View {
        let controls = model.controls
        switch graph {
        case .today:
            VStack(spacing: Theme.Spacing.xSmall) {
                ForEach(TodayStats.lines(data), id: \.self) { Text($0) }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .futureDue:
            histogram(FutureDueGraph.histogram(
                data, range: controls.futureDueRange, backlog: model.preferences.futureDueShowBacklog))
        case .calendar:
            if let calendar = CalendarGraph(
                data, year: controls.calendarYear, firstWeekday: model.preferences.calendarFirstDayOfWeek,
                history: model.history) {
                CalendarChart(
                    graph: calendar, setFirstWeekday: { model.preferences.calendarFirstDayOfWeek = $0 }, search: search)
            } else {
                NoData()
            }
        case .reviews:
            if let reviews = ReviewsGraph(data, range: controls.reviewsRange, showTime: controls.reviewsShowTime) {
                ReviewsChart(graph: reviews)
                GraphTable(rows: reviews.table)
            } else {
                NoData()
            }
        case .cardCounts:
            CardCountsChart(
                graph: CardCountsGraph(data, separateInactive: model.preferences.cardCountsSeparateInactive),
                search: search)
        case .intervals:
            histogram(IntervalsGraph.histogram(data.intervals.intervals, range: controls.intervalsRange, fsrs: false))
        case .stability:
            histogram(IntervalsGraph.histogram(data.stability.intervals, range: controls.stabilityRange, fsrs: true))
        case .ease:
            histogram(PercentageGraphs.ease(data))
        case .difficulty:
            histogram(PercentageGraphs.difficulty(data, range: controls.difficultyRange))
        case .retrievability:
            histogram(PercentageGraphs.retrievability(data, range: controls.retrievabilityRange))
        case .trueRetention:
            TrueRetentionTable(graph: TrueRetentionGraph(data, history: model.history), mode: controls.trueRetentionMode)
        case .hours:
            if let hours = HoursGraph(data, range: controls.hoursRange) { HoursChart(graph: hours) } else { NoData() }
        case .buttons:
            if let buttons = ButtonsGraph(data, range: controls.buttonsRange) {
                ButtonsChart(graph: buttons)
            } else {
                NoData()
            }
        case .added:
            histogram(AddedGraph.histogram(data, range: controls.addedRange))
        }
    }

    @ViewBuilder private func histogram(_ result: (Histogram?, [TableRow])) -> some View {
        if let histogram = result.0 {
            HistogramChart(histogram: histogram, search: search)
        } else {
            NoData()
        }
        GraphTable(rows: result.1)
    }
}

/// A segmented switch between a graph's ranges.
private struct RangePicker<Choice: Hashable & Identifiable & TitledChoice>: View {
    @Binding var selection: Choice
    let choices: [Choice]

    var body: some View {
        Picker(selection: $selection) {
            ForEach(choices) { Text($0.title).tag($0) }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

protocol TitledChoice {
    var title: String { get }
}

extension GraphRange: TitledChoice {}
extension IntervalRange: TitledChoice {}
extension PercentageRange: TitledChoice {}
extension TrueRetentionGraph.Mode: TitledChoice {}

/// Desktop's empty graph.
private struct NoData: View {
    var body: some View {
        Text(Tr.statisticsNoData)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: Theme.Statistics.chartHeight)
    }
}
