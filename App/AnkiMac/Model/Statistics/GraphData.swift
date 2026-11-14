import AnkiKit
import Foundation
import SwiftUI

typealias GraphsResponse = Anki_Stats_GraphsResponse

/// The period a graph covers, picked under each graph.
enum GraphRange: Int, CaseIterable, Identifiable {
    case month, threeMonths, year, allTime

    var id: Self { self }

    var title: String {
        switch self {
        case .month: timeSpan(TimeUnit.months.seconds)
        case .threeMonths: timeSpan(3 * TimeUnit.months.seconds)
        case .year: timeSpan(TimeUnit.years.seconds)
        case .allTime: Tr.statisticsRangeAllTime
        }
    }

    /// The ranges offered when the backend was asked for `history`.
    static func choices(_ history: RevlogHistory) -> [GraphRange] {
        history == .all ? allCases : [.month, .threeMonths, .year]
    }

    /// Desktop's graphs that follow the page's history switch jump to all
    /// time with it, and back to a year when it is turned off.
    func following(_ history: RevlogHistory) -> GraphRange {
        if history == .all { return .allTime }
        return self == .allTime ? .year : self
    }
}

/// How much review history the backend gathers: the page's range switch.
enum RevlogHistory: Hashable {
    case year, all

    var days: UInt32 { self == .year ? 365 : 0 }
}

struct TableRow: Hashable {
    let label: String
    let value: String
}

/// A histogram bar's points: a key of the backend's map and its count.
typealias Point = (x: Double, count: Double)
typealias PointBin = GraphScale.Bin<Point>

extension GraphScale.Bin where Point == (x: Double, count: Double) {
    var value: Double { points.reduce(0) { $0 + $1.count } }
}

/// Everything a histogram graph draws: the bars, an optional running total,
/// and what hovering and clicking a bar show and search.
struct Histogram {
    var bins: [PointBin]
    var domain: (Double, Double)
    var total: Double
    var showArea: Bool
    var colour: (Double) -> Color
    var hoverText: (_ bin: PointBin, _ cumulative: Double, _ percent: Double) -> String
    var search: (PointBin) -> String
    var xTickFormat: (Double) -> String = { localizedNumber($0) }

    /// The running total after each bar.
    var cumulative: [Double] {
        var sum = 0.0
        return bins.map { sum += $0.value; return sum }
    }
}

// MARK: Formatting, as tslib/time.ts and tslib/i18n

enum TimeUnit: Int, Comparable {
    case seconds, minutes, hours, days, months, years

    var seconds: Double {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        case .days: 86_400
        case .months: 365 * 86_400 / 12
        case .years: 365 * 86_400
        }
    }

    var name: String {
        switch self {
        case .seconds: "seconds"
        case .minutes: "minutes"
        case .hours: "hours"
        case .days: "days"
        case .months: "months"
        case .years: "years"
        }
    }

    static func natural(_ seconds: Double) -> TimeUnit {
        let secs = abs(seconds)
        if secs < TimeUnit.minutes.seconds { return .seconds }
        if secs < TimeUnit.hours.seconds { return .minutes }
        if secs < TimeUnit.days.seconds { return .hours }
        if secs < TimeUnit.months.seconds { return .days }
        if secs < TimeUnit.years.seconds { return .months }
        return .years
    }

    static func < (a: TimeUnit, b: TimeUnit) -> Bool { a.rawValue < b.rawValue }
}

/// A number rounded to `precision` decimals, as desktop's localizedNumber.
func localizedNumber(_ value: Double, _ precision: Int = 2) -> String {
    let scale = pow(10, Double(precision))
    let rounded = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    return rounded.formatted(.number.precision(.fractionLength(0...max(precision, 0))))
}

/// "3 months", or "3mo" when `short`.
func timeSpan(_ seconds: Double, short: Bool = false, precise: Bool = true, maxUnit: TimeUnit = .years) -> String {
    let unit = min(TimeUnit.natural(seconds), maxUnit)
    var amount = seconds / unit.seconds
    if !precise, unit < .months { amount = amount.rounded(.toNearestOrAwayFromZero) }
    if short {
        let text = Tr.number(amount)
        switch unit {
        case .seconds: return Tr.statisticsElapsedTimeSeconds(amount: text)
        case .minutes: return Tr.statisticsElapsedTimeMinutes(amount: text)
        case .hours: return Tr.statisticsElapsedTimeHours(amount: text)
        case .days: return Tr.statisticsElapsedTimeDays(amount: text)
        case .months: return Tr.statisticsElapsedTimeMonths(amount: text)
        case .years: return Tr.statisticsElapsedTimeYears(amount: text)
        }
    }
    switch unit {
    case .seconds: return Tr.schedulingTimeSpanSeconds(amount: amount)
    case .minutes: return Tr.schedulingTimeSpanMinutes(amount: amount)
    case .hours: return Tr.schedulingTimeSpanHours(amount: amount)
    case .days: return Tr.schedulingTimeSpanDays(amount: amount)
    case .months: return Tr.schedulingTimeSpanMonths(amount: amount)
    case .years: return Tr.schedulingTimeSpanYears(amount: amount)
    }
}

