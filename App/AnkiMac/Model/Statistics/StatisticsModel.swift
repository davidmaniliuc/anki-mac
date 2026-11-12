import AnkiKit
import Foundation
import Observation

/// What the Statistics window covers: the current deck, the whole
/// collection, or a search, as desktop's radio buttons and search box.
enum StatisticsScope: Hashable {
    case deck, collection, search
}

/// The switches under each graph, with desktop's starting values. They live
/// here rather than in the views so a saved PDF shows what is on screen.
struct GraphControls {
    var futureDueRange = GraphRange.month
    var reviewsRange = GraphRange.month
    var reviewsShowTime = false
    var calendarYear = Calendar.current.component(.year, from: .now)
    var intervalsRange = IntervalRange.percentile95
    var stabilityRange = IntervalRange.percentile95
    var difficultyRange = PercentageRange.all
    var retrievabilityRange = PercentageRange.all
    var trueRetentionMode = TrueRetentionGraph.Mode.summary
    var hoursRange = GraphRange.year
    var buttonsRange = GraphRange.year
    var addedRange = GraphRange.month

    /// Reviews, Hourly Breakdown and Answer Buttons follow the history
    /// switch, and the calendar can't go back past the history fetched.
    mutating func follow(_ history: RevlogHistory) {
        reviewsRange = reviewsRange.following(history)
        hoursRange = hoursRange.following(history)
        buttonsRange = buttonsRange.following(history)
        let years = CalendarGraph.years(history, current: Calendar.current.component(.year, from: .now))
        calendarYear = min(max(calendarYear, years.lowerBound), years.upperBound)
    }
}

/// The Statistics window's state: its scope and history range, the graph
/// preferences shared with desktop, and the backend's data for them.
@Observable
final class StatisticsModel {
    var scope: StatisticsScope = .deck {
        didSet {
            guard scope != oldValue else { return }
            // The box shows the search in use, as desktop's.
            switch scope {
            case .deck: searchText = "deck:current"
            case .collection: searchText = ""
            case .search: break
            }
            reload()
        }
    }
    /// The search box. Typing doesn't reload; `submitSearch` does.
    var searchText = "deck:current"
    var history: RevlogHistory = .year {
        didSet {
            guard history != oldValue else { return }
            controls.follow(history)
            reload()
        }
    }
    var controls = GraphControls()
    /// Desktop's graph preferences, saved to the collection on change.
    var preferences = Anki_Stats_GraphPreferences() {
        didSet { if preferences != oldValue, preferencesLoaded { savePreferences() } }
    }
    private(set) var data: GraphsResponse?
    private(set) var loading = false
    var errorMessage: String?

    @ObservationIgnored private let backend: AnkiBackend
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesLoaded = false

    init(backend: AnkiBackend) {
        self.backend = backend
    }

    /// The search the backend is given, as desktop's: `deck:current`, the
    /// empty search for the collection, or the box's text.
    var search: String {
        switch scope {
        case .deck: "deck:current"
        case .collection: ""
        case .search: searchText
        }
    }

    func submitSearch() {
        if scope == .search { reload() } else { scope = .search }
    }

    /// Reads the preferences, then the graphs. Called when the window opens
    /// or is shown again for another deck.
    func load() {
        loadTask?.cancel()
        loadTask = Task {
            if !preferencesLoaded, let loaded = try? await backend.perform({ try $0.getGraphPreferences() }) {
                preferences = loaded
                preferencesLoaded = true
            }
            await fetch()
        }
    }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { await fetch() }
    }

    private func fetch() async {
        var request = Anki_Stats_GraphsRequest()
        request.search = search
        request.days = history.days
        loading = true
        do {
            let response = try await backend.perform { [request] in try $0.graphs(request) }
            guard !Task.isCancelled else { return }
            data = response
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = ActionFailure.reason(error)
        }
        loading = false
    }

    private func savePreferences() {
        let preferences = preferences
        Task { try? await backend.perform { try $0.setGraphPreferences(preferences) } }
    }
}
