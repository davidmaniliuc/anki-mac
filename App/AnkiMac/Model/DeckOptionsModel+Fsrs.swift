import AnkiKit
import Foundation

/// FSRS work started from the options window, ported from desktop's
/// FsrsOptions.svelte. Optimizing and evaluating can take minutes, so they
/// report progress and can be cancelled.
extension DeckOptionsModel {
    enum FsrsJob: Equatable {
        case optimizing, evaluating, optimizingAll
    }

    /// The search FSRS learns from: the preset's own, or every unsuspended
    /// card using the preset.
    var paramSearch: String { config.paramSearch.isEmpty ? presetSearch : config.paramSearch }

    /// Desktop parses the date as UTC midnight.
    private var ignoreRevlogsBeforeMs: Int64 {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: config.ignoreRevlogsBeforeDate) else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    /// Relearning steps that fit in a day.
    private var relearningStepsInDay: UInt32 {
        var total: Float = 0
        var count: UInt32 = 0
        for step in config.relearnSteps {
            total += step
            if total >= 1440 { break }
            count += 1
        }
        return count
    }

    /// "12.5% of 3,000 reviews" while optimizing.
    var progressText: String {
        guard let progress = fsrsProgress, progress.total > 0 else { return "" }
        if progress.current == progress.total { return Tr.deckConfigCheckingForImprovement }
        let percent = (Double(progress.current) / Double(progress.total) * 100).formatted(
            .number.precision(.fractionLength(1)))
        if fsrsJob == .optimizingAll, progress.totalPresets > 1 {
            return Tr.deckConfigOptimizingPreset(
                currentCount: String(progress.currentPreset), totalCount: String(progress.totalPresets))
                + " " + Tr.deckConfigPercentOfReviews(reviews: Int(progress.reviews), pct: percent)
        }
        return Tr.deckConfigPercentOfReviews(reviews: Int(progress.reviews), pct: percent)
    }

    /// Optimizes the selected preset's parameters. Returns what desktop
    /// shows in an alert afterwards, if anything.
    func optimize() async throws -> String? {
        let current = config.fsrsParams
        var request = Anki_Scheduler_ComputeFsrsParamsRequest()
        request.search = paramSearch
        request.ignoreRevlogsBeforeMs = ignoreRevlogsBeforeMs
        request.currentParams = current
        request.numOfRelearningSteps = relearningStepsInDay
        request.healthCheck = fsrsHealthCheck
        guard let response = try await runFsrs(.optimizing, { [request] in try $0.computeFsrsParams(request) }) else { return nil }
        let alreadyOptimal = response.params.isEmpty
            || (!current.isEmpty && current.count == response.params.count
                && zip(current, response.params).allSatisfy { rounded4($0) == rounded4($1) })
        var messages: [String] = []
        if alreadyOptimal {
            messages.append(response.fsrsItems > 0 ? Tr.deckConfigFsrsParamsOptimal : Tr.deckConfigFsrsParamsNoReviews)
        }
        if response.hasHealthCheckPassed {
            messages.append(response.healthCheckPassed ? Tr.deckConfigFsrsGoodFit : Tr.deckConfigFsrsBadFitWarning)
        }
        if !alreadyOptimal {
            config.fsrsParams6 = response.params
            optimizedParams = true
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n\n")
    }

    /// Desktop's legacy Evaluate: how well the parameters fit the history.
    func evaluate() async throws -> String? {
        var request = Anki_Scheduler_EvaluateParamsLegacyRequest()
        request.search = paramSearch
        request.ignoreRevlogsBeforeMs = ignoreRevlogsBeforeMs
        request.params = config.fsrsParams
        guard let response = try await runFsrs(.evaluating, { [request] in try $0.evaluateParamsLegacy(request) }) else {
            return nil
        }
        let logLoss = response.logLoss.formatted(.number.precision(.fractionLength(4)))
        let rmse = (response.rmseBins * 100).formatted(.number.precision(.fractionLength(2)))
        return "Log loss: \(logLoss), RMSE(bins): \(rmse)%. \(Tr.deckConfigSmallerIsBetter)"
    }

    /// Saves everything and optimizes every preset, as desktop's "Optimize
    /// All Presets".
    func saveAndOptimizeAll() async throws -> Bool {
        let request = request(mode: .computeAllParams)
        guard try await runFsrs(.optimizingAll, { try $0.updateDeckConfigs(request) }) != nil else { return false }
        markSaved()
        return true
    }

    /// Asks the running job to stop; it ends with an "interrupted" error,
    /// which `runFsrs` swallows.
    func cancelFsrsJob() {
        guard fsrsJob != nil else { return }
        let backend = backend
        Task.detached { try? backend.setWantsAbort() }
    }

    func cancelBackgroundWork() {
        cancelFsrsJob()
    }

    /// The change in daily workload from the retention the window opened
    /// with, as desktop's note under desired retention.
    func workloadNote(retention: Double) async -> String {
        let start = (startingRetention * 100).rounded()
        let after = (retention * 100).rounded()
        if start == after { return Tr.deckConfigWorkloadFactorUnchanged }
        let params = config.fsrsParams
        if workloadCosts == nil || workloadParams != params {
            var request = Anki_DeckConfig_GetRetentionWorkloadRequest()
            request.w = params
            request.search = presetSearch
            workloadParams = params
            workloadCosts = try? await backend.perform { [request] in try $0.getRetentionWorkload(request).costs }
        }
        guard let costs = workloadCosts, let before = costs[UInt32(start)], let now = costs[UInt32(after)],
            before > 0
        else { return "" }
        return Tr.deckConfigWorkloadFactorChange(
            factor: (now / before).formatted(.number.precision(.fractionLength(2))),
            previousDR: String(Int(start)))
    }

    /// How many cards "ignore reviews before" leaves for optimizing.
    func ignoredBeforeCount(date: String) async -> Anki_DeckConfig_GetIgnoredBeforeCountResponse? {
        guard !date.isEmpty, date != "1970-01-01" else { return nil }
        var request = Anki_DeckConfig_GetIgnoredBeforeCountRequest()
        request.search = paramSearch
        request.ignoreRevlogsBeforeDate = date
        return try? await backend.perform { [request] in try $0.getIgnoredBeforeCount(request) }
    }

    /// Runs a long FSRS call, polling the backend's progress meanwhile.
    /// Returns nil when the user cancelled.
    private func runFsrs<T: Sendable>(
        _ job: FsrsJob, _ work: @escaping @Sendable (AnkiBackend) throws -> T
    ) async throws -> T? {
        guard fsrsJob == nil else { return nil }
        fsrsJob = job
        fsrsProgress = nil
        let backend = backend
        let poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Theme.DeckOptions.progressInterval)
                guard let progress = try? await backend.perform({ try $0.latestProgress() }) else { continue }
                if case .computeParams(let value)? = progress.value { self?.fsrsProgress = value }
            }
        }
        defer {
            poll.cancel()
            fsrsJob = nil
        }
        do {
            let result = try await backend.perform(work)
            if let progress = fsrsProgress { lastReviewCount = progress.reviews }
            return result
        } catch let error as AnkiError where error.backend?.kind == .interrupted {
            return nil
        }
    }

    private func rounded4(_ value: Float) -> Float { (value * 10_000).rounded() / 10_000 }
}
