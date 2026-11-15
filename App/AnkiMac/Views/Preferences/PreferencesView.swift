import AnkiKit
import SwiftUI

/// The Settings window (⌘,): desktop's Preferences, its tabs as the
/// toolbar's panes, each drawn as Deck Options' settings are. Changes are
/// saved as they are made, as macOS settings are.
struct PreferencesView: View {
    let model: CollectionModel
    @State private var preferences = Anki_Config_Preferences()
    @State private var saved = Anki_Config_Preferences()
    @State private var state = LoadState.loading
    @State private var failure: ActionFailure?
    @AppStorage(AnswerKeys.spaceAnswersName) private var spaceAnswers = true

    var body: some View {
        TabView {
            pane { review }
                .tabItem { Label(Tr.preferencesReview, systemImage: "rectangle.stack") }
            pane { editing }
                .tabItem { Label(Tr.preferencesEditing, systemImage: "pencil") }
            SyncPane(model: model)
                .modifier(PreferencesPane())
                .tabItem { Label(Tr.preferencesNetwork, systemImage: "arrow.triangle.2.circlepath") }
            pane { backups }
                .tabItem { Label(Tr.preferencesBackups, systemImage: "clock.arrow.circlepath") }
        }
        .containerBackground(Theme.Palette.canvas, for: .window)
        .task(id: model.isLoaded) { await load() }
        .onChange(of: preferences) { _, new in save(new) }
        .alert(
            failure?.title ?? "",
            isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }
        ) {
            Button("OK") {}
        } message: {
            Text(verbatim: failure?.detail ?? "")
        }
    }

    private enum LoadState: Equatable {
        case loading, ready, noCollection, failed(String)
    }

    /// A pane of collection settings, or why they aren't there: still
    /// loading, no profile open, or a failed load to try again.
    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Group {
            switch state {
            case .ready:
                content()
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: Theme.Preferences.placeholderHeight)
            case .noCollection:
                placeholder("Open a profile to change these settings.")
            case .failed(let reason):
                VStack(spacing: Theme.Spacing.small) {
                    placeholder("Couldn’t load the settings. \(reason)")
                    Button("Try Again") { Task { await load() } }
                        .buttonStyle(ChipButtonStyle())
                }
            }
        }
        .modifier(PreferencesPane())
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Palette.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: Theme.Preferences.placeholderHeight)
    }

    @ViewBuilder private var review: some View {
        OptionSection(title: Tr.preferencesScheduler) {
            numberRow(Tr.preferencesNextDayStartsAt, unit: Tr.preferencesHoursPastMidnight, value: rollover, range: 0...23)
            numberRow(Tr.preferencesLearnAheadLimit, unit: Tr.preferencesMins, value: learnAhead, range: 0...999)
            numberRow(Tr.preferencesTimeboxTimeLimit, unit: Tr.preferencesMins, value: timebox, range: 0...999)
        }
        OptionSection(title: Tr.preferencesReview) {
            switchRow(Tr.preferencesShowPlayButtonsOnCardsWith, isOn: showPlayButtons)
            switchRow(Tr.preferencesInterruptCurrentAudioWhenAnswering, isOn: $preferences.reviewing.interruptAudioWhenAnswering)
            switchRow(Tr.preferencesShowRemainingCardCount, isOn: $preferences.reviewing.showRemainingDueCounts)
            switchRow(Tr.preferencesShowNextReviewTimeAboveAnswer, isOn: $preferences.reviewing.showIntervalsOnButtons)
            switchRow(Tr.preferencesSpacebarRatesCard, isOn: $spaceAnswers)
            switchRow(Tr.preferencesGenerateLatexImagesAutomatically, isOn: $preferences.editing.renderLatex)
            // Desktop asks for them in a prompt; here they're typed in place.
            OptionRow(title: Tr.preferencesUrlSchemes, help: Tr.preferencesUrlSchemePrompt, revertible: false) {
                CommitField(
                    text: model.allowedURLSchemes.joined(separator: " "), prompt: "mailto",
                    font: Theme.DeckOptions.rowFont
                ) {
                    model.allowedURLSchemes = $0.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
                }
                .frame(width: Theme.DeckOptions.searchFieldWidth)
            }
        }
        OptionSection(title: Tr.preferencesAnswerKeys) {
            Text(Tr.preferencesShortcutPlaceholder)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .optionNote()
            ForEach(Rating.allCases, id: \.self) { AnswerKeyRow(rating: $0) }
        }
    }

    @ViewBuilder private var editing: some View {
        OptionSection(title: Tr.preferencesEditing) {
            switchRow(Tr.preferencesPasteClipboardImagesAsPng, isOn: $preferences.editing.pasteImagesAsPng)
            switchRow(Tr.preferencesPasteWithoutShiftKeyStripsFormatting, isOn: $preferences.editing.pasteStripsFormatting)
            OptionRow(title: Tr.preferencesDefaultDeck, revertible: false) {
                OptionPicker(selection: $preferences.editing.addingDefaultsToCurrentDeck, choices: [
                    (true, Tr.preferencesWhenAddingDefaultToCurrentDeck),
                    (false, Tr.preferencesChangeDeckDependingOnNoteType),
                ])
            }
        }
        OptionSection(title: Tr.preferencesBrowsing) {
            // Saved once typing ends: each save reloads the decks.
            OptionRow(title: Tr.preferencesDefaultSearchText, revertible: false) {
                CommitField(
                    text: preferences.editing.defaultSearchText, prompt: Tr.preferencesDefaultSearchTextExample,
                    font: Theme.DeckOptions.rowFont
                ) { preferences.editing.defaultSearchText = $0 }
                .frame(width: Theme.DeckOptions.searchFieldWidth)
            }
            switchRow(Tr.preferencesIgnoreAccentsInSearch, isOn: $preferences.editing.ignoreAccentsInSearch)
        }
    }

    @ViewBuilder private var backups: some View {
        OptionSection(title: Tr.preferencesBackups) {
            // Desktop's line on restoring names File > Switch Profile; here
            // it's File > Revert to Backup, which no string of upstream's says.
            Text(Tr.preferencesBackupExplanation)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .optionNote()
            numberRow(Tr.preferencesDailyBackups, value: backups(\.daily), range: 0...99)
            numberRow(Tr.preferencesWeeklyBackups, value: backups(\.weekly), range: 0...99)
            numberRow(Tr.preferencesMonthlyBackups, value: backups(\.monthly), range: 0...99)
            numberRow(Tr.preferencesMinutesBetweenBackups, value: backups(\.minimumIntervalMins), range: 0...99999)
            OptionWarning(text: Tr.preferencesMediaIsNotBackedUp)
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        OptionRow(title: title, revertible: false) { SwitchControl(title: title, isOn: isOn) }
    }

    /// A number with desktop's unit after it, in Pencil.
    private func numberRow(_ title: String, unit: String = "", value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        OptionRow(title: title, revertible: false) {
            NumberField(value: value, range: range, unit: unit)
        }
    }

    private var rollover: Binding<Double> {
        Binding { Double(preferences.scheduling.rollover) } set: { preferences.scheduling.rollover = UInt32($0) }
    }
    private var learnAhead: Binding<Double> {
        Binding { Double(preferences.scheduling.learnAheadSecs / 60) } set: { preferences.scheduling.learnAheadSecs = UInt32($0) * 60 }
    }
    private var timebox: Binding<Double> {
        Binding { Double(preferences.reviewing.timeLimitSecs / 60) } set: { preferences.reviewing.timeLimitSecs = UInt32($0) * 60 }
    }
    private var showPlayButtons: Binding<Bool> {
        Binding { !preferences.reviewing.hideAudioPlayButtons } set: { preferences.reviewing.hideAudioPlayButtons = !$0 }
    }
    private func backups(_ key: WritableKeyPath<Anki_Config_Preferences.BackupLimits, UInt32>) -> Binding<Double> {
        Binding { Double(preferences.backups[keyPath: key]) } set: { preferences.backups[keyPath: key] = UInt32($0) }
    }

    /// Runs as the collection opens and closes, so a closed profile's
    /// settings never stay on screen to be changed.
    @MainActor private func load() async {
        guard model.isLoaded, let backend = model.backend else {
            state = .noCollection
            return
        }
        state = .loading
        do {
            let current = try await backend.perform { try $0.getPreferences() }
            saved = current
            preferences = current
            state = .ready
        } catch {
            state = .failed(ActionFailure.reason(error))
        }
    }

    private func save(_ new: Anki_Config_Preferences) {
        guard state == .ready, model.isLoaded, new != saved, let backend = model.backend else { return }
        saved = new
        Task {
            do {
                _ = try await backend.perform { try $0.setPreferences(new) }
                model.deckOptionsChanged()
            } catch {
                failure = ActionFailure("Couldn’t save the preferences", error: error)
            }
        }
    }
}

