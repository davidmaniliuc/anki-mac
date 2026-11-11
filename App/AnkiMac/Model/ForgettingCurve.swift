import AnkiKit
import Foundation

/// The FSRS forgetting curve of Card Info, ported from upstream's
/// `ts/routes/card-info/forgetting-curve.ts`: retrievability between reviews
/// and on to the card's next due date.
enum ForgettingCurve {
    typealias Entry = Anki_Stats_CardStatsResponse.StatsRevlogEntry

    struct Point: Identifiable {
        let id: Int
        let date: Date
        let daysSinceFirstLearn: Double
        let elapsedDays: Double
        /// 0 to 100.
        let retrievability: Double
        let stability: Double
    }

    enum Range: CaseIterable, Hashable {
        case week, month, year, allTime

        var maxDays: Double {
            switch self {
            case .week: 7
            case .month: 30
            case .year: 365
            case .allTime: .infinity
            }
        }

        var label: String {
            switch self {
            case .week: Tr.cardStatsFsrsForgettingCurveFirstWeek
            case .month: Tr.cardStatsFsrsForgettingCurveFirstMonth
            case .year: Tr.cardStatsFsrsForgettingCurveFirstYear
            case .allTime: Tr.cardStatsFsrsForgettingCurveAllTime
            }
        }

        /// The ranges worth offering for a history of `maxDays`.
        static func available(maxDays: Double) -> [Range] {
            guard maxDays > 7 else { return [] }
            return [.week, .month] + (maxDays > 30 ? [.year] : []) + (maxDays > 365 ? [.allTime] : [])
        }

        static func defaultRange(maxDays: Double) -> Range {
            if maxDays > 365 { .allTime } else if maxDays > 30 { .year } else if maxDays > 7 { .month } else { .week }
        }
    }

    /// FSRS-6's default decay, or the one in the preset's parameters.
    static func decay(params: [Float]) -> Double {
        if params.isEmpty { return 0.1542 }
        if params.count < 21 { return 0.5 }
        return Double(params[20])
    }

    static func retrievability(stability: Double, daysElapsed: Double, decay: Double) -> Double {
        let factor = pow(0.9, 1 / -decay) - 1
        return pow(daysElapsed / stability * factor + 1, -decay)
    }

    /// Manual-with-ease-0 entries (a reset) end the memory history, as do
    /// entries without a memory state; manual, rescheduled and filtered
    /// entries without an ease are left out. Newest first, as the backend sends it.
    static func filter(_ revlog: [Entry]) -> [Entry] {
        var kept: [Entry] = []
        for entry in revlog {
            if (entry.reviewKind == .manual && entry.ease == 0) || !entry.hasMemoryState { break }
            kept.append(entry)
        }
        return kept.filter(countsAsReview)
    }

    static func countsAsReview(_ entry: Entry) -> Bool {
        entry.reviewKind != .manual && entry.reviewKind != .rescheduled && (entry.reviewKind != .filtered || entry.ease != 0)
    }

    static func maxDays(_ filtered: [Entry], range: Range, now: Date = Date()) -> Double {
        guard let newest = filtered.first, let oldest = filtered.last else { return 0 }
        let now = now.timeIntervalSince1970
        let sinceFirstLearn = (now - Double(oldest.time)) / 86400
        let sinceLastReview = (now - Double(newest.time)) / 86400
        let lastScheduled = Double(newest.interval) / 86400
        let preview = max(lastScheduled * 1.5 - sinceLastReview, lastScheduled * 0.5)
        return min(sinceFirstLearn + preview, range.maxDays)
    }

    /// The curve from the first review to `maxDays` after it, a point per
    /// `maxDays / 1000` days (at most a day).
    static func points(_ filtered: [Entry], maxDays: Double, decay: Double, now: Date = Date()) -> [Point] {
        guard maxDays > 0 else { return [] }
        let step = min(maxDays / 1000, 1)
        var data: [Point] = []
        func append(_ date: Double, days: Double, elapsed: Double, retrievability: Double, stability: Double) {
            data.append(Point(
                id: data.count, date: Date(timeIntervalSince1970: date), daysSinceFirstLearn: days,
                elapsedDays: elapsed, retrievability: retrievability, stability: stability))
        }
        func beyond() -> Bool { (data.last?.daysSinceFirstLearn ?? 0) > maxDays }

        var lastTime = 0.0
        var lastStability = 0.0
        var days = 0.0
        for (index, entry) in filtered.reversed().enumerated() {
            let time = Double(entry.time)
            if index == 0 {
                lastTime = time
                lastStability = Double(entry.memoryState.stability)
                append(time, days: 0, elapsed: 0, retrievability: 100, stability: lastStability)
                continue
            }
            let total = (time - lastTime) / 86400
            var elapsed = 0.0
            while elapsed < total - step, !beyond() {
                elapsed += step
                append(
                    lastTime + elapsed * 86400, days: data[data.count - 1].daysSinceFirstLearn + step, elapsed: elapsed,
                    retrievability: retrievability(stability: lastStability, daysElapsed: elapsed, decay: decay) * 100,
                    stability: lastStability)
            }
            days += total
            append(lastTime + total * 86400, days: days, elapsed: 0, retrievability: 100, stability: lastStability)
            if beyond() { return data.filter { $0.daysSinceFirstLearn <= maxDays } }
            lastTime = time
            lastStability = Double(entry.memoryState.stability)
        }
        guard !data.isEmpty else { return [] }

        let now = now.timeIntervalSince1970
        let sinceLastReview = (now - lastTime) / 86400
        var elapsed = 0.0
        while elapsed < sinceLastReview - step, !beyond() {
            elapsed += step
            append(
                lastTime + elapsed * 86400, days: data[data.count - 1].daysSinceFirstLearn + step, elapsed: elapsed,
                retrievability: retrievability(stability: lastStability, daysElapsed: elapsed, decay: decay) * 100,
                stability: lastStability)
        }
        days += sinceLastReview
        append(
            now, days: days, elapsed: sinceLastReview,
            retrievability: retrievability(stability: lastStability, daysElapsed: sinceLastReview, decay: decay) * 100,
            stability: lastStability)

        let preview = maxDays - sinceLastReview
        var previewElapsed = 0.0
        while previewElapsed < preview, !beyond() {
            previewElapsed += step
            append(
                now + previewElapsed * 86400, days: data[data.count - 1].daysSinceFirstLearn + step,
                elapsed: sinceLastReview + previewElapsed,
                retrievability: retrievability(
                    stability: lastStability, daysElapsed: elapsed + previewElapsed, decay: decay) * 100,
                stability: lastStability)
        }
        return data.filter { $0.daysSinceFirstLearn <= maxDays }
    }
}
