import AnkiKit
import Foundation
import Observation

typealias DeckConfig = Anki_DeckConfig_DeckConfig
typealias DeckConfigInner = Anki_DeckConfig_DeckConfig.Config
typealias DeckLimits = Anki_DeckConfig_DeckConfigsForUpdate.CurrentDeck.Limits

/// The state behind the Deck Options window, ported from desktop's
/// `DeckOptionsState` (ts/routes/deck-options/lib.ts): the presets, which
/// one the deck uses, the deck's own limits and the collection-wide options,
/// with enough bookkeeping to send back only what changed.
@Observable
final class DeckOptionsModel {
    struct Preset {
        var config: DeckConfig
        /// Decks using it, not counting this one; the list adds one to the
        /// selected preset, so the counts follow the selection.
        var useCount: Int
    }

    let deckID: Int64
    let deckName: String
    let defaults: DeckConfigInner
    let legacyEvaluate: Bool

    private(set) var presets: [Preset]
    private(set) var selectedIndex: Int
    var limits: DeckLimits
    var cardStateCustomizer: String
    var newCardsIgnoreReviewLimit: Bool
    var applyAllParentLimits: Bool
    var fsrs: Bool
    var fsrsReschedule = false
    var fsrsHealthCheck: Bool
    let daysSinceLastOptimization: Int

    let backend: AnkiBackend
    private var modifiedIDs: Set<Int64> = []
    private var removedIDs: [Int64] = []
    private var schemaModified: Bool
    private(set) var presetAssignmentsChanged = false
    /// Desktop's "today only" tabs restart from the last value used, even
    /// when it was set on an earlier day.
    private let lastNewToday: UInt32?
    private let lastReviewToday: UInt32?
    private var original: Snapshot!

    // FSRS jobs (DeckOptionsModel+Fsrs.swift).
    var fsrsJob: FsrsJob?
    var fsrsProgress: Anki_Collection_ComputeParamsProgress?
    /// Reviews the last optimization used, shown once it ends.
    var lastReviewCount: UInt32?
    /// Set once optimizing changed the parameters this time.
    var optimizedParams = false
    /// The desired retention in force when the window opened.
    private(set) var startingRetention: Double = 0
    var workloadCosts: [UInt32: Float]?
    var workloadParams: [Float] = []

    init(deckID: Int64, data: Anki_DeckConfig_DeckConfigsForUpdate, backend: AnkiBackend) {
        self.deckID = deckID
        self.backend = backend
        deckName = data.currentDeck.name
        defaults = data.defaults.config
        legacyEvaluate = data.fsrsLegacyEvaluate
        var presets = data.allConfig.map { Preset(config: $0.config, useCount: Int($0.useCount)) }
        let current = data.currentDeck.configID
        let selected = presets.firstIndex { $0.config.id == current } ?? 0
        presets[selected].useCount -= 1
        for index in presets.indices { Self.normalise(&presets[index].config.config, defaults: defaults) }
        self.presets = presets
        selectedIndex = selected
        cardStateCustomizer = data.cardStateCustomizer
        newCardsIgnoreReviewLimit = data.newCardsIgnoreReviewLimit
        applyAllParentLimits = data.applyAllParentLimits
        fsrs = data.fsrs
        fsrsHealthCheck = data.fsrsHealthCheck
        daysSinceLastOptimization = Int(data.daysSinceLastFsrsOptimize)
        schemaModified = data.schemaModified

        var limits = data.currentDeck.limits
        lastNewToday = limits.hasNewToday ? limits.newToday : nil
        lastReviewToday = limits.hasReviewToday ? limits.reviewToday : nil
        // A "today" limit from an earlier day no longer applies.
        if !limits.newTodayActive { limits.clearNewToday() }
        if !limits.reviewTodayActive { limits.clearReviewToday() }
        self.limits = limits
        sortPresets()
        setUpTabs()
        startingRetention = value(.retention)
        original = snapshot()
    }

    static func load(deckID: Int64, backend: AnkiBackend) async throws -> DeckOptionsModel {
        let data = try await backend.perform { backend in
            var id = Anki_Decks_DeckId()
            id.did = deckID
            return try backend.getDeckConfigsForUpdate(id)
        }
        return DeckOptionsModel(deckID: deckID, data: data, backend: backend)
    }

