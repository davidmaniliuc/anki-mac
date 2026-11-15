import AppKit
import Charts
import SwiftUI

/// Desktop's graphs, in its order. Each case is one card of the page: its
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

/// The page's content: a header naming what the graphs cover, with the
/// controls that choose it, then the graphs in one to three columns.
struct StatisticsView: View {
    @Bindable var model: StatisticsModel
    @Environment(CollectionModel.self) private var collection
    @Environment(\.compact) private var compact
    @State private var width: CGFloat = 0
    @FocusState private var searchFocused: Bool

    private var margin: CGFloat { compact ? Theme.Layout.compactPageMargin : Theme.Layout.pageMargin }

    /// One to three, as desktop's grid at the page's width.
    private var columns: Int {
        let gap = Theme.Statistics.columnGap
        let room = width - 2 * margin + gap
        return max(1, min(Theme.Statistics.maxColumns, Int(room / (Theme.Statistics.graphMinWidth + gap))))
    }

    var body: some View {
        ScrollView {
            // Lazy, so only the graphs in sight are drawn.
            LazyVStack(alignment: .leading, spacing: Theme.Statistics.rowGap) {
                header
                if let data = model.data {
                    let graphs = StatisticsGraph.allCases.filter { $0.applies(fsrs: data.fsrs) }
                    let rows = stride(from: 0, to: graphs.count, by: columns).map {
                        graphs[$0..<min($0 + columns, graphs.count)]
                    }
                    ForEach(rows, id: \.first) { row in
                        HStack(alignment: .top, spacing: Theme.Statistics.columnGap) {
                            ForEach(row) { GraphSection(graph: $0, model: model, data: data, browse: browse) }
                            // A short last row keeps the columns' widths.
                            ForEach(row.count..<columns, id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, compact ? 0 : Theme.Spacing.small)
            .padding(.bottom, Theme.Layout.pageBottomPadding)
        }
        .pageScrolling()
        .pageActions { QuickFindButton() }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .overlay {
            if model.data == nil {
                if let error = model.errorMessage {
                    ContentUnavailableView(Tr.statisticsTitle, systemImage: "chart.bar", description: Text(error))
                } else {
                    ProgressView()
                }
            }
        }
    }

    /// The title, with the controls at its trailing edge, or under it when
    /// the page is too narrow for both; the search box under them.
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            // The eyebrow sits apart, so a long deck path doesn't push the controls under the title.
            VStack(alignment: .leading, spacing: 6) {
                // The sidebar's decks open their overview, so the deck is picked here, from its own name.
                if model.scope == .deck {
                    deckMenu
                } else {
                    // Always laid out, so the title stays put as the scope changes,
                    // level with Today's under its greeting.
                    Eyebrow(coverage.isEmpty ? " " : coverage)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.large) {
                        title
                        Spacer(minLength: Theme.Spacing.small)
                        controls
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                        title
                        controls.outdented()
                    }
                }
            }
            if model.scope == .search {
                TextField(Tr.statisticsRangeSearch, text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: Theme.Statistics.searchWidth)
                    .focused($searchFocused)
                    .onSubmit { model.submitSearch() }
                    .onAppear { searchFocused = true }
            }
        }
    }

    private var title: some View {
        PageTitle(eyebrow: "", title: Tr.statisticsTitle) {
            Image(systemName: "chart.bar.fill")
                .font(Theme.Statistics.titleSymbol)
                .foregroundStyle(Theme.Palette.violet)
                .accessibilityHidden(true)
        }
    }

    /// What the graphs cover, over the title: the deck's path or the
    /// search. The collection has none, as its segment already says it.
    private var coverage: String {
        switch model.scope {
        case .deck: model.deckName?.replacingOccurrences(of: "::", with: " › ") ?? ""
        case .collection: ""
        case .search: model.search
        }
    }

    /// The deck's path as the eyebrow, which opens the deck tree as nested
    /// menus, each parent first in its own.
    private var deckMenu: some View {
        Menu {
            DeckMenuItems(decks: collection.decks, current: model.deckID, pick: model.show(deck:))
        } label: {
            HStack(spacing: Theme.Spacing.xSmall) {
                Eyebrow(coverage.isEmpty ? Tr.statisticsRangeDeck : coverage)
                Image(systemName: "chevron.down")
                    .font(Theme.Fonts.menuChevron)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .modifier(MenuHover(shape: RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // The hover wash reaches past the eyebrow, which stays in line with the title.
        .padding(.leading, -Theme.Layout.menuPadding)
        .accessibilityLabel(sentenceCase(Tr.statisticsRangeDeck))
        .accessibilityValue(coverage)
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.medium) {
            QuietSegments(selection: $model.scope, choices: [.deck, .collection, .search]) {
                switch $0 {
                case .deck: sentenceCase(Tr.statisticsRangeDeck)
                case .collection: sentenceCase(Tr.statisticsRangeCollection)
                case .search: sentenceCase(Tr.statisticsRangeSearch)
                }
            }
            Menu {
                Picker(Tr.statisticsTitle, selection: $model.history) {
                    Text(historyTitle(.year)).tag(RevlogHistory.year)
                    Text(historyTitle(.all)).tag(RevlogHistory.all)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: Theme.Spacing.xSmall) {
                    Text(historyTitle(model.history))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Theme.Fonts.menuChevron)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .font(Theme.Fonts.chip)
                .foregroundStyle(Theme.Palette.text)
                .frame(height: Theme.Layout.controlHeight)
                .modifier(MenuHover(shape: Capsule(), fill: Theme.Palette.raised))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            // The spinner takes Save PDF's place while the graphs load, so the
            // controls reach the page's edge and nothing moves as it comes and goes.
            let loading = model.loading && model.data != nil
            IconButton("square.and.arrow.down", help: Tr.statisticsSavePdf, action: savePDF)
                .disabled(model.data == nil || loading)
                .opacity(loading ? 0 : 1)
                .overlay {
                    if loading { ProgressView().controlSize(.small) }
                }
        }
    }

    private func historyTitle(_ history: RevlogHistory) -> String {
        sentenceCase(history == .year ? Tr.statisticsRange1YearHistory : Tr.statisticsRangeAllHistory)
    }

    private func browse(_ search: String) {
        BrowserWindowController.show(collection: collection)
        BrowserWindowController.current?.model.search(text: search)
    }

    /// Saves every graph, one per row, on a single tall page, as desktop's
    /// Save PDF button.
    private func savePDF() {
        guard let window = collection.mainWindow, let data = model.data else { return }
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd@HH-mm-ss"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "anki-\(Tr.statisticsStats)-\(format.string(from: .now)).pdf"
        let content = StatisticsPrintView(model: model, data: data)
            .environment(\.colorScheme, .light)
            .background(Theme.Palette.canvas)
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let renderer = ImageRenderer(content: content)
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
                context.closePDF()
            }
        }
    }
}

/// Upstream's range names are lower case ("deck", "last 12 months"); as
/// control labels they take a capital, as Mac controls do.
private func sentenceCase(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
}

/// `text` with its numbers ("22", "2,1", "31,82%") set in `font`, as the
/// Rounded Numbers Rule asks of upstream's sentences.
private func roundedFigures(_ text: String, _ font: Font) -> AttributedString {
    var result = AttributedString(text)
    for match in text.matches(of: /\d[\d.,:%]*/) {
        let digits = text[match.range].trimmingCharacters(in: CharacterSet(charactersIn: ".,:"))
        guard let lower = AttributedString.Index(match.range.lowerBound, within: result),
              let upper = AttributedString.Index(text.index(match.range.lowerBound, offsetBy: digits.count), within: result)
        else { continue }
        result[lower..<upper].font = font
    }
    return result
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
        VStack(spacing: Theme.Statistics.rowGap) {
            ForEach(StatisticsGraph.allCases.filter { $0.applies(fsrs: data.fsrs) }) { graph in
                GraphSection(graph: graph, model: model, data: data, browse: { _ in })
            }
        }
        .padding(Theme.Spacing.xLarge)
        .frame(width: Theme.Statistics.pdfWidth)
        .environment(\.statisticsPrinting, true)
    }
}

// MARK: Sections

/// One graph, unboxed on the canvas under a hairline: its title, subtitle,
/// switches, chart and table, or desktop's "no data" when the range has
/// nothing to show.
private struct GraphSection: View {
    let graph: StatisticsGraph
    @Bindable var model: StatisticsModel
    let data: GraphsResponse
    let browse: (String) -> Void
    @Environment(\.statisticsPrinting) private var printing

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                Text(graph.title)
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = graph.subtitle(model.controls) {
                    Text(subtitle)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !printing { controls }
            content.environment(\.graphTitle, graph.title)
        }
        .padding(.top, Theme.Statistics.sectionPadding)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func search(_ query: String) {
        browse(model.search.isEmpty ? query : "\(model.search) \(query)")
    }

// MARK: Switches

    /// The switches on one line, or stacked when the column is too narrow.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.medium) { switches }
            VStack(alignment: .leading, spacing: Theme.Spacing.small) { switches }
        }
        .outdented(switchesStartQuiet)
    }