/// "Tomorrow", "In 3-6 days", "5 days ago"...
func dayLabel(_ start: Double, _ end: Double) -> String {
    let larger = max(abs(start), abs(end)), smaller = min(abs(start), abs(end))
    if larger - smaller <= 1 {
        return start >= 0 ? Tr.statisticsInDaysSingle(days: start) : Tr.statisticsDaysAgoSingle(days: -start)
    }
    if start >= 0 {
        return Tr.statisticsInDaysRange(daysStart: Tr.number(start), daysEnd: Tr.number(end - 1))
    }
    return Tr.statisticsDaysAgoRange(daysStart: Tr.number(abs(end - 1)), daysEnd: Tr.number(-start))
}

/// A number as JavaScript prints it in a template string: no grouping.
private func plain(_ value: Double) -> String {
    value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
}

private func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }

/// The points of a backend map, by key.
private func points<K: BinaryInteger>(_ map: [K: UInt32]) -> [Point] {
    map.map { (Double($0.key), Double($0.value)) }.sorted { $0.x < $1.x }
}

// MARK: Today

enum TodayStats {
    static func lines(_ data: GraphsResponse) -> [String] {
        let today = data.today
        guard today.answerCount > 0 else { return [Tr.statisticsTodayNoCards] }
        let answers = Double(today.answerCount)
        let secs = Double(today.answerMillis) / 1000
        let unit = min(TimeUnit.natural(secs), .minutes)
        let studied = Tr.statisticsStudiedToday(
            cards: Int(today.answerCount), unit: unit.name, amount: secs / unit.seconds,
            secsPerCard: Tr.number(secs / answers))
        let again = Double(today.answerCount - today.correctCount)
        let againText = "\(Tr.statisticsTodayAgainCount) \(Tr.number(again)) (\(localizedNumber(again / answers * 100))%)"
        let types = Tr.statisticsTodayTypeCounts(
            learnCount: Tr.number(Int(today.learnCount)), reviewCount: Tr.number(Int(today.reviewCount)),
            relearnCount: Tr.number(Int(today.relearnCount)), filteredCount: Tr.number(Int(today.earlyReviewCount)))
        let mature = today.matureCount > 0
            ? Tr.statisticsTodayCorrectMature(
                correct: Tr.number(Int(today.matureCorrect)), total: Tr.number(Int(today.matureCount)),
                percent: Tr.number(Double(today.matureCorrect) / Double(today.matureCount) * 100))
            : Tr.statisticsTodayNoMatureCards
        return [studied, againText, types, mature]
    }
}

// MARK: Future Due

enum FutureDueGraph {
    static func histogram(_ data: GraphsResponse, range: GraphRange, backlog: Bool) -> (Histogram?, [TableRow]) {
        let due = data.futureDue
        let all = points(due.futureDue)
        let shown = backlog ? all : all.filter { $0.x >= 0 }
        guard let first = shown.first, let last = shown.last else { return (nil, []) }
        let xMin = backlog ? first.x : 0
        let xMax: Double = switch range {
        case .month: 31
        case .threeMonths: 90
        case .year: 365
        case .allTime: last.x
        }
        let desiredBars = min(70, xMax - xMin)
        let thresholds = GraphScale.ticks(xMin, xMax, count: desiredBars)
        let bins = GraphScale.bin(shown, value: \.x, domain: (xMin, xMax), thresholds: thresholds)
        guard bins.contains(where: { !$0.points.isEmpty }) else { return (nil, []) }
        let total = bins.reduce(0) { $0 + $1.value }
        let periodDays = xMax - xMin
        let histogram = Histogram(
            bins: bins, domain: (xMin, xMax), total: total, showArea: true,
            colour: { Theme.Statistics.shade(Theme.Colors.reviewCards, GraphScale.linear($0, domain: (xMin, xMax), range: (1, 0.4))) },
            hoverText: { bin, cumulative, _ in
                let days = dayLabel(bin.x0, bin.x1 == xMax ? bin.x1 + 1 : bin.x1)
                return "\(days):\n\(Tr.statisticsCardsDue(cards: bin.value))\n"
                    + "\(Tr.statisticsRunningTotal): \(localizedNumber(cumulative))"
            },
            search: { bin in
                let start = Int(bin.x0), end = Int(bin.x1 == xMax ? bin.x1 : bin.x1 - 1)
                return start == end ? "\"prop:due=\(start)\"" : "\"prop:due>=\(start)\" AND \"prop:due<=\(end)\""
            })
        let table = [
            TableRow(label: Tr.statisticsTotal, value: Tr.statisticsReviews(reviews: total)),
            TableRow(
                label: Tr.statisticsAverage,
                value: Tr.statisticsReviewsPerDay(count: periodDays > 0 ? jsRound(total / periodDays) : 0)),
            TableRow(
                label: Tr.statisticsDueTomorrow,
                value: Tr.statisticsReviews(reviews: Int(due.futureDue[1] ?? 0))),
            TableRow(label: Tr.statisticsDailyLoad, value: Tr.statisticsReviewsPerDay(count: Int(due.dailyLoad))),
        ]
        return (histogram, table)
    }
}

// MARK: Reviews

