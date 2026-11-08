import AppKit
import Foundation

/// Drives the app through the bench scenario when launched with
/// `-BenchEventsPath <file>`, writing the same event file as desktop's
/// bench/anki_bench_addon so bench/run_app.py can compare the two.
///
/// Scenario: deck list painted → idle (memory sampled by the harness) →
/// study the top-level deck with the most due cards, 30 × Good → quit.
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
    private static let idleSettle = Duration.seconds(4)
    private static let idleSample = Duration.seconds(3)

    private let model: CollectionModel
    private let path: URL
    private var events: [String: Double] = [:]
    private var answerMs: [Double] = []
    private var phase = "starting"
    private var studyEnd: String?
    private var answered = 0
    private var pendingAnswer: Double?

    init(model: CollectionModel, path: String) {
        self.model = model
        self.path = URL(fileURLWithPath: path)
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
            quit()
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
        var state: [String: Any] = ["events": merged, "answer_ms": answerMs, "phase": phase]
        if let studyEnd { state["study_end"] = studyEnd }
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        try? data.write(to: path, options: .atomic)
    }
}

private extension Dictionary {
    func mapKeys(_ transform: (Key) -> Key) -> Self {
        Dictionary(uniqueKeysWithValues: map { (transform($0.key), $0.value) })
    }
}