/// A rating's key in the reviewer: one character, or none.
private struct AnswerKeyRow: View {
    let rating: Rating
    @AppStorage private var key: String

    init(rating: Rating) {
        self.rating = rating
        _key = AppStorage(wrappedValue: AnswerKeys.defaultKey(rating), AnswerKeys.name(rating))
    }

    var body: some View {
        OptionRow(title: rating.title, revertible: false) {
            // The last character typed, so typing over the key replaces it.
            CommitField(text: key) { key = $0.trimmingCharacters(in: .whitespaces).last.map(String.init) ?? "" }
                .multilineTextAlignment(.center)
                .frame(width: Theme.DeckOptions.numberFieldWidth)
        }
    }
}

/// Desktop's Syncing tab: the profile's sync switches and its AnkiWeb login.
private struct SyncPane: View {
    let model: CollectionModel
    @State private var loggingIn = false
    /// Whether the next sync is already one-way, which can't be taken back.
    @State private var oneWayPending = false

    var body: some View {
        OptionSection(title: Tr.preferencesTabSynchronisation) {
            OptionRow(title: Tr.preferencesSynchronizeAudioAndImagesToo, revertible: false) {
                SwitchControl(
                    title: Tr.preferencesSynchronizeAudioAndImagesToo,
                    isOn: Binding { model.syncMediaEnabled } set: { model.syncMediaEnabled = $0 })
            }
            OptionRow(title: Tr.preferencesAutomaticallySyncOnProfileOpenclose, revertible: false) {
                SwitchControl(
                    title: Tr.preferencesAutomaticallySyncOnProfileOpenclose,
                    isOn: Binding { model.autoSync } set: { model.autoSync = $0 })
            }
            OptionRow(title: Tr.preferencesPeriodicallySyncMedia, revertible: false) {
                SwitchControl(
                    title: Tr.preferencesPeriodicallySyncMedia,
                    isOn: Binding { model.periodicMediaSync } set: { model.periodicMediaSync = $0 })
            }
            OptionRow(title: Tr.preferencesOnNextSyncForceChangesIn, revertible: false) {
                SwitchControl(
                    title: Tr.preferencesOnNextSyncForceChangesIn,
                    isOn: Binding { oneWayPending } set: { on in
                        guard on else { return }
                        oneWayPending = true
                        Task { oneWayPending = await model.forceOneWaySync() }
                    })
                    .disabled(oneWayPending)
            }
            OptionRow(title: Tr.preferencesNetworkTimeout, revertible: false) {
                NumberField(
                    value: Binding { Double(model.networkTimeout) } set: { model.networkTimeout = Int($0) },
                    range: 30...99999, unit: Tr.schedulingSeconds)
            }
        }
        .disabled(!model.isLoaded)
        // A sync, here or elsewhere, may have carried the one-way change.
        .task(id: model.isLoaded && !model.syncIsRunning) {
            guard let backend = model.backend, model.isLoaded else { return }
            oneWayPending = (try? await backend.perform { $0.schemaAlreadyChanged() }) ?? false
        }
        OptionSection(title: Tr.preferencesAccount) {
            if model.syncAuth == nil {
                Text(Tr.preferencesAnkiwebIntro)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .optionNote()
                OptionActions {
                    Button(Tr.syncLogInButton) { loggingIn = true }
                        .disabled(!model.isLoaded)
                }
            } else {
                OptionRow(title: model.syncUsername, revertible: false) {
                    Button(Tr.syncLogOutButton) { model.logOut() }
                        .buttonStyle(ChipButtonStyle())
                        .disabled(model.syncIsRunning)
                }
            }
            OptionRow(title: Tr.preferencesCustomSyncUrl, revertible: false) {
                CommitField(text: model.customSyncURL, prompt: "https://", font: Theme.DeckOptions.rowFont) {
                    model.customSyncURL = $0.trimmingCharacters(in: .whitespaces)
                }
                .frame(width: Theme.DeckOptions.searchFieldWidth)
                .disabled(!model.isLoaded || model.syncIsRunning)
            }
            OptionWarning(text: Tr.preferencesCustomSyncUrlDisclaimer, level: .info)
        }
        .sheet(isPresented: $loggingIn) {
            SyncLoginSheet().environment(model)
        }
        // A login closes the main window's sheet; this one closes once
        // the account is in.
        .onChange(of: model.syncAuth != nil) { _, loggedIn in
            if loggedIn { loggingIn = false }
        }
    }
}

/// A tab's settings in one column on the canvas, as tall as they are, so
/// the window fits each tab; one taller than the screen scrolls instead of
/// running off it.
private struct PreferencesPane: ViewModifier {
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.DeckOptions.sectionGap) {
                content
            }
            .padding(.horizontal, Theme.DeckOptions.margin)
            .padding(.top, Theme.Preferences.topPadding)
            .padding(.bottom, Theme.DeckOptions.margin)
            .frame(width: Theme.Preferences.width, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Theme.Preferences.width, height: height.map { min($0, Self.maxHeight) })
    }

    private static var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? Theme.Preferences.fallbackScreenHeight) - Theme.Preferences.chromeHeight
    }
}