/// The five kinds of review stacked in each Reviews bar, bottom first.
enum ReviewKind: Int, CaseIterable, Identifiable {
    case mature, young, relearn, learn, filtered

    var id: Self { self }

    var label: String {
        switch self {
        case .mature: Tr.statisticsCountsMatureCards
        case .young: Tr.statisticsCountsYoungCards
        case .relearn: Tr.statisticsCountsRelearningCards
        case .learn: Tr.statisticsCountsLearningCards
        case .filtered: Tr.statisticsCountsFilteredCards
        }
    }

    /// The queue colours: review green for mature and young, learning
    /// coral for relearning and learning.
    var colour: Color {
        switch self {
        case .mature: Theme.Statistics.mature
        case .young: Theme.Statistics.young
        case .relearn: Theme.Statistics.relearning
        case .learn: Theme.Statistics.learning
        case .filtered: Theme.Statistics.filtered
        }
    }

    func value(_ reviews: GraphsResponse.ReviewCountsAndTimes.Reviews) -> Double {
        switch self {
        case .mature: Double(reviews.mature)
        case .young: Double(reviews.young)
        case .relearn: Double(reviews.relearn)
        case .learn: Double(reviews.learn)
        case .filtered: Double(reviews.filtered)
        }
    }
}

struct ReviewsGraph {
    struct Bar: Identifiable {
        let id: Int
        let x0: Double
        let x1: Double
        /// By `ReviewKind` raw value.
        let totals: [Double]
        var sum: Double { totals.reduce(0, +) }
        /// The top of `kind`'s segment.
        func top(_ kind: ReviewKind) -> Double { totals[...kind.rawValue].reduce(0, +) }
    }

    let bars: [Bar]
    let domain: (Double, Double)
    let showTime: Bool
    let table: [TableRow]
    /// The oldest day asked for, before the first bar was widened.
    let originalXMin: Double

    var cumulative: [Double] {
        var sum = 0.0
        return bars.map { sum += $0.sum; return sum }
    }

    func valueLabel(_ value: Double) -> String {
        showTime ? timeSpan(value / 1000, short: false, precise: true, maxUnit: .hours) : Tr.statisticsReviews(reviews: value)
    }

    func tickLabel(_ value: Double) -> String {
        if showTime { return timeSpan(value / 1000, short: true, precise: true, maxUnit: .hours) }
        return value.rounded() == value ? localizedNumber(value) : ""
    }

    func dayRange(_ bar: Bar) -> String {
        let start = bar.id == 0 ? originalXMin : floor(bar.x0)
        return dayLabel(start, bar.x1 == 0 ? 1 : bar.x1)
    }

    init?(_ data: GraphsResponse, range: GraphRange, showTime: Bool) {
        let counts = data.reviews.count, times = data.reviews.time
        let xMax = 1.0
        var xMin: Double = switch range {
        case .month: -30
        case .threeMonths: -89
        case .year: -364
        case .allTime: Double(counts.keys.min() ?? 0)
        }
        let desiredBars = min(70, abs(xMin))
        let originalXMin = xMin
        var thresholds = GraphScale.ticks(xMin, xMax, count: desiredBars)
        // Widen the oldest bin of an open range to the others' width.
        if range == .allTime, thresholds.count >= 2 {
            let spacing = thresholds[1] - thresholds[0]
            let partial = thresholds[0] - xMin
            if spacing > 0, partial > 0, partial < spacing {
                xMin = thresholds[0] - spacing
                thresholds = GraphScale.ticks(xMin, xMax, count: desiredBars)
            }
        }
        // Over a year or more, bins end on day 0 rather than day 1.
        if range == .year || range == .allTime {
            thresholds = Array(Set(thresholds.map { min($0 + 1, 1) })).sorted()
        }
        let source = (showTime ? times : counts).map { (x: Double($0.key), reviews: $0.value) }
        let bins = GraphScale.bin(source, value: \.x, domain: (xMin, xMax), thresholds: thresholds)
        let studiedDays = bins.reduce(0) { $0 + $1.points.count }
        guard studiedDays > 0 else { return nil }
        bars = bins.enumerated().map { index, bin in
            Bar(id: index, x0: bin.x0, x1: bin.x1, totals: ReviewKind.allCases.map { kind in
                bin.points.reduce(0) { $0 + kind.value($1.reviews) }
            })
        }
        domain = (xMin, xMax)
        self.showTime = showTime
        self.originalXMin = originalXMin

        let total = bars.reduce(0) { $0 + $1.sum }
        let periodDays = -originalXMin + 1
        let studiedPercent = Double(studiedDays) / periodDays * 100
        let periodAverage = total / periodDays
        let studiedAverage = total / Double(studiedDays)
        let percent: String = if studiedPercent < 99.5 {
            localizedNumber(studiedPercent)
        } else if studiedPercent < 99.95 {
            localizedNumber(studiedPercent, 1)
        } else if studiedPercent < 100 {
            localizedNumber(studiedPercent, 2)
        } else {
            "100"
        }
        var table = [
            TableRow(
                label: Tr.statisticsDaysStudied,
                value: Tr.statisticsAmountOfTotalWithPercentage(
                    amount: Tr.number(studiedDays), total: Tr.number(periodDays), percent: percent)),
        ]
        if showTime {
            table.append(TableRow(label: Tr.statisticsTotal, value: timeSpan(total / 1000, maxUnit: .hours)))
            table.append(TableRow(
                label: Tr.statisticsAverageOverPeriod,
                value: Tr.statisticsMinutesPerDay(count: jsRound(periodAverage / 1000 / 60))))
            if studiedPercent < 100 {
                table.append(TableRow(
                    label: Tr.statisticsAverageForDaysStudied,
                    value: Tr.statisticsMinutesPerDay(count: jsRound(studiedAverage / 1000 / 60))))
            }
            let reviews = counts.filter { Double($0.key) >= xMin && Double($0.key) <= xMax }.values
                .reduce(0.0) { sum, day in ReviewKind.allCases.reduce(sum) { $0 + $1.value(day) } }
            let seconds = total / 1000
            table.append(TableRow(
                label: Tr.statisticsAverageAnswerTimeLabel,
                value: Tr.statisticsAverageAnswerTime(
                    averageSeconds: Tr.number(seconds / reviews), cardsPerMinute: Tr.number(reviews * 60 / seconds))))
        } else {
            table.append(TableRow(label: Tr.statisticsTotal, value: Tr.statisticsReviews(reviews: total)))
            table.append(TableRow(
                label: Tr.statisticsAverageOverPeriod, value: Tr.statisticsReviewsPerDay(count: jsRound(periodAverage))))
            if studiedPercent < 100 {
                table.append(TableRow(
                    label: Tr.statisticsAverageForDaysStudied,
                    value: Tr.statisticsReviewsPerDay(count: jsRound(studiedAverage))))
            }
        }
        self.table = table
    }
}