    // MARK: The selected preset

    var preset: DeckConfig { presets[selectedIndex].config }

    /// The selected preset's options. Writing one marks the preset changed.
    var config: DeckConfigInner {
        get { presets[selectedIndex].config.config }
        set {
            guard newValue != presets[selectedIndex].config.config else { return }
            presets[selectedIndex].config.config = newValue
            markModified()
        }
    }

    var isDefaultPresetSelected: Bool { preset.id == 1 }

    /// The search that selects this preset's cards, for FSRS.
    var presetSearch: String {
        let escaped = preset.name.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        return "preset:\"\(escaped)\" -is:suspended"
    }

    func useCount(at index: Int) -> Int {
        presets[index].useCount + (index == selectedIndex ? 1 : 0)
    }

    func select(_ index: Int) {
        guard index != selectedIndex, presets.indices.contains(index) else { return }
        selectedIndex = index
        presetAssignmentsChanged = true
        resetPresetTabs()
    }

    func rename(to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != preset.name else { return }
        presets[selectedIndex].config.name = uniqueName(name)
        markModified()
        sortPresets()
    }

    /// Adds a preset with the default options, or a copy of the selected
    /// one, and selects it. It is created on save.
    func addPreset(named name: String, cloning: Bool) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var config = DeckConfig()
        config.name = uniqueName(name)
        config.config = cloning ? self.config : defaults
        Self.normalise(&config.config, defaults: defaults)
        presets.append(Preset(config: config, useCount: 0))
        selectedIndex = presets.count - 1
        presetAssignmentsChanged = true
        sortPresets()
        resetPresetTabs()
    }

    /// Removing a saved preset changes the schema, so the next sync has to
    /// be one-way unless it already is.
    var removalForcesOneWaySync: Bool { !schemaModified && preset.id != 0 }

    func removePreset() {
        guard !isDefaultPresetSelected else { return }
        if preset.id != 0 {
            removedIDs.append(preset.id)
            schemaModified = true
        }
        presets.remove(at: selectedIndex)
        selectedIndex = max(0, selectedIndex - 1)
        presetAssignmentsChanged = true
        resetPresetTabs()
    }

    // MARK: Daily limits

    enum LimitScope: Int, CaseIterable, Identifiable, Comparable {
        case preset, deck, today
        var id: Self { self }

        var title: String {
            switch self {
            case .preset: Tr.deckConfigSharedPreset
            case .deck: Tr.deckConfigDeckOnly
            case .today: Tr.deckConfigTodayOnly
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// A value set per preset, per deck or for today only, as desktop's
    /// `TabbedValue`: the most specific one set is in force.
    enum Limit: CaseIterable {
        case new, review, retention

        var scopes: [LimitScope] { self == .retention ? [.preset, .deck] : LimitScope.allCases }
    }

    struct LimitTabs {
        var scope: LimitScope = .preset
        /// Each tab's last value, which it returns to when chosen again.
        var remembered: [LimitScope: Double] = [:]
        /// The values when the window opened (the preset's, when it was selected).
        var initial: [LimitScope: Double] = [:]
        /// Where a tab with no value starts: today's limit from an earlier day.
        var start: [LimitScope: Double] = [:]
    }

    private(set) var tabs: [Limit: LimitTabs] = [:]

    func scope(_ limit: Limit) -> LimitScope { tabs[limit]?.scope ?? .preset }

    func value(_ limit: Limit) -> Double { stored(limit, scope(limit)) ?? 0 }

    func setValue(_ limit: Limit, _ value: Double) {
        let scope = scope(limit)
        tabs[limit]?.remembered[scope] = value
        store(limit, scope, value)
    }

    /// Choosing a tab, as desktop does: it takes its last value (or the one
    /// shown), the tabs before it go back to their initial values, and the
    /// ones after it are cleared, since they would override it.
    func setScope(_ limit: Limit, _ scope: LimitScope) {
        guard var tab = tabs[limit] else { return }
        let shown = value(limit)
        for other in limit.scopes {
            if other == scope {
                let value = tab.remembered[other] ?? tab.start[other] ?? shown
                tab.remembered[other] = value
                store(limit, other, value)
            } else if other < scope {
                store(limit, other, tab.initial[other])
            } else {
                store(limit, other, nil)
            }
        }
        tab.scope = scope
        tabs[limit] = tab
    }

    private func setUpTabs() {
        for limit in Limit.allCases {
            var tab = LimitTabs()
            for scope in limit.scopes {
                if let value = stored(limit, scope) {
                    tab.initial[scope] = value
                    tab.remembered[scope] = value
                    tab.scope = scope
                }
            }
            if limit == .new, let last = lastNewToday { tab.start[.today] = Double(last) }
            if limit == .review, let last = lastReviewToday { tab.start[.today] = Double(last) }
            tabs[limit] = tab
        }
    }

    /// The preset tabs follow the newly selected preset.
    private func resetPresetTabs() {
        for limit in Limit.allCases {
            let value = stored(limit, .preset)
            tabs[limit]?.initial[.preset] = value
            tabs[limit]?.remembered[.preset] = value
        }
    }

    private func stored(_ limit: Limit, _ scope: LimitScope) -> Double? {
        switch (limit, scope) {
        case (.new, .preset): Double(config.newPerDay)
        case (.new, .deck): limits.hasNew ? Double(limits.new) : nil
        case (.new, .today): limits.hasNewToday ? Double(limits.newToday) : nil
        case (.review, .preset): Double(config.reviewsPerDay)
        case (.review, .deck): limits.hasReview ? Double(limits.review) : nil
        case (.review, .today): limits.hasReviewToday ? Double(limits.reviewToday) : nil
        case (.retention, .preset): Double(config.desiredRetention)
        case (.retention, _): limits.hasDesiredRetention ? Double(limits.desiredRetention) : nil
        }
    }

    private func store(_ limit: Limit, _ scope: LimitScope, _ value: Double?) {
        switch (limit, scope) {
        case (.new, .preset): if let value { config.newPerDay = UInt32(value) }
        case (.new, .deck): if let value { limits.new = UInt32(value) } else { limits.clearNew() }
        case (.new, .today): if let value { limits.newToday = UInt32(value) } else { limits.clearNewToday() }
        case (.review, .preset): if let value { config.reviewsPerDay = UInt32(value) }
        case (.review, .deck): if let value { limits.review = UInt32(value) } else { limits.clearReview() }
        case (.review, .today): if let value { limits.reviewToday = UInt32(value) } else { limits.clearReviewToday() }
        case (.retention, .preset): if let value { config.desiredRetention = Float(value) }
        case (.retention, _):
            if let value { limits.desiredRetention = Float(value) } else { limits.clearDesiredRetention() }
        }
    }

    // MARK: Saving

    var isModified: Bool { snapshot() != original }

    func save(mode: Anki_DeckConfig_UpdateDeckConfigsMode = .normal) async throws {
        let request = request(mode: mode)
        _ = try await backend.perform { try $0.updateDeckConfigs(request) }
        markSaved()
    }

    func markSaved() {
        original = snapshot()
    }

    func request(mode: Anki_DeckConfig_UpdateDeckConfigsMode) -> Anki_DeckConfig_UpdateDeckConfigsRequest {
        var request = Anki_DeckConfig_UpdateDeckConfigsRequest()
        request.targetDeckID = deckID
        // New and changed presets, then the selected one, which the deck uses
        // because it comes last.
        request.configs = presets.indices
            .filter { $0 != selectedIndex && (presets[$0].config.id == 0 || modifiedIDs.contains(presets[$0].config.id)) }
            .map { presets[$0].config } + [preset]
        request.removedConfigIds = removedIDs
        request.mode = mode
        request.cardStateCustomizer = cardStateCustomizer
        request.limits = limits
        request.newCardsIgnoreReviewLimit = newCardsIgnoreReviewLimit
        request.applyAllParentLimits = applyAllParentLimits
        request.fsrs = fsrs
        request.fsrsReschedule = fsrsReschedule
        request.fsrsHealthCheck = fsrsHealthCheck
        return request
    }

    // MARK: Helpers

    private struct Snapshot: Equatable {
        var presets: [DeckConfig]
        var selectedID: Int64
        var selectedName: String
        var limits: DeckLimits
        var cardStateCustomizer: String
        var newCardsIgnoreReviewLimit: Bool
        var applyAllParentLimits: Bool
        var fsrs: Bool
        var fsrsReschedule: Bool
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            presets: presets.map(\.config), selectedID: preset.id, selectedName: preset.name, limits: limits,
            cardStateCustomizer: cardStateCustomizer, newCardsIgnoreReviewLimit: newCardsIgnoreReviewLimit,
            applyAllParentLimits: applyAllParentLimits, fsrs: fsrs, fsrsReschedule: fsrsReschedule)
    }

    private func markModified() {
        if preset.id != 0 { modifiedIDs.insert(preset.id) }
    }

    private func uniqueName(_ name: String) -> String {
        presets.contains { $0.config.name == name } ? name + String(Int(Date().timeIntervalSince1970)) : name
    }

    private func sortPresets() {
        let selected = preset.name
        presets.sort { $0.config.name.localizedCaseInsensitiveCompare($1.config.name) == .orderedAscending }
        selectedIndex = presets.firstIndex { $0.config.name == selected } ?? 0
    }

    /// What desktop's components fix up when a preset is first shown: seven
    /// easy-day percentages, a date for "ignore reviews before", and a valid
    /// new card sort order.
    private static func normalise(_ config: inout DeckConfigInner, defaults: DeckConfigInner) {
        if config.easyDaysPercentages.count != 7 { config.easyDaysPercentages = defaults.easyDaysPercentages }
        if config.ignoreRevlogsBeforeDate.isEmpty { config.ignoreRevlogsBeforeDate = "1970-01-01" }
        if case .UNRECOGNIZED = config.newCardSortOrder { config.newCardSortOrder = .template }
        if disabledSortOrders(for: config.newCardGatherPriority).contains(config.newCardSortOrder) {
            config.newCardSortOrder = .template
        }
    }

    /// Sort orders that repeat another one for this gather order.
    static func disabledSortOrders(
        for gather: DeckConfigInner.NewCardGatherPriority
    ) -> [DeckConfigInner.NewCardSortOrder] {
        switch gather {
        case .randomNotes: [.templateThenRandom, .randomNoteThenTemplate]
        case .randomCards: [.templateThenRandom, .randomNoteThenTemplate, .randomCard]
        default: []
        }
    }
}

/// The FSRS parameters in force: the newest set the preset has.
extension DeckConfigInner {
    var fsrsParams: [Float] {
        !fsrsParams6.isEmpty ? fsrsParams6 : !fsrsParams5.isEmpty ? fsrsParams5 : fsrsParams4
    }
}

/// Learning steps as typed in desktop: "1m 10m 1d", stored in minutes.
nonisolated enum LearningSteps {
    private static let units: [(suffix: String, seconds: Double)] = [
        ("d", 86_400), ("h", 3_600), ("m", 60), ("s", 1),
    ]

    static func format(_ steps: [Float]) -> String {
        steps.map(format).joined(separator: " ")
    }

    private static func format(_ minutes: Float) -> String {
        let seconds = Double(minutes) * 60
        // The largest unit that divides the step evenly, as desktop's
        // naturalWholeUnit, with months and years shown as days.
        let start = units.firstIndex { seconds >= $0.seconds } ?? units.count - 1
        for unit in units[start...] {
            let amount = (seconds / unit.seconds).rounded()
            if abs(seconds - amount * unit.seconds) < .ulpOfOne || unit.suffix == "s" {
                return "\(Int(amount))\(unit.suffix)"
            }
        }
        return "\(Int(seconds))s"
    }

    static func parse(_ text: String) -> [Float] {
        text.split(separator: " ").compactMap { word in
            guard let match = word.firstMatch(of: /(\d+)(.*)/), let number = Double(match.1) else { return nil }
            let unit = units.first { $0.suffix == String(match.2) }?.seconds ?? 60
            // Must fit a negative i32 of seconds in the review log.
            let seconds = min(number * unit, Double(1 << 31))
            return seconds == 0 ? nil : Float(seconds / 60)
        }
    }
}
