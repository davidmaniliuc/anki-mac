import AnkiKit
import Foundation

/// Desktop's Card Info text, ported from upstream's `ts/lib/tslib/time.ts` and
/// `ts/routes/card-info/{lib,Revlog}.ts`: the same rows, in the same order,
/// with the same rounding.
enum CardInfoFormat {
    // MARK: Time spans

    enum Unit: Int, Comparable {
        case seconds, minutes, hours, days, months, years

        static func < (a: Unit, b: Unit) -> Bool { a.rawValue < b.rawValue }

        var seconds: Double {
            switch self {
            case .seconds: 1
            case .minutes: 60
            case .hours: 3600
            case .days: 86400
            case .months: 365 * 86400 / 12
            case .years: 365 * 86400
            }
        }

        static func natural(_ secs: Double) -> Unit {
            let secs = abs(secs)
            for unit in [Unit.seconds, .minutes, .hours, .days, .months] where secs < unit.next.seconds { return unit }
            return .years
        }

        private var next: Unit { Unit(rawValue: rawValue + 1) ?? .years }
    }

    static let day = Unit.days.seconds

    /// "1.17 months", or "3d" when `short`. Seconds and days below a month
    /// are rounded to whole numbers unless `precise`.
    static func timeSpan(_ seconds: Double, short: Bool = false, precise: Bool = true, maxUnit: Unit = .years) -> String {
        let unit = min(Unit.natural(seconds), maxUnit)
        var amount = seconds / unit.seconds
        if !precise, unit < .months { amount = amount.rounded() }
        if short {
            switch unit {
            case .seconds: return Tr.statisticsElapsedTimeSeconds(amount: amount)
            case .minutes: return Tr.statisticsElapsedTimeMinutes(amount: amount)
            case .hours: return Tr.statisticsElapsedTimeHours(amount: amount)
            case .days: return Tr.statisticsElapsedTimeDays(amount: amount)
            case .months: return Tr.statisticsElapsedTimeMonths(amount: amount)
            case .years: return Tr.statisticsElapsedTimeYears(amount: amount)
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

    // MARK: Dates

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// YYYY-MM-DD in the local time zone, as upstream's `Timestamp.dateString`.
    static func dateString(_ timestamp: Int64) -> String {
        formatter("yyyy-MM-dd").string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    /// HH:MM in the local time zone.
    static func timeString(_ timestamp: Int64) -> String {
        formatter("HH:mm").string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    // MARK: Stats table

    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    static func rows(_ stats: Anki_Stats_CardStatsResponse) -> [Row] {
        var rows: [Row] = []
        func add(_ label: String, _ value: String) { rows.append(Row(label: label, value: value)) }

        add(Tr.cardStatsAdded, dateString(stats.added))
        if stats.hasFirstReview { add(Tr.cardStatsFirstReview, dateString(stats.firstReview)) }
        if stats.hasLatestReview { add(Tr.cardStatsLatestReview, dateString(stats.latestReview)) }
        if stats.hasDueDate { add(Tr.statisticsDueDate, dateString(stats.dueDate)) }
        if stats.hasDuePosition { add(Tr.cardStatsNewCardPosition, String(stats.duePosition)) }
        if stats.interval != 0 { add(Tr.cardStatsInterval, timeSpan(Double(stats.interval) * day)) }

        if stats.hasMemoryState {
            let stability = Double(stats.memoryState.stability)
            var text = timeSpan(stability * day, precise: false)
            if stability > 31 { text += " (\(timeSpan(stability * day, precise: false, maxUnit: .days)))" }
            add(Tr.cardStatsFsrsStability, text)
            add(Tr.cardStatsFsrsDifficulty, "\(difficultyPercent(stats.memoryState.difficulty))%")
            if stats.hasFsrsRetrievability, stats.fsrsRetrievability != 0 {
                add(Tr.cardStatsFsrsRetrievability, String(format: "%.0f%%", Double(stats.fsrsRetrievability) * 100))
            }
        } else if stats.ease != 0, !stats.hasDesiredRetention {
            // With FSRS on but no memory state yet, ease would mislead.
            add(Tr.cardStatsEase, "\(Tr.number(Double(stats.ease) / 10))%")
        }

        add(Tr.cardStatsReviewCount, String(stats.reviews))
        add(Tr.cardStatsLapseCount, String(stats.lapses))
        if stats.totalSecs != 0 {
            add(Tr.cardStatsAverageTime, timeSpan(Double(stats.averageSecs)))
            add(Tr.cardStatsTotalTime, timeSpan(Double(stats.totalSecs)))
        }

        add(Tr.cardStatsCardTemplate, stats.cardType)
        add(Tr.cardStatsNoteType, stats.notetype)
        add(Tr.cardStatsDeckName, stats.hasOriginalDeck && !stats.originalDeck.isEmpty ? "\(stats.deck) (\(stats.originalDeck))" : stats.deck)
        add(Tr.cardStatsPreset, stats.preset)
        add(Tr.cardStatsCardId, String(stats.cardID))
        add(Tr.cardStatsNoteId, String(stats.noteID))
        if !stats.customData.isEmpty { add(Tr.cardStatsCustomData, customData(stats.customData)) }
        return rows
    }

    /// FSRS difficulty runs 1 to 10; shown as 0 to 100%.
    static func difficultyPercent(_ difficulty: Float) -> String {
        String(format: "%.0f", (Double(difficulty) - 1) / 9 * 100)
    }

    /// `key=value` pairs, as upstream; the raw text when it isn't a JSON object.
    /// JSON objects are unordered here, so keys are sorted.
    static func customData(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json }
        return object.keys.sorted().map { key in "\(key)=\(scalar(object[key]!))" }.joined(separator: " ")
    }

    private static func scalar(_ value: Any) -> String {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.doubleValue == number.doubleValue.rounded() && abs(number.doubleValue) < 1e15
                ? String(number.int64Value) : String(number.doubleValue)
        }
        return String(describing: value)
    }

    // MARK: Review log

    struct RevlogRow: Identifiable {
        let id: Int
        let date: String
        let time: String
        let kind: Anki_Stats_RevlogEntry.ReviewKind
        let kindLabel: String
        let rating: UInt32
        let interval: String
        let ease: String
        let taken: String
    }

    static func revlogRows(_ revlog: [Anki_Stats_CardStatsResponse.StatsRevlogEntry]) -> [RevlogRow] {
        revlog.enumerated().map { index, entry in
            RevlogRow(
                id: index, date: dateString(entry.time), time: timeString(entry.time),
                kind: entry.reviewKind, kindLabel: label(entry.reviewKind), rating: entry.buttonChosen,
                interval: timeSpan(Double(entry.interval)), ease: easeOrDifficulty(entry.ease),
                taken: timeSpan(Double(entry.takenSecs), short: true))
        }
    }

    static func label(_ kind: Anki_Stats_RevlogEntry.ReviewKind) -> String {
        switch kind {
        case .learning: Tr.cardStatsReviewLogTypeLearn
        case .review: Tr.cardStatsReviewLogTypeReview
        case .relearning: Tr.cardStatsReviewLogTypeRelearn
        case .filtered: Tr.cardStatsReviewLogTypeFiltered
        case .manual: Tr.cardStatsReviewLogTypeManual
        case .rescheduled: Tr.cardStatsReviewLogTypeRescheduled
        case .UNRECOGNIZED: ""
        }
    }

    /// The revlog stores FSRS difficulty as 1 to 11 tenths, shifted by 10%, and SM-2 ease as a permille.
    static func easeOrDifficulty(_ ease: UInt32) -> String {
        if ease == 0 { return "" }
        let percent = Double(ease) / 10
        return percent <= 110 ? "D:\(String(format: "%.0f", percent - 10))%" : "\(String(format: "%.0f", percent))%"
    }
}