// MARK: Calendar

struct CalendarGraph {
    struct Day: Identifiable {
        var id: Int { yearDay }
        let yearDay: Int
        /// Relative to today, for the search; only meaningful when count > 0.
        let day: Int
        let count: Int
        let week: Int
        let weekday: Int
        let date: Date
    }

    typealias Weekday = Anki_Stats_GraphPreferences.Weekday

    let days: [Day]
    let maxCount: Int
    /// Weekday numbers (0 is Sunday) from the top row down.
    let weekdays: [Int]

    init?(_ data: GraphsResponse, year: Int, firstWeekday: Weekday, history: RevlogHistory, now: Date = .now) {
        var calendar = Calendar.current
        calendar.firstWeekday = firstWeekday.rawValue + 1
        weekdays = (0..<7).map { (firstWeekday.rawValue + $0) % 7 }

        func place(_ date: Date, day: Int, count: Int) -> Day {
            let yearStart = calendar.dateInterval(of: .year, for: date)!.start
            let weekOfStart = calendar.dateInterval(of: .weekOfYear, for: yearStart)!.start
            let weekOfDate = calendar.dateInterval(of: .weekOfYear, for: date)!.start
            let week = calendar.dateComponents([.day], from: weekOfStart, to: weekOfDate).day! / 7
            let weekday = calendar.dateComponents(
                [.day], from: weekOfDate, to: calendar.startOfDay(for: date)).day!
            let yearDay = calendar.dateComponents([.day], from: yearStart, to: calendar.startOfDay(for: date)).day!
            return Day(yearDay: yearDay, day: day, count: count, week: week, weekday: weekday, date: date)
        }

        var byYearDay: [Int: Day] = [:]
        var maxCount = 0
        for (day, reviews) in data.reviews.count {
            let count = Int(ReviewKind.allCases.reduce(0) { $0 + $1.value(reviews) })
            maxCount = max(maxCount, count)
            // An Anki day may roll over after midnight.
            guard let shifted = calendar.date(byAdding: .day, value: Int(day), to: now),
                  let date = calendar.date(byAdding: .hour, value: -Int(data.rolloverHour), to: shifted),
                  calendar.component(.year, from: date) == year
            else { continue }
            let placed = place(date, day: Int(day), count: count)
            byYearDay[placed.yearDay] = placed
        }
        guard maxCount > 0 else { return nil }
        let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
        for offset in 0..<365 {
            let date = calendar.date(byAdding: .day, value: offset, to: yearStart)!
            if date > now || (history == .year && date < yearAgo) { continue }
            let placed = place(date, day: offset, count: 0)
            if byYearDay[placed.yearDay] == nil { byYearDay[placed.yearDay] = placed }
        }
        days = byYearDay.values.sorted { $0.yearDay < $1.yearDay }
        self.maxCount = maxCount
    }

    func colour(_ count: Int) -> Color {
        guard count > 0 else { return Theme.Statistics.calendarEmpty }
        let t = (Double(count) / Double(maxCount)).squareRoot()
        return Theme.Statistics.shade(Theme.Colors.newCards, 0.25 + 0.75 * t)
    }

    /// The years the arrows can reach.
    static func years(_ history: RevlogHistory, current: Int) -> ClosedRange<Int> {
        (history == .year ? current - 1 : 2000)...current
    }
}

// MARK: Card Counts

struct CardCountsGraph {
    struct Row: Identifiable {
        var id: String { label }
        let label: String
        let count: Int
        let shown: Bool
        let search: String
        let colour: Color
    }

    let rows: [Row]
    let total: Int

