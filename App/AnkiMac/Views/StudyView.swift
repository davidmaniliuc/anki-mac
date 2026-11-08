import AppKit
import SwiftUI

/// The card, with the answer controls under it. Keyboard: Space shows the
/// answer, 1–4 rate it, Ctrl+1 to Ctrl+7 flag it, * marks the note (see StudyCommands, which also puts every action in
/// the menu bar).
///
/// This view stays in the window for the app's lifetime, hidden while no
/// session is running, so the card web view is attached once, not every time
/// studying starts.
struct StudyView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let session: StudySession?
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if model.reviewerReady, let webView = model.reviewer.webView {
                    CardWebView(webView: webView)
                        .frame(minHeight: Theme.Study.cardMinHeight)
                } else {
                    Color.clear
                }
                AnswerBar(session: session)
            }
            if session?.phase == .finished {
                ContentUnavailableView {
                    Label("Congratulations!", systemImage: "checkmark.circle")
                } description: {
                    Text("You have finished this deck for now.")
                } actions: {
                    Button("Back to Deck") { model.stopStudying() }
                        .keyboardShortcut(.defaultAction)
                }
                .background(.background)
            }
        }
        .opacity(session == nil ? 0 : 1)
        .allowsHitTesting(session != nil)
        .accessibilityHidden(session == nil)
        // Fixed items, only enabled or disabled: when NSToolbar adds,
        // removes or resizes items it re-lays out the window (~35-45 ms),
        // which used to land on the first card.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Undo", systemImage: "arrow.uturn.backward") { session?.undo() }
                    .disabled(!(session?.canUndo ?? false))
                Button("End Session", systemImage: "xmark") { model.stopStudying() }
                    .disabled(session == nil)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding { session?.errorMessage != nil } set: { if !$0 { session?.errorMessage = nil } }
        ) {
            Button("OK") {}
        } message: {
            Text(session?.errorMessage ?? "")
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            model.reviewer.setNightMode(scheme == .dark)
        }
        .onChange(of: session == nil, initial: true) { _, idle in
            if idle {
                if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                keyMonitor = nil
            } else if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handleKey(event) ? nil : event
                }
            }
        }
    }

    /// The web view takes plain keys before the menu bar sees them, so the
    /// Study menu's single-key shortcuts are handled here first. Keys pass
    /// through while a text box (type-in-the-answer) has focus.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let session, let window = event.window, window.isKeyWindow else { return false }
        let responder = window.firstResponder
        if responder is NSText || (responder === model.reviewer.webView && model.reviewer.isEditingText) {
            return false
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        let key = event.charactersIgnoringModifiers ?? ""
        if modifiers == .command, key == "z" {
            session.undo()
            return true
        }
        if modifiers == .control, let digit = Int(key), let flag = CardFlag(rawValue: digit), flag != .none {
            session.toggleFlag(flag)
            return true
        }
        guard modifiers.isEmpty else { return false }

        switch (session.phase, key) {
        case (.question, " "), (.question, "\r"):
            session.showAnswer()
        // As desktop: Space or Return on the answer means Good.
        case (.answer, " "), (.answer, "\r"):
            session.answer(.good)
        case (.answer, "1"), (.answer, "2"), (.answer, "3"), (.answer, "4"):
            session.answer(Rating(rawValue: Int(key)! - 1)!)
        case (.question, "r"), (.answer, "r"):
            session.replayAudio()
        case (.question, "*"), (.answer, "*"):
            session.toggleMark()
        case (_, "\u{1b}"):
            model.stopStudying()
        default:
            return false
        }
        return true
    }
}

/// Show Answer, then Again / Hard / Good / Easy with their next intervals.
///
/// This sits at the bottom of the window, against the HIG's advice to keep
/// controls off the bottom edge: it follows the reading order (question,
/// answer, decision) that every Anki client uses, and every action is also
/// in the Study menu with a single-key shortcut.
private struct AnswerBar: View {
    let session: StudySession?

    var body: some View {
        // Counts on the leading side; the buttons stay centred in the window.
        HStack(spacing: Theme.Spacing.medium) {
            Group {
                if let session {
                    DueCounts(
                        new: session.counts.new, learn: session.counts.learn, review: session.counts.review,
                        highlighted: session.currentQueue)
                        .font(Theme.Fonts.studyCounts)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Theme.Spacing.medium) {
                buttons
            }
            // In a narrow window the buttons keep their room; the side columns give way.
            .layoutPriority(1)
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
        }
        .controlSize(.large)
        .padding(.vertical, Theme.Study.barPadding)
        .padding(.horizontal, Theme.Spacing.large)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var buttons: some View {
        switch session?.phase ?? .loading {
        case .question:
            Button { session?.showAnswer() } label: {
                Text("Show Answer").frame(minWidth: Theme.Study.answerButtonWidth * 2)
            }
            .buttonStyle(.borderedProminent)
        case .answer:
            if let session {
                ForEach(Rating.allCases, id: \.self) { rating in
                    AnswerButton(
                        rating: rating,
                        interval: session.card?.intervals[safe: rating.rawValue] ?? "",
                        session: session)
                }
            }
        case .loading, .finished:
            // Keeps the bar's height while the next card loads.
            Button("Show Answer") {}.hidden()
        }
    }
}

private struct AnswerButton: View {
    let rating: Rating
    let interval: String
    let session: StudySession

    var body: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            Text(interval)
                .font(Theme.Fonts.intervalCaption)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.secondary)
            let button = Button { session.answer(rating) } label: {
                Text(rating.title)
                    .frame(minWidth: Theme.Study.answerButtonMinWidth, maxWidth: Theme.Study.answerButtonWidth)
            }
            // Good is what most answers are, so it is the one prominent button.
            if rating == .good {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rating.title), next review in \(interval)")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