    /// Whether the switches start with a quiet control (segments or the
    /// calendar's arrows) rather than a checkbox, whose ink starts at its edge.
    private var switchesStartQuiet: Bool {
        switch graph {
        case .futureDue: !data.futureDue.haveBacklog
        case .reviews, .cardCounts, .today, .ease: false
        default: true
        }
    }

    @ViewBuilder private var switches: some View {
        let history = model.history
        switch graph {
        case .futureDue:
            Group {
                if data.futureDue.haveBacklog {
                    Toggle(Tr.statisticsBacklogCheckbox, isOn: $model.preferences.futureDueShowBacklog)
                }
                RangePicker(selection: $model.controls.futureDueRange, choices: GraphRange.choices(.all))
            }
        case .calendar:
            let years = CalendarGraph.years(history, current: Calendar.current.component(.year, from: .now))
            HStack(spacing: Theme.Spacing.xSmall) {
                // Named by the year they go to: upstream has no words for them.
                IconButton("chevron.left", help: String(model.controls.calendarYear - 1)) {
                    model.controls.calendarYear -= 1
                }
                    .disabled(model.controls.calendarYear <= years.lowerBound)
                Text(String(model.controls.calendarYear))
                    .font(Theme.Statistics.figures)
                    .foregroundStyle(Theme.Palette.text)
                    .accessibilityAddTraits(.updatesFrequently)
                IconButton("chevron.right", help: String(model.controls.calendarYear + 1)) {
                    model.controls.calendarYear += 1
                }
                    .disabled(model.controls.calendarYear >= years.upperBound)
            }
        case .reviews:
            Group {
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
            // Desktop's sentences, the first (what was studied) leading.
            let lines = TodayStats.lines(data)
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(roundedFigures(line, index == 0 ? Theme.Statistics.todayLeadFigures : Theme.Statistics.todayFigures))
                        .font(index == 0 ? Theme.Statistics.todayLead : Theme.Fonts.body)
                        .foregroundStyle(index == 0 ? Theme.Palette.text : Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// A switch between a graph's ranges.
private struct RangePicker<Choice: Hashable & TitledChoice>: View {
    @Binding var selection: Choice
    let choices: [Choice]

    var body: some View {
        QuietSegments(selection: $selection, choices: choices) { sentenceCase($0.title) }
    }
}

extension View {
    /// For a row that starts with quiet controls: their first word lines up
    /// with the text above, and the chosen one's wash reaches past it, as a
    /// list row's does.
    fileprivate func outdented(_ enabled: Bool = true) -> some View {
        padding(.leading, enabled ? -Theme.Layout.segmentPadding : 0)
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
            .font(Theme.Fonts.lead)
            .foregroundStyle(Theme.Palette.tertiary)
            .frame(maxWidth: .infinity, minHeight: Theme.Statistics.chartHeight)
    }
}