    static let colours: [Color] = [
        Theme.Statistics.newCards, Theme.Statistics.learning, Theme.Statistics.relearning, Theme.Statistics.young,
        Theme.Statistics.mature, Theme.Statistics.suspended, Theme.Statistics.buried,
    ]

    init(_ data: GraphsResponse, separateInactive: Bool) {
        let counts = separateInactive ? data.cardCounts.excludingInactive : data.cardCounts.includingInactive
        let extra = separateInactive ? "AND -(\"is:buried\" OR \"is:suspended\")" : ""
        let entries: [(String, UInt32, Bool, String)] = [
            (Tr.statisticsCountsNewCards, counts.newCards, true, "\"is:new\"\(extra)"),
            (Tr.statisticsCountsLearningCards, counts.learn, true, "(-\"is:review\" AND \"is:learn\")\(extra)"),
            (Tr.statisticsCountsRelearningCards, counts.relearn, true, "(\"is:review\" AND \"is:learn\")\(extra)"),
            (Tr.statisticsCountsYoungCards, counts.young, true,
             "(\"is:review\" AND -\"is:learn\") AND \"prop:ivl<21\"\(extra)"),
            (Tr.statisticsCountsMatureCards, counts.mature, true,
             "(\"is:review\" -\"is:learn\") AND \"prop:ivl>=21\"\(extra)"),
            (Tr.statisticsCountsSuspendedCards, counts.suspended, separateInactive, "\"is:suspended\""),
            (Tr.statisticsCountsBuriedCards, counts.buried, separateInactive, "\"is:buried\""),
        ]
        rows = entries.enumerated().map { index, entry in
            Row(label: entry.0, count: Int(entry.1), shown: entry.2, search: entry.3, colour: Self.colours[index])
        }
        total = rows.reduce(0) { $0 + $1.count }
    }

    func percent(_ row: Row) -> String {
        "\(localizedNumber(Double(row.count) / Double(max(1, total)) * 100, 2))%"
    }
}

// MARK: Intervals and Stability

enum IntervalRange: Int, CaseIterable, Identifiable {
    case month, percentile50, percentile95, all

    var id: Self { self }

    var title: String {
        switch self {
        case .month: timeSpan(TimeUnit.months.seconds)
        case .percentile50: "50%"
        case .percentile95: "95%"
        case .all: Tr.statisticsRangeAllTime
        }
    }
}

enum IntervalsGraph {
    /// Review Intervals, or Card Stability when `fsrs`.
    static func histogram(_ map: [UInt32: UInt32], range: IntervalRange, fsrs: Bool) -> (Histogram?, [TableRow]) {
        let runs = points(map).map { (value: $0.x, count: Int($0.count)) }.filter { $0.count > 0 }
        guard let last = runs.last else { return (nil, []) }
        var xMax = last.value
        var niceNecessary = false
        switch range {
        case .month:
            xMax = min(xMax, 30)
        case .percentile50:
            xMax = GraphScale.quantile(sortedRuns: runs, 0.5)!
            niceNecessary = true
        case .percentile95:
            xMax = GraphScale.quantile(sortedRuns: runs, 0.95)!
            niceNecessary = true
        case .all:
            niceNecessary = true
        }
        let xMin = 0.0
        xMax += 1
        // Intervals start at a day, stabilities at zero.
        let increment: (Double) -> Double = fsrs ? { $0 } : { $0 + 1 }
        let desiredBars = min(70, xMax - xMin)
        let prescale = niceNecessary ? GraphScale.nice((xMin, xMax)) : (xMin, xMax)
        let domain = (increment(prescale.0), increment(prescale.1))
        let ticks = GraphScale.ticks(domain.0, domain.1, count: desiredBars)
        let thresholds = ticks.enumerated().flatMap { index, x in
            index == ticks.count - 1 ? [x - (ticks[0] - 1), x + 1] : [x - (ticks[0] - 1)]
        }
        let bins = GraphScale.bin(
            runs.map { (x: $0.value, count: Double($0.count)) }, value: \.x, domain: domain, thresholds: thresholds)
        let total = bins.reduce(0) { $0 + $1.value }
        guard total > 0 else { return (nil, []) }
        let histogram = Histogram(
            bins: bins, domain: domain, total: total, showArea: true,
            colour: { Theme.Statistics.shade(Theme.Colors.newCards, GraphScale.linear($0, domain: (xMax, xMin), range: (1, 0.4))) },
            hoverText: { bin, _, percent in
                "\(intervalLabel(bin.x0, bin.x1, cards: bin.value, fsrs: fsrs))\n"
                    + "\(Tr.statisticsRunningTotal): \u{200e}\(localizedNumber(percent, 1))%"
            },
            search: { bin in
                var start = bin.x0
                let end = bin.x1 - 1
                if fsrs {
                    if start == 0 { start = 0.5 }
                    return "\"prop:s>=\(plain(start - 0.5))\" \"prop:s<\(plain(end + 0.5))\""
                }
                return start == end
                    ? "\"prop:ivl=\(plain(start))\""
                    : "\"prop:ivl>=\(plain(start))\" \"prop:ivl<=\(plain(end))\""
            })
        let median = (GraphScale.quantile(sortedRuns: runs, 0.5) ?? 0).rounded(.toNearestOrAwayFromZero)
        let table = [
            TableRow(
                label: fsrs ? Tr.statisticsMedianStability : Tr.statisticsMedianInterval,
                value: timeSpan(median * 86_400)),
        ]
        return (histogram, table)
    }

