import AppKit
import Foundation

/// Drives the app through the bench scenario when launched with
/// `-BenchEventsPath <file>`, writing the same event file as desktop's
/// bench/anki_bench_addon so bench/run_app.py can compare the two.
///
/// Scenario: deck list painted → idle (memory sampled by the harness) →
/// study the top-level deck with the most due cards, 30 × Good → open the
/// browser and time three searches → quit.
final class BenchDriver {
    /// Timestamps from inside the app (launch, collection open, first card
    /// render…), merged into the event file to break the totals down.
    private static var trace: [String: Double] = [:]
    private static let isActive = UserDefaults.standard.string(forKey: "BenchEventsPath") != nil

    static func trace(_ name: String) {
        guard isActive, trace[name] == nil else { return }
        trace[name] = Date().timeIntervalSince1970
    }

    private static let answers = 30
    private static let searches = ["deck:*", "is:due", "front:*a*"]
    private static weak var current: BenchDriver?
    private static let idleSettle = Duration.seconds(4)
    private static let idleSample = Duration.seconds(3)

    private let model: CollectionModel
    private let path: URL
    private var events: [String: Double] = [:]
    private var answerMs: [Double] = []
    private var phase = "starting"
    private var studyEnd: String?
    private var browserEnd: String?
    private var answered = 0
    private var pendingAnswer: Double?
    private var browser: BrowserModel?
    private var searchMs: [String: Double] = [:]
    private var browserRows: Int?
    /// The search being timed, and the ids version on screen when it started:
    /// only a paint of a newer version is its result. Version 0 is the empty
    /// table drawn before the browser's first search returns.
    private var pendingSearch: (query: String, start: Double, after: Int)?
    private var shownAfter = 0

    init(model: CollectionModel, path: String) {
        self.model = model
        self.path = URL(fileURLWithPath: path)
        Self.current = self
    }

    /// Call once the collection is open and the deck list is in the model.
    func run() {
        // Let SwiftUI lay out the sidebar and the window draw it.
        DispatchQueue.main.async { [self] in
            NSApp.windows.forEach { $0.displayIfNeeded() }
            mark("deck_browser_painted")
            Task {
                try? await Task.sleep(for: Self.idleSettle)
                phase = "idle"
                flush()
                try? await Task.sleep(for: Self.idleSample)
                startStudy()
            }
        }
    }

    private func startStudy() {
        phase = "study"
        guard let best = model.decks.max(by: { $0.dueCount < $1.dueCount }), best.dueCount > 0 else {
            studyEnd = "no due cards"
            quit()
            return
        }
        model.selectedDeckID = best.id
        mark("study_start")
        model.startStudying()
        model.session?.onDisplayed = { [weak self] phase in self?.displayed(phase) }
    }

    private func displayed(_ shown: StudySession.Phase) {
        let now = Date().timeIntervalSince1970
        switch shown {
        case .question:
            if events["study_first_question"] == nil {
                mark("study_first_question")
            } else if let pendingAnswer {
                answerMs.append((now - pendingAnswer) * 1000)
            }
            pendingAnswer = nil
            if answered >= Self.answers {
                finishStudy("done")
            } else {
                model.session?.showAnswer()
            }
        case .answer:
            answered += 1
            pendingAnswer = now
            model.session?.answer(.good)
        case .finished:
            finishStudy(answered == 0 ? "no cards" : "ran out of cards")
        case .loading:
            break
        }
    }

    private func finishStudy(_ reason: String) {
        guard studyEnd == nil else { return }
        studyEnd = reason
        model.session?.onDisplayed = nil
        model.stopStudying()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            startBrowser()
        }
    }

    // MARK: Browser

    /// As the desktop add-on: from asking for the browser to its first
    /// search's rows on screen, then each search from submitting it to its
    /// rows on screen.
    private func startBrowser() {
        phase = "browser"
        mark("browser_open_start")
        BrowserWindowController.show(collection: model)
    }

    static func browserOpened(_ browser: BrowserModel) {
        current?.attach(browser)
    }

    private func attach(_ browser: BrowserModel) {
        guard phase == "browser", self.browser == nil else { return }
        self.browser = browser
        browser.onRowsPainted = { [weak self] version, laidOut in self?.rowsPainted(version: version, laidOut: laidOut) }
    }

    private func rowsPainted(version: Int, laidOut: Int) {
        guard let browser else { return }
        guard version > (pendingSearch?.after ?? shownAfter) else { return }
        let now = Date().timeIntervalSince1970
        if events["browser_shown"] == nil {
            mark("browser_shown")
        } else if let pendingSearch {
            searchMs[pendingSearch.query] = (now - pendingSearch.start) * 1000
            browserRows = browser.ids.count
        }
        // A paint that laid out no rows for a non-empty result would mean the
        // number timed an empty table.
        if !browser.ids.isEmpty && laidOut == 0 {
            browserEnd = "painted no rows"
        }
        guard let next = Self.searches.dropFirst(searchMs.count).first else {
            pendingSearch = nil
            browser.onRowsPainted = nil
            flush()
            BrowserWindowController.current?.close()
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                quit()
            }
            return
        }
        pendingSearch = (next, Date().timeIntervalSince1970, browser.idsVersion)
        if UserDefaults.standard.bool(forKey: "XNoField") {
            browser.search(text: next)
        } else {
            browser.searchText = next
            browser.search()
        }
    }

    private func quit() {
        phase = "quitting"
        mark("quit_requested")
        NSApp.terminate(nil)
    }

    private func mark(_ name: String) {
        if events[name] == nil { events[name] = Date().timeIntervalSince1970 }
        flush()
    }

    private func flush() {
        let merged = events.merging(Self.trace.mapKeys { "trace_\($0)" }) { event, _ in event }
        var state: [String: Any] = ["events": merged, "answer_ms": answerMs, "phase": phase, "search_ms": searchMs]
        if let studyEnd { state["study_end"] = studyEnd }
        if let browserRows { state["browser_rows"] = browserRows }
        if let browserEnd { state["browser_end"] = browserEnd }
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        try? data.write(to: path, options: .atomic)
    }
}

private extension Dictionary {
    func mapKeys(_ transform: (Key) -> Key) -> Self {
        Dictionary(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
