import AnkiKit
import Foundation
import Observation

/// Desktop's FSRS simulator (SimulatorModal.svelte), in its two forms: the
/// review simulator, which plots each day of a simulated year, and "Help Me
/// Decide", which plots the workload at each desired retention. Runs pile
/// up so they can be compared.
@Observable
final class FsrsSimulator: Identifiable {
    enum Graph: CaseIterable, Identifiable {
        case ratio, count, time, memorized
        var id: Self { self }

        var title: String {
            switch self {
            case .ratio: Tr.deckConfigFsrsSimulatorRadioEfficiency
            case .count: Tr.deckConfigFsrsSimulatorRadioCount
            case .time: Tr.statisticsReviewsTimeCheckbox
            case .memorized: Tr.deckConfigFsrsSimulatorRadioMemorized
            }
        }
    }

    struct Point: Identifiable {
        let run: Int
        /// Days from today, or the desired retention in percent.
        let x: Double
        var timeCost: Double
        var count: Double
        var memorized: Double
        var reviewlessEndMemorized: Double = 0
        var id: String { "\(run)-\(x)" }
    }

    let workload: Bool
    private let options: DeckOptionsModel

    var daysToSimulate: Double = 365
    var additionalNewCards: Double = 0
    var desiredRetention: Double
    var newLimit: Double
    var reviewLimit: Double
    var maxInterval: Double
    var reviewOrder: DeckConfigInner.ReviewCardOrder
    var newCardsIgnoreReviewLimit: Bool
    var easyDays: [Float]
    var smooth = true
    var suspendLeeches: Bool
    var leechThreshold: Double
    var graph: Graph

    private(set) var points: [Point] = []
    private(set) var runCount = 0
    private(set) var simulating = false
    private(set) var computingRetention = false
    private(set) var retentionIterations: UInt32?
    private(set) var optimalRetention: Double?
    var failure: ActionFailure?

    init(options: DeckOptionsModel, workload: Bool) {
        self.options = options
        self.workload = workload
        let config = options.config
        desiredRetention = Double(config.desiredRetention)
        newLimit = Double(config.newPerDay)
        // Help Me Decide lifts the review limit, as desktop does.
        reviewLimit = workload ? 9999 : Double(config.reviewsPerDay)
        maxInterval = Double(config.maximumReviewInterval)
        reviewOrder = config.reviewOrder
        newCardsIgnoreReviewLimit = options.newCardsIgnoreReviewLimit
        easyDays = config.easyDaysPercentages
        suspendLeeches = config.leechAction == .suspend
        leechThreshold = Double(config.leechThreshold)
        graph = workload ? .ratio : .count
    }

    var graphs: [Graph] { workload ? Graph.allCases : [.count, .time, .memorized] }
    var busy: Bool { simulating || computingRetention }

    private var request: Anki_Scheduler_SimulateFsrsReviewRequest {
        let config = options.config
        var request = Anki_Scheduler_SimulateFsrsReviewRequest()
        request.params = config.fsrsParams
        request.desiredRetention = Float(desiredRetention)
        request.deckSize = UInt32(additionalNewCards)
        request.daysToSimulate = UInt32(daysToSimulate)
        request.newLimit = UInt32(newLimit)
        request.reviewLimit = UInt32(reviewLimit)
        request.maxInterval = UInt32(maxInterval)
        request.search = options.presetSearch
        request.newCardsIgnoreReviewLimit = newCardsIgnoreReviewLimit
        request.easyDaysPercentages = easyDays
        request.reviewOrder = reviewOrder
        request.historicalRetention = config.historicalRetention
        request.learningStepCount = UInt32(config.learnSteps.count)
        request.relearningStepCount = UInt32(config.relearnSteps.count)
        if suspendLeeches { request.suspendAfterLapseCount = UInt32(leechThreshold) }
        return request
    }

    func simulate() {
        guard !busy else { return }
        let request = request
        let workload = workload
        simulating = true
        failure = nil
        Task {
            defer { simulating = false }
            do {
                let run = runCount + 1
                let new: [Point]
                if workload {
                    let response = try await options.backend.perform { try $0.simulateFsrsWorkload(request) }
                    new = response.memorized.keys.sorted().map { retention in
                        Point(
                            run: run, x: Double(retention), timeCost: Double(response.cost[retention] ?? 0),
                            count: Double(response.reviewCount[retention] ?? 0),
                            memorized: Double(response.memorized[retention] ?? 0),
                            reviewlessEndMemorized: Double(response.reviewlessEndMemorized))
                    }
                } else {
                    let response = try await options.backend.perform { try $0.simulateFsrsReview(request) }
                    new = response.dailyTimeCost.indices.map { day in
                        Point(
                            run: run, x: Double(day), timeCost: Double(response.dailyTimeCost[day]),
                            count: Double(response.dailyReviewCount[day] + response.dailyNewCount[day]),
                            memorized: Double(response.accumulatedKnowledgeAcquisition[day]))
                    }
                }
                runCount = run
                points += new
            } catch {
                failure = ActionFailure("Couldn’t run the simulation", error: error)
            }
        }
    }