    static func intervalLabel(_ start: Double, _ end: Double, cards: Double, fsrs: Bool) -> String {
        if end - start <= 1 {
            let day = Tr.number(start)
            return fsrs
                ? Tr.statisticsStabilityDaySingle(cards: cards, day: day)
                : Tr.statisticsIntervalsDaySingle(cards: cards, day: day)
        }
        let from = Tr.number(start), to = Tr.number(end - 1)
        return fsrs
            ? Tr.statisticsStabilityDayRange(cards: cards, daysStart: from, daysEnd: to)
            : Tr.statisticsIntervalsDayRange(cards: cards, daysStart: from, daysEnd: to)
    }
}

// MARK: Ease, Difficulty and Retrievability

/// The 50% / 95% / 100% / all switch of the FSRS percentage graphs.
enum PercentageRange: Int, CaseIterable, Identifiable {
    case percentile50, percentile95, percentile100, all

    var id: Self { self }

    var title: String {
        switch self {
        case .percentile50: "50%"
        case .percentile95: "95%"
        case .percentile100: "100%"
        case .all: Tr.statisticsRangeAllTime
        }
    }

    /// Halved, since the range trims both ends.
    var quantile: Double? {
        switch self {
        case .percentile100: 1
        case .percentile95: 0.975
        case .percentile50: 0.75
        case .all: nil
        }
    }
}

enum PercentageGraphs {
    private static func easeQuantile(_ data: [Point], _ quantile: Double) -> Double? {
        var count = data.reduce(0) { $0 + $1.count } * quantile
        for point in data {
            count -= point.count
            if count <= 0 { return point.x }
        }
        return nil
    }

    /// percentageRange.ts's getAdjustedScaleAndTicks; the ease graph's own
    /// copy has no minimum bin size.
    private static func scaleAndTicks(_ low: Double, _ high: Double, minBinSize: Double?) -> ((Double, Double), [Double]) {
        let domain = GraphScale.nice((low, high))
        var ticks = GraphScale.ticks(domain.0, domain.1, count: 20)
        let minOffset = low - domain.0
        var tickSize = ticks.count > 1 ? ticks[1] - ticks[0] : .nan
        if let minBinSize, tickSize < minBinSize {
            ticks = Array(stride(from: low, to: high, by: minBinSize))
            tickSize = minBinSize
        }
        if minOffset == 0
            || (minOffset.truncatingRemainder(dividingBy: tickSize) != 0
                && tickSize.truncatingRemainder(dividingBy: minOffset) != 0) {
            return (domain, ticks)
        }
        return ((domain.0 + minOffset, domain.1 + minOffset), ticks.map { $0 + minOffset })
    }

    private static func histogram(
        _ data: [Point], low: Double, high: Double, minBinSize: Double?, colour: @escaping (Double) -> Color,
        hover: @escaping (PointBin) -> String, query: @escaping (Double, Double) -> String
    ) -> Histogram {
        let (domain, ticks) = scaleAndTicks(low, high, minBinSize: minBinSize)
        let bins = GraphScale.bin(data, value: \.x, domain: domain, thresholds: ticks)
        return Histogram(
            bins: bins, domain: domain, total: bins.reduce(0) { $0 + $1.value }, showArea: false,
            colour: colour, hoverText: { bin, _, _ in hover(bin) },
            search: { query($0.x0, $0.x1 - 1) },
            xTickFormat: { "\(localizedNumber($0, 0))%" })
    }

    private static func percent(_ value: Float) -> String { "\(localizedNumber(Double(value), 0))%" }

    static func ease(_ data: GraphsResponse) -> (Histogram?, [TableRow]) {
        let eases = points(data.eases.eases)
        guard let last = eases.last else { return (nil, []) }
        let low = 130.0
        let histogram = histogram(
            eases, low: low, high: last.x + 1, minBinSize: nil,
            colour: { ColorRamp.redYellowGreen(GraphScale.linear($0, domain: (low, 300), range: (0, 1))) },
            hover: { bin in
                let percent = floor(bin.x1) - floor(bin.x0) <= 10
                    ? "\(plain(bin.x0))%" : "\(plain(bin.x0))%-\(plain(bin.x1))%"
                return Tr.statisticsCardEaseTooltip(cards: bin.value, percent: percent)
            },
            query: { start, end in
                start == end
                    ? "\"prop:ease=\(plain(start / 100))\""
                    : "\"prop:ease>=\(plain(start / 100))\" AND \"prop:ease<\(plain((end + 1) / 100))\""
            })
        return (histogram, [TableRow(label: Tr.statisticsMedianEase, value: percent(data.eases.average))])
    }

    private static func fsrsQuery(_ property: String) -> (Double, Double) -> String {
        { start, end in
            let comparison = end == 99 ? "<=" : "<"
            return "\"prop:\(property)>=\(plain(start / 100))\" AND \"prop:\(property)\(comparison)\(plain((end + 1) / 100))\""
        }
    }

