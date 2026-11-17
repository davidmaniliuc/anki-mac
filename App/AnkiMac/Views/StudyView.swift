import AppKit
import SwiftUI

/// The card, with the answer controls under it. Keyboard: Space shows the
/// answer, 1–4 rate it, Ctrl+1 to Ctrl+7 flag it, * marks the note, B opens
/// the browser, M opens the card's menu (see StudyCommands and CardCommands,
/// which also put every action in the menu bar).
///
/// This view stays in the window for the app's lifetime, hidden while no
/// session is running, so the card web view is attached once, not every time
/// studying starts.
struct StudyView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.compact) private var compact
    let session: StudySession?
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                card
                if let session, session.phase == .finished {
                    SessionFinished(session: session)
                }
            }
            AnswerBar(session: session)
        }
        .background(Theme.Palette.canvas)
        .overlay(alignment: .topLeading) {
            if let session, session.phase != .finished {
                SessionTitle(session: session)
            }
        }
        .pageActions(shown: session != nil) { actions }
        .opacity(session == nil ? 0 : 1)
        .allowsHitTesting(session != nil)
        .accessibilityHidden(session == nil)
        .alert(failureTitle, isPresented: failureShown) {
            Button("OK") {}
        } message: {
            Text(verbatim: session?.failure?.detail ?? "")
        }
        .alert(
            session?.timeboxMessage ?? "",
            isPresented: Binding { session?.timeboxMessage != nil } set: { _ in }
        ) {
            Button(Tr.studyingContinue) { session?.continueAfterTimebox() }
                .keyboardShortcut(.defaultAction)
            Button(Tr.studyingFinish) { model.stopStudying() }
        }
        .overlay(alignment: .bottom) {
            if let feedback = session?.feedback {
                Text(feedback)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, Theme.Study.feedbackBottomInset)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.default, value: session?.feedback)
        .sheet(item: Binding { session?.prompt } set: { session?.prompt = $0 }) { prompt in
            if let session { StudyPromptSheet(prompt: prompt, session: session) }
        }
        .sheet(item: Binding { session?.editor } set: { if $0 == nil { session?.finishEditing(save: false) } }) { editor in
            if let session { StudyEditSheet(model: editor, session: session) }
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            model.reviewer.setNightMode(scheme == .dark)
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                handleKey(event) ? nil : event
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    /// The failed action's alert: what didn't happen, then why.
    private var failureTitle: String { session?.failure?.title ?? "" }

    private var failureShown: Binding<Bool> {
        Binding { session?.failure != nil } set: { if !$0 { session?.failure = nil } }
    }

    /// The card, straight on the canvas in the reading column. Its page
    /// paints the canvas colour (Theme.Palette.canvasHex), so there is no
    /// box around it, as desktop draws none.
    @ViewBuilder private var card: some View {
        Group {
            if model.reviewerReady, let webView = model.reviewer.webView {
                CardWebView(webView: webView)
                    .contextMenu {
                        reviewerActions
                    }
                    .overlay(alignment: .top) {
                        if let card = session?.card, session?.phase != .finished {
                            // The toolbar's flag button shows the flag unless
                            // a small window folds it into More.
                            CardIndicators(flag: compact ? card.flag : .none, isMarked: card.isMarked)
                        }
                    }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: Theme.Study.cardMaxWidth, minHeight: Theme.Study.cardMinHeight)
        .padding(.horizontal, compact ? Theme.Study.compactMargin : Theme.Study.margin)
        .padding(.top, compact ? Theme.Spacing.xSmall : Theme.Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Undo and End stay in view; Edit and Flag fold into More in a small window.
    private var actions: some View {
        HStack(spacing: 0) {
            let undoState = session?.undoState ?? UndoState()
            IconButton(
                "arrow.uturn.backward", help: undoState.canUndo ? undoState.undoTitle : "Undo",
                shortcut: undoState.canUndo ? Tr.actionsShortcutKey(val: "U") : nil
            ) {
                session?.undo()
            }
            .disabled(!undoState.canUndo)
            if !compact, let session {
                IconButton("pencil", help: "Edit Note", shortcut: Tr.actionsShortcutKey(val: "E")) {
                    session.editCurrentNote()
                }
                Menu {
                    flagItems(session)
                } label: {
                    Image(systemName: session.card.map { $0.flag == .none ? "flag" : "flag.fill" } ?? "flag")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(session.card.map { Theme.flagColor($0.flag) } ?? Theme.Palette.secondary)
                        .frame(width: 30, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(QuietButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Tr.studyingFlagCard)
            }
            Menu {
                reviewerActions
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.button)
            .buttonStyle(QuietButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More (M)")
            IconButton("xmark", help: "End Session", shortcut: Tr.actionsShortcutKey(val: "\u{238B}")) { model.stopStudying() }
        }
    }

    @ViewBuilder private func flagItems(_ session: StudySession) -> some View {
        ForEach(CardFlag.assignable, id: \.self) { flag in
            Toggle(flag.title, isOn: Binding { session.card?.flag == flag } set: { _ in session.toggleFlag(flag) })
                .keyboardShortcut(KeyEquivalent(Character("\(flag.rawValue)")), modifiers: .control)
        }
    }

    /// The web view takes plain keys before the menu bar sees them, so the
    /// Study menu's single-key shortcuts are handled here first. Keys pass
    /// through while a text box (type-in-the-answer) has focus.
    private func handleKey(_ event: NSEvent) -> Bool {
        // Only the main window, which holds the card view; the browser has its own keys.
        guard let window = event.window, window.isKeyWindow, window === model.reviewer.webView?.window else {
            return false
        }
        let responder = window.firstResponder
        if responder is NSText || (responder === model.reviewer.webView && model.reviewer.isEditingText) {
            return false
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        let key = event.charactersIgnoringModifiers ?? ""
        // Desktop's single-key shortcut, kept for muscle memory beside the menu's Shift-Command-B.
        if modifiers.isEmpty, key == "b" {
            BrowserWindowController.show(collection: model)
            return true
        }
        // And "o" for the current deck's options, in the overview and while studying.
        if modifiers.isEmpty, key == "o", let deck = model.selectedDeck {
            model.showOptions(deck)
            return true
        }
        // "/", desktop's Study Deck key, and Command-F open Quick Find, from Today, the overview and a session.
        if (modifiers.isEmpty && key == "/") || (modifiers == .command && key == "f"), model.isLoaded {
            model.quickFindPresented = true
            return true
        }
        // "f" creates a filtered deck; in a filtered deck's overview, "r" rebuilds and "e" empties it.
        if modifiers.isEmpty, key == "f" {
            model.editFilteredDeck()
            return true
        }
        // In the overview, "c" opens Custom Study and "u" unburies, as desktop.
        if modifiers.isEmpty, session == nil, let deck = model.selectedDeck, key == "c" || key == "u" {
            if key == "c" { model.showCustomStudy(deck.id) } else { model.askUnbury(deck.id) }
            return true
        }
        if modifiers.isEmpty, session == nil, let deck = model.selectedDeck, deck.filtered, key == "r" || key == "e" {
            if key == "r" { model.rebuildFilteredDeck(deck.id) } else { model.emptyFilteredDeck(deck.id) }
            return true
        }
        guard let session else { return false }
        // The end of a session is desktop's congratulations screen, where "c" is Custom Study.
        if modifiers.isEmpty, session.phase == .finished, key == "c", model.deck(session.deckID)?.filtered == false {
            model.showCustomStudy(session.deckID)
            return true
        }
        // Caps Lock changes the letter too, so Shift is read from the flags.
        let shift = event.modifierFlags.contains(.shift)
        if modifiers.isEmpty, key.lowercased() == "v" {
            if shift { session.recordVoice() } else { session.replayVoice() }
            return true
        }
        if modifiers.isEmpty, shift, key.lowercased() == "a" { session.toggleAutoAdvance(); return true }
        if modifiers.isEmpty, key == "m" { showContextMenu(in: window); return true }
        if modifiers.isEmpty, key == "u" { session.undo(); return true }
        if modifiers.isEmpty, key == "e" { session.editCurrentNote(); return true }
        if modifiers.isEmpty, key == "@" { session.suspendCurrentCard(); return true }
        if modifiers.isEmpty, key == "!" { session.suspendCurrentNote(); return true }
        if modifiers.isEmpty, key == "-" { session.buryCurrentCard(); return true }
        if modifiers.isEmpty, key == "=" { session.buryCurrentNote(); return true }
        if modifiers == [.command, .option], key == "n" { session.askForget(); return true }
        // Desktop's Ctrl+Alt+E and Ctrl+Backspace, with Command for Ctrl as on its Mac build.
        if modifiers == [.command, .option], key == "e" { session.createCopy(in: model); return true }
        if modifiers == .command, event.keyCode == 51 { session.deleteCurrentNote(); return true }
        if modifiers == [.command, .shift], key == "d" { session.askSetDueDate(); return true }
        if modifiers.isEmpty, key == "i" { session.showCardInfo(in: model); return true }
        if modifiers == .command, key == "z" {
            session.undo()
            return true
        }
        if modifiers == .control, let digit = Int(key), let flag = CardFlag(rawValue: digit), flag != .none {
            session.toggleFlag(flag)
            return true
        }
        guard modifiers.isEmpty else { return false }
        if session.phase == .answer, !key.isEmpty, let rating = Rating.allCases.first(where: { AnswerKeys.key($0) == key }) {
            session.answer(rating)
            return true
        }

        switch (session.phase, key) {
        case (.question, " "), (.question, "\r"):
            session.showAnswer()
        // As desktop: Space or Return on the answer means Good, unless
        // that's turned off in Settings.
        case (.answer, " "), (.answer, "\r"):
            if AnswerKeys.spaceAnswers { session.answer(.good) }
        case (.question, "r"), (.answer, "r"):
            session.replayAudio()
        case (.question, "5"), (.answer, "5"):
            session.toggleAudioPause()
        case (.question, "6"), (.answer, "6"):
            session.seekAudio(by: -5)
        case (.question, "7"), (.answer, "7"):
            session.seekAudio(by: 5)
        case (.question, "*"), (.answer, "*"):
            session.toggleMark()
        case (_, "\u{1b}"):
            model.stopStudying()
        default:
            return false
        }
        return true
    }

    /// Desktop's M: the card's context menu, at the pointer when it is over
    /// the card, else in the card's middle. A right click is sent there, so
    /// the menu opens the same way as for a real one.
    private func showContextMenu(in window: NSWindow) {
        guard let webView = model.reviewer.webView else { return }
        let card = webView.convert(webView.bounds, to: nil)
        var location = window.mouseLocationOutsideOfEventStream
        if !card.contains(location) { location = NSPoint(x: card.midX, y: card.midY) }
        guard let click = NSEvent.mouseEvent(
            with: .rightMouseDown, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { return }
        window.sendEvent(click)
    }

    /// Desktop's reviewer menu in its order, with its shortcuts, after Copy
    /// (from its web view's own menu) and Edit (its E key).
    @ViewBuilder private var reviewerActions: some View {
        if let session {
            if session.hasSelection {
                Button(Tr.actionsCopy) { session.copySelection() }
                Divider()
            }
            Button("Edit Note…") { session.editCurrentNote() }
                .keyboardShortcut("e", modifiers: [])
            Divider()
            Menu(Tr.studyingFlagCard) {
                flagItems(session)
            }
            Button(Tr.studyingBuryCard) { session.buryCurrentCard() }
                .keyboardShortcut("-", modifiers: [])
            Button(Tr.actionsWithEllipsis(action: Tr.actionsForgetCard)) { session.askForget() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button(Tr.actionsWithEllipsis(action: Tr.actionsSetDueDate)) { session.askSetDueDate() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button(Tr.actionsReposition + "…") { session.askReposition() }
                .disabled(!session.canReposition)
            Button(Tr.actionsSuspendCard) { session.suspendCurrentCard() }
                .keyboardShortcut("@", modifiers: [])
            Button(Tr.actionsOptions) { if let deck = model.selectedDeck { model.showOptions(deck) } }
                .keyboardShortcut("o", modifiers: [])
            Button(Tr.actionsCardInfo) { session.showCardInfo(in: model) }
                .keyboardShortcut("i", modifiers: [])
            Divider()
            Toggle(Tr.studyingMarkNote, isOn: Binding { session.card?.isMarked ?? false } set: { _ in session.toggleMark() })
                .keyboardShortcut("*", modifiers: [])
            Button(Tr.studyingBuryNote) { session.buryCurrentNote() }
                .keyboardShortcut("=", modifiers: [])
            Button(Tr.studyingSuspendNote) { session.suspendCurrentNote() }
                .keyboardShortcut("!", modifiers: [])
            Button(Tr.actionsWithEllipsis(action: Tr.actionsCreateCopy)) { session.createCopy(in: model) }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Button(Tr.studyingDeleteNote) { session.deleteCurrentNote() }
                .keyboardShortcut(.delete)
            Divider()
            Button(Tr.actionsReplayAudio) { session.replayAudio() }
                .keyboardShortcut("r", modifiers: [])
            Button(Tr.studyingPauseAudio) { session.toggleAudioPause() }
                .keyboardShortcut("5", modifiers: [])
            Button(Tr.studyingAudio5s) { session.seekAudio(by: -5) }
                .keyboardShortcut("6", modifiers: [])
            Button(Tr.studyingAudioAnd5s) { session.seekAudio(by: 5) }
                .keyboardShortcut("7", modifiers: [])
            Button(Tr.studyingRecordOwnVoice) { session.recordVoice() }
                .keyboardShortcut("v", modifiers: .shift)
            Button(Tr.studyingReplayOwnVoice) { session.replayVoice() }
                .keyboardShortcut("v", modifiers: [])
            Toggle(Tr.actionsAutoAdvance, isOn: Binding { session.autoAdvance } set: { _ in session.toggleAutoAdvance() })
                .keyboardShortcut("a", modifiers: .shift)
        }
    }
}

/// The marked star at the top left of the card's column and the flag at the
/// top right, where desktop draws them inside the page. Study and the
/// browser's previewer show it.
struct CardIndicators: View {
    let flag: CardFlag
    let isMarked: Bool

    var body: some View {
        HStack {
            if isMarked {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.Palette.secondary)
                    .accessibilityLabel("Marked")
            }
            Spacer()
            if flag != .none {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Theme.flagColor(flag))
                    .accessibilityLabel("\(flag.title) Flag")
            }
        }
        .font(.title2)
        .padding(Theme.Spacing.medium)
        .allowsHitTesting(false)
        .animation(.default, value: isMarked)
        .animation(.default, value: flag)
    }
}

/// The deck's name in the title bar, lined up with the card's left edge,
/// after its parent decks when they fit, then the session's counts with the
/// current card's queue underlined. With the sidebar put away it starts no
/// sooner than past the window controls and the sidebar button; it stops
/// short of the actions.
private struct SessionTitle: View {
    @Environment(CollectionModel.self) private var model
    @Environment(WindowLayout.self) private var layout
    @Environment(\.compact) private var compact
    let session: StudySession

    var body: some View {
        if let deck = model.deck(session.deckID) {
            let parents = deck.fullName.components(separatedBy: "::").dropLast().joined(separator: " › ")
            let clear = !layout.sidebarVisible || layout.sidebarFloats
                ? Theme.Study.titleControlsInset : Theme.Spacing.large
            GeometryReader { proxy in
                let margin = compact ? Theme.Study.compactMargin : Theme.Study.margin
                let cardEdge = max(margin, (proxy.size.width - Theme.Study.cardMaxWidth) / 2)
                let leading = max(clear, cardEdge)
                HStack(spacing: Theme.Spacing.medium) {
                    ViewThatFits(in: .horizontal) {
                        if !parents.isEmpty {
                            HStack(spacing: 5) {
                                Text(parents).foregroundStyle(Theme.Palette.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.Palette.tertiary)
                                Text(deck.name)
                            }
                        }
                        Text(deck.name).truncationMode(.tail)
                    }
                    .font(Theme.Fonts.studyTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    DueCounts(
                        new: session.counts.new, learn: session.counts.learn, review: session.counts.review,
                        highlighted: session.currentQueue)
                        .font(Theme.Fonts.studyCounts)
                        .fixedSize()
                }
                .frame(maxWidth: max(0, proxy.size.width - leading - Theme.Study.titleActionsInset), alignment: .leading)
                // The page starts under the title bar; the row moves up into
                // it, centred on the bar's height.
                .frame(height: proxy.safeAreaInsets.top)
                .offset(y: -proxy.safeAreaInsets.top)
                .padding(.leading, leading)
            }
            .allowsHitTesting(false)
        }
    }
}

/// The end of a session, as a page: upstream's congratulations for its
/// title, what the session did, and what desktop's congratulations screen
/// adds (learning cards still to come, limits reached, Custom Study and
/// Unbury, the deck's description).
private struct SessionFinished: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: StudySession
    @State private var ticked = false

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                PageTitle(eyebrow: deckPath, title: Tr.schedulingCongratulationsFinished, lineLimit: nil) {
                    Image(systemName: "checkmark.circle")
                        .font(Theme.Fonts.titleSymbol)
                        .foregroundStyle(Theme.Palette.text)
                        // The tick draws itself once, as the page appears.
                        .symbolEffect(.drawOn, isActive: !ticked)
                        .accessibilityHidden(true)
                }
                if let summary {
                    Text(summary).font(Theme.Fonts.lead).foregroundStyle(Theme.Palette.secondary)
                }
            }

            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    ForEach(notes, id: \.self) { Text($0) }
                }
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: Theme.Overview.descriptionWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }

            ActionRow { backButton } secondary: { actions }

            if let description = session.congratsDescription {
                Text(description)
                    .font(Theme.Fonts.lead)
                    .foregroundStyle(Theme.Palette.secondary)
                    .textSelection(.enabled)
                    .padding(.top, Theme.Spacing.medium)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.Palette.hairline).frame(height: 1) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.canvas)
        .onAppear {
            if reduceMotion { ticked = true } else { withAnimation { ticked = true } }
        }
    }

    /// "Spanish › Verbs › Irregular", naming the deck that was finished.
    private var deckPath: String {
        model.deck(session.deckID)?.fullName.replacing("::", with: " › ") ?? ""
    }

    /// "12 cards studied in 8 minutes.", desktop's timebox wording.
    private var summary: String? {
        guard session.studied > 0, let finishedAt = session.finishedAt else { return nil }
        let minutes = max(1, Int((finishedAt.timeIntervalSince(session.startedAt) / 60).rounded()))
        return Tr.studyingCardStudiedInMinute(cards: session.studied, minutes: minutes)
    }

    /// Desktop's lines under the congratulations, in its order.
    private var notes: [String] {
        guard let info = session.congrats else { return [] }
        var notes: [String] = []
        // The backend sends a day or more when no learning card is due later today.
        let secs = Int(info.secsUntilNextLearn)
        if secs < 86_400 {
            let (unit, amount) = secs < 3_600 ? ("minutes", Double(secs) / 60) : ("hours", Double(secs) / 3_600)
            notes.append(Tr.schedulingNextLearnDue(unit: unit, amount: Int(amount.rounded()))
                + " " + Tr.schedulingLearnRemaining(remaining: Int(info.learnRemaining)))
        }
        if info.reviewRemaining { notes.append(Tr.schedulingTodayReviewLimitReached) }
        if info.newRemaining { notes.append(Tr.schedulingTodayNewLimitReached) }
        return notes
    }

    private var buried: BuriedCards {
        BuriedCards(manually: session.congrats?.haveUserBuried ?? false, siblings: session.congrats?.haveSchedBuried ?? false)
    }

    private var backButton: some View {
        Button { model.stopStudying() } label: {
            Text(model.sessionReturnsToToday ? "Back to Today" : "Back to Deck")
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
        .fixedSize()
    }

    @ViewBuilder private var actions: some View {
        Group {
            if session.congrats?.isFilteredDeck == false {
                Button("\(Tr.actionsCustomStudy)…") { model.showCustomStudy(session.deckID) }
                    .help("\(Tr.actionsCustomStudy) (C)")
            }
            if buried.any {
                Button(buried.manually && buried.siblings ? "\(Tr.studyingUnbury)…" : Tr.studyingUnbury) {
                    model.unburyAfterSession(buried)
                }
            }
        }
        .fixedSize()
    }
}

/// Show Answer, then Again / Hard / Good / Easy with their next intervals,
/// in the ratings' colours. They share the width evenly up to a comfortable
/// size; in a small window they lose the key badges and get shorter.
///
/// This sits at the bottom of the window, against the HIG's advice to keep
/// controls off the bottom edge: it follows the reading order (question,
/// answer, decision) that every Anki client uses, and every action is also
/// in the Study menu with a single-key shortcut.
private struct AnswerBar: View {
    @Environment(\.compact) private var compact
    let session: StudySession?

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            buttons
        }
        .frame(height: compact ? Theme.Study.compactAnswerButtonHeight : Theme.Study.answerButtonHeight)
        // The same edge as the card, so no button reaches past it.
        .padding(.horizontal, compact ? Theme.Study.compactMargin : Theme.Study.margin)
        .padding(.vertical, compact ? 10 : 18)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var buttons: some View {
        switch session?.phase ?? .loading {
        case .question:
            Button { session?.showAnswer() } label: {
                HStack(spacing: Theme.Layout.keyCapGap) {
                    Text(Tr.studyingShowAnswer).font(Theme.Fonts.button)
                    if !compact { KeyCap("Space") }
                }
            }
            // Only a label and its key at rest: the card is what to look at.
            .buttonStyle(GradeButtonStyle(color: Theme.Palette.text, emphasised: false, rests: false))
            .frame(height: Theme.Study.showAnswerHeight)
            .fixedSize()
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
            Color.clear
        }
    }
}

private struct AnswerButton: View {
    @Environment(\.compact) private var compact
    let rating: Rating
    let interval: String
    let session: StudySession
    @AppStorage private var key: String

    init(rating: Rating, interval: String, session: StudySession) {
        self.rating = rating
        self.interval = interval
        self.session = session
        _key = AppStorage(wrappedValue: AnswerKeys.defaultKey(rating), AnswerKeys.name(rating))
    }

    var body: some View {
        Button { session.answer(rating) } label: {
            if compact {
                VStack(spacing: 2) {
                    Text(rating.title).font(.system(size: 13, weight: .semibold))
                    Text(interval).font(Theme.Fonts.intervalCaption).foregroundStyle(Theme.Palette.secondary)
                }
                .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    // The key follows the label as part of it, not as a
                    // badge in the corner.
                    HStack(spacing: Theme.Layout.keyCapGap) {
                        Text(rating.title).font(Theme.Fonts.button)
                        if !key.isEmpty { KeyCap(key) }
                    }
                    Text(interval).font(Theme.Fonts.intervalCaption).foregroundStyle(Theme.Palette.secondary)
                }
                .lineLimit(1)
            }
        }
        // Good is what most answers are, so it is the one outlined.
        .buttonStyle(GradeButtonStyle(color: rating.color, emphasised: rating == .good))
        .frame(maxWidth: Theme.Study.answerButtonMaxWidth)
        .accessibilityLabel("\(rating.title), next review in \(interval)")
    }
}

private extension Rating {
    var color: Color {
        switch self {
        case .again: Theme.Palette.coral
        case .hard: Theme.Palette.amber
        case .good: Theme.Palette.green
        case .easy: Theme.Palette.blue
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