    func clearLast() {
        guard runCount > 0 else { return }
        points.removeAll { $0.run == runCount }
        runCount -= 1
    }

    /// Desktop's "Minimum recommended retention", with its iteration count.
    func computeRetention() {
        if computingRetention {
            let backend = options.backend
            Task.detached { try? backend.setWantsAbort() }
            return
        }
        let request = request
        let backend = options.backend
        computingRetention = true
        retentionIterations = nil
        failure = nil
        let poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Theme.DeckOptions.progressInterval)
                guard let progress = try? await backend.perform({ try $0.latestProgress() }) else { continue }
                if case .computeRetention(let value)? = progress.value { self?.retentionIterations = value.current }
            }
        }
        Task {
            defer {
                poll.cancel()
                computingRetention = false
            }
            do {
                optimalRetention = Double(try await backend.perform { try $0.computeOptimalRetention(request) }
                    .optimalRetention)
            } catch let error as AnkiError where error.backend?.kind == .interrupted {
            } catch {
                failure = ActionFailure("Couldn’t compute the retention", error: error)
            }
        }
    }

    /// Copies the simulator's settings into the preset.
    func saveToPreset() {
        var config = options.config
        config.newPerDay = UInt32(newLimit)
        config.reviewsPerDay = UInt32(reviewLimit)
        config.maximumReviewInterval = UInt32(maxInterval)
        if !workload { config.desiredRetention = Float(desiredRetention) }
        config.reviewOrder = reviewOrder
        config.leechAction = suspendLeeches ? .suspend : .tagOnly
        config.leechThreshold = UInt32(leechThreshold)
        config.easyDaysPercentages = easyDays
        options.config = config
        options.newCardsIgnoreReviewLimit = newCardsIgnoreReviewLimit
        options.presetChanged()
    }

    // MARK: Plotting

    /// The points of the chosen graph, smoothed per run as desktop does.
    var plotted: [Point] {
        let window = smooth ? max(1, Int((daysToSimulate / 365).rounded(.up))) : 1
        return Dictionary(grouping: points, by: \.run).keys.sorted().flatMap { run in
            let group = points.filter { $0.run == run }
            guard window > 1 else { return group }
            return group.indices.map { index in
                let slice = group[max(0, index - window + 1)...index]
                var point = group[index]
                point.timeCost = slice.map(\.timeCost).reduce(0, +) / Double(slice.count)
                point.count = slice.map(\.count).reduce(0, +) / Double(slice.count)
                point.memorized = slice.map(\.memorized).reduce(0, +) / Double(slice.count)
                return point
            }
        }
    }

    func y(_ point: Point) -> Double {
        switch (graph, workload) {
        case (.ratio, _):
            point.timeCost > 0 ? 3600 * (point.memorized - point.reviewlessEndMemorized) / point.timeCost : 0
        case (.time, true): point.timeCost / daysToSimulate
        case (.count, true): point.count / daysToSimulate
        case (.time, false): point.timeCost
        case (.count, false): point.count
        case (.memorized, _): point.memorized
        }
    }

    var yAxisTitle: String {
        switch graph {
        case .ratio: Tr.deckConfigFsrsSimulatorRadioEfficiency
        case .count: Tr.deckConfigFsrsSimulatorYAxisTitleCount
        case .time: Tr.deckConfigFsrsSimulatorYAxisTitleTime
        case .memorized: Tr.deckConfigFsrsSimulatorYAxisTitleMemorized
        }
    }

    /// The value as desktop's tooltip words it.
    func describe(_ value: Double) -> String {
        switch (graph, workload) {
        case (.ratio, _):
            Tr.deckConfigFsrsSimulatorRatioTooltip2(time: value.formatted(.number.precision(.fractionLength(2))))
        case (.time, true):
            "\((value / 60).formatted(.number.precision(.significantDigits(2)))) minutes/day"
        case (.count, true): Tr.statisticsReviewsPerDay(count: Int(value.rounded()))
        case (.time, false): Self.duration(value)
        case (.count, false): Tr.statisticsReviews(reviews: Int(value.rounded()))
        case (.memorized, _): Tr.statisticsMemorized(memorized: String(Int(value.rounded())))
        }
    }

    static func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }
}