    private static func bounds(_ data: [Point], _ range: PercentageRange) -> (Double, Double) {
        guard let quantile = range.quantile else { return (0, 100) }
        return (easeQuantile(data, 1 - quantile) ?? 0, easeQuantile(data, quantile) ?? 0)
    }

    static func difficulty(_ data: GraphsResponse, range: PercentageRange) -> (Histogram?, [TableRow]) {
        let values = points(data.difficulty.eases)
        guard !values.isEmpty else { return (nil, []) }
        let (low, high) = bounds(values, range)
        let histogram = histogram(
            values, low: low, high: high, minBinSize: 1,
            colour: { ColorRamp.redYellowGreen(GraphScale.linear($0, domain: (100, 0), range: (0, 1))) },
            hover: { Tr.statisticsCardDifficultyTooltip(cards: $0.value, percent: "\(plain($0.x0))%-\(plain($0.x1))%") },
            query: fsrsQuery("d"))
        return (histogram, [TableRow(label: Tr.statisticsMedianDifficulty, value: percent(data.difficulty.average))])
    }

    static func retrievability(_ data: GraphsResponse, range: PercentageRange) -> (Histogram?, [TableRow]) {
        let source = data.retrievability
        let values = points(source.retrievability)
        guard !values.isEmpty else { return (nil, []) }
        let (low, high) = bounds(values, range)
        let histogram = histogram(
            values, low: low, high: high, minBinSize: 1,
            colour: { ColorRamp.redYellowGreen(GraphScale.linear($0, domain: (0, 100), range: (0, 1))) },
            hover: { Tr.statisticsRetrievabilityTooltip(cards: $0.value, percent: "\(plain($0.x0))%-\(plain($0.x1))%") },
            query: fsrsQuery("r"))
        let knowledge = "\(Tr.statisticsCards(cards: Double(source.sumByCard).rounded())) / "
            + Tr.statisticsNotes(notes: Double(source.sumByNote).rounded())
        return (histogram, [
            TableRow(label: Tr.statisticsAverageRetrievability, value: percent(source.average)),
            TableRow(label: Tr.statisticsEstimatedTotalKnowledge, value: knowledge),
        ])
    }
}

// MARK: Added

enum AddedGraph {
    static func histogram(_ data: GraphsResponse, range: GraphRange) -> (Histogram?, [TableRow]) {
        let added = points(data.added.added)
        guard let first = added.first else { return (nil, []) }
        let xMin: Double = switch range {
        case .month: -31
        case .threeMonths: -90
        case .year: -365
        case .allTime: first.x
        }
        let xMax = 1.0
        let thresholds = GraphScale.ticks(xMin, xMax, count: min(70, abs(xMin)))
        let bins = GraphScale.bin(added, value: \.x, domain: (xMin, xMax), thresholds: thresholds)
        let total = bins.reduce(0) { $0 + $1.value }
        guard total > 0 else { return (nil, []) }
        let histogram = Histogram(
            bins: bins, domain: (xMin, xMax), total: total, showArea: true,
            colour: { Theme.Statistics.shade(Theme.Colors.newCards, GraphScale.linear($0, domain: (xMax, xMin), range: (1, 0.4))) },
            hoverText: { bin, cumulative, _ in
                "\(dayLabel(bin.x0, bin.x1)):\n\(Tr.statisticsCards(cards: bin.value))\n"
                    + "\(Tr.statisticsRunningTotal): \(Tr.statisticsCards(cards: cumulative))"
            },
            search: { bin in
                let start = Int(abs(bin.x0)) + 1, end = Int(abs(bin.x1)) + 1
                return start == 1 ? "\"added:\(start)\"" : "\"added:\(start)\" AND -\"added:\(end)\""
            })
        let table = [
            TableRow(label: Tr.statisticsTotal, value: Tr.statisticsCards(cards: total)),
            TableRow(label: Tr.statisticsAverage, value: Tr.statisticsCardsPerDay(count: jsRound(total / abs(xMin)))),
        ]
        return (histogram, table)
    }
}

// MARK: Hourly Breakdown

struct HoursGraph {
    struct Hour: Identifiable {
        let id: Int
        let total: Int
        let correct: Int
        var ratio: Double { total > 0 ? Double(correct) / Double(total) : 0 }
    }

    let hours: [Hour]
    let maxTotal: Int

    init?(_ data: GraphsResponse, range: GraphRange) {
        let source: [GraphsResponse.Hours.Hour] = switch range {
        case .month: data.hours.oneMonth
        case .threeMonths: data.hours.threeMonths
        case .year: data.hours.oneYear
        case .allTime: data.hours.allTime
        }
        hours = source.enumerated().map { Hour(id: $0, total: Int($1.total), correct: Int($1.correct)) }
        maxTotal = hours.map(\.total).max() ?? 0
        guard maxTotal > 0 else { return nil }
    }

    func colour(_ hour: Hour) -> Color {
        Theme.Statistics.shade(Theme.Colors.newCards, 0.2 + 0.8 * Double(hour.total) / Double(maxTotal))
    }

    /// Upstream's lines, without the 📊 and 📈 that key them to the bar and
    /// the line; the tooltip draws swatches instead.
    func tooltipLines(_ hour: Hour) -> (range: String, reviews: String, correct: String) {
        let plain = { (text: String) in
            String(text.filter { !($0.unicodeScalars.first?.properties.isEmojiPresentation ?? false) })
                .trimmingCharacters(in: .whitespaces)
        }
        return (
            Tr.statisticsHoursRange(hourStart: String(hour.id), hourEnd: String(hour.id + 1)),
            plain(Tr.statisticsHoursReviews(reviews: Tr.number(hour.total))),
            plain(Tr.statisticsHoursCorrectReviews(percent: Tr.number(hour.ratio * 100), reviews: Tr.number(hour.correct))))
    }

    func tooltip(_ hour: Hour) -> String {
        let lines = tooltipLines(hour)
        return [lines.range, lines.reviews, lines.correct].joined(separator: "\n")
    }
}

// MARK: Answer Buttons

struct ButtonsGraph {
    enum Group: String, CaseIterable, Identifiable {
        case learning, young, mature

        var id: Self { self }

        var label: String {
            switch self {
            case .learning: Tr.statisticsCountsLearningCards
            case .young: Tr.statisticsCountsYoungCards
            case .mature: Tr.statisticsCountsMatureCards
            }
        }
    }

    struct Bar: Identifiable {
        var id: String { "\(group.rawValue)\(button)" }
        let group: Group
        let button: Int
        let count: Int
    }

    let bars: [Bar]
    let maxCount: Int

    init?(_ data: GraphsResponse, range: GraphRange) {
        let counts = switch range {
        case .month: data.buttons.oneMonth
        case .threeMonths: data.buttons.threeMonths
        case .year: data.buttons.oneYear
        case .allTime: data.buttons.allTime
        }
        let groups: [(Group, [UInt32])] = [(.learning, counts.learning), (.young, counts.young), (.mature, counts.mature)]
        bars = groups.flatMap { group, values in
            values.enumerated().map { Bar(group: group, button: $0 + 1, count: Int($1)) }
        }
        maxCount = bars.map(\.count).max() ?? 0
        guard maxCount > 0 else { return nil }
    }

    static func colour(_ button: Int) -> Color {
        Theme.Statistics.grades[button - 1]
    }

    func tooltip(_ bar: Bar) -> String {
        let group = bars.filter { $0.group == bar.group }
        let total = group.reduce(0) { $0 + $1.count }
        let correct = group.filter { $0.button > 1 }.reduce(0) { $0 + $1.count }
        let correctPercent = total > 0 ? localizedNumber(Double(correct) / Double(total) * 100) : "0"
        let pressedPercent = total > 0 ? localizedNumber(Double(bar.count) / Double(total) * 100) : "0"
        let name = switch bar.button {
        case 1: Tr.studyingAgain
        case 2: Tr.studyingHard
        case 3: Tr.studyingGood
        case 4: Tr.studyingEasy
        default: ""
        }
        let correctText = Tr.statisticsHoursCorrect(
            correct: Tr.number(correct), total: Tr.number(total), percent: correctPercent)
        return [
            "\(Tr.statisticsAnswerButtonsButtonNumber): \(bar.button) (\(name))",
            "\(Tr.statisticsAnswerButtonsButtonPressed): \(localizedNumber(Double(bar.count))) (\(pressedPercent)%)",
            "\(correctText) \(Tr.statisticsHoursCorrectInfo)",
        ].joined(separator: "\n")
    }
}

// MARK: True Retention

struct TrueRetentionGraph {
    enum Mode: Int, CaseIterable, Identifiable {
        case young, mature, summary

        var id: Self { self }

        var title: String {
            switch self {
            case .young: Tr.statisticsTrueRetentionYoung
            case .mature: Tr.statisticsTrueRetentionMature
            case .summary: Tr.statisticsTrueRetentionAll
            }
        }
    }

    struct Row: Identifiable {
        var id: String { title }
        let title: String
        let youngPassed: Int
        let youngFailed: Int
        let maturePassed: Int
        let matureFailed: Int
    }

    let rows: [Row]

    init(_ data: GraphsResponse, history: RevlogHistory) {
        let stats = data.trueRetention
        var periods = [
            (Tr.statisticsTrueRetentionToday, stats.today),
            (Tr.statisticsTrueRetentionYesterday, stats.yesterday),
            (Tr.statisticsTrueRetentionWeek, stats.week),
            (Tr.statisticsTrueRetentionMonth, stats.month),
            (Tr.statisticsTrueRetentionYear, stats.year),
        ]
        if history == .all { periods.append((Tr.statisticsTrueRetentionAllTime, stats.allTime)) }
        rows = periods.map { title, value in
            Row(
                title: title, youngPassed: Int(value.youngPassed), youngFailed: Int(value.youngFailed),
                maturePassed: Int(value.maturePassed), matureFailed: Int(value.matureFailed))
        }
    }

    static func retention(passed: Int, failed: Int) -> String {
        let total = passed + failed
        guard total > 0 else { return Tr.statisticsTrueRetentionNotApplicable }
        return (Double(passed) / Double(total)).formatted(.percent.precision(.fractionLength(1)))
    }
}
