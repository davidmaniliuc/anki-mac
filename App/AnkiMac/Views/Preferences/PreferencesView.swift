import AnkiKit
import SwiftUI

/// The Settings window (⌘,): desktop's Preferences for the collection-wide
/// options. Changes are saved as they are made, as macOS settings are.
struct PreferencesView: View {
    let model: CollectionModel
    @State private var preferences = Anki_Config_Preferences()
    @State private var saved = Anki_Config_Preferences()
    @State private var loaded = false
    @State private var failure: ActionFailure?

    var body: some View {
        Group {
            if loaded {
                form
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 520, height: 720)
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

    private var form: some View {
        Form {
            Section(Tr.preferencesScheduling) {
                Stepper(value: rollover, in: 0...23) {
                    HStack {
                        Text(Tr.preferencesNextDayStartsAt)
                        Spacer()
                        Text("\(rollover.wrappedValue) \(Tr.preferencesHoursPastMidnight)").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: learnAhead, in: 0...999) {
                    HStack {
                        Text(Tr.preferencesLearnAheadLimit)
                        Spacer()
                        Text("\(learnAhead.wrappedValue) \(Tr.preferencesMins)").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: timebox, in: 0...999) {
                    HStack {
                        Text(Tr.preferencesTimeboxTimeLimit)
                        Spacer()
                        Text("\(timebox.wrappedValue) \(Tr.preferencesMins)").foregroundStyle(.secondary)
                    }
                }
            }
            Section(Tr.preferencesReview) {
                Toggle(Tr.preferencesShowRemainingCardCount, isOn: $preferences.reviewing.showRemainingDueCounts)
                Toggle(Tr.preferencesShowNextReviewTimeAboveAnswer, isOn: $preferences.reviewing.showIntervalsOnButtons)
                Toggle(Tr.preferencesShowPlayButtonsOnCardsWith, isOn: showPlayButtons)
                Toggle(Tr.preferencesInterruptCurrentAudioWhenAnswering, isOn: $preferences.reviewing.interruptAudioWhenAnswering)
            }
            Section(Tr.preferencesEditing) {
                Picker(Tr.preferencesDefaultDeck, selection: $preferences.editing.addingDefaultsToCurrentDeck) {
                    Text(Tr.preferencesWhenAddingDefaultToCurrentDeck).tag(true)
                    Text(Tr.preferencesChangeDeckDependingOnNoteType).tag(false)
                }
                Toggle(Tr.preferencesPasteWithoutShiftKeyStripsFormatting, isOn: $preferences.editing.pasteStripsFormatting)
                Toggle(Tr.preferencesPasteClipboardImagesAsPng, isOn: $preferences.editing.pasteImagesAsPng)
                Toggle(Tr.preferencesGenerateLatexImagesAutomatically, isOn: $preferences.editing.renderLatex)
            }
            Section(Tr.preferencesBrowsing) {
                Toggle(Tr.preferencesIgnoreAccentsInSearch, isOn: $preferences.editing.ignoreAccentsInSearch)
                TextField(
                    Tr.preferencesDefaultSearchText, text: $preferences.editing.defaultSearchText,
                    prompt: Text(Tr.preferencesDefaultSearchTextExample))
            }
            Section {
                Stepper(Tr.preferencesDailyBackups + " \(preferences.backups.daily)", value: backups(\.daily), in: 0...99)
                Stepper(Tr.preferencesWeeklyBackups + " \(preferences.backups.weekly)", value: backups(\.weekly), in: 0...99)
                Stepper(Tr.preferencesMonthlyBackups + " \(preferences.backups.monthly)", value: backups(\.monthly), in: 0...99)
                Stepper(
                    Tr.preferencesMinutesBetweenBackups + " \(preferences.backups.minimumIntervalMins)",
                    value: backups(\.minimumIntervalMins), in: 0...99999)
            } header: {
                Text(Tr.preferencesBackups)
            } footer: {
                Text(Tr.preferencesBackupExplanation + " " + Tr.preferencesMediaIsNotBackedUp)
            }
        }
        .formStyle(.grouped)
    }

    private var rollover: Binding<Int> {
        Binding { Int(preferences.scheduling.rollover) } set: { preferences.scheduling.rollover = UInt32($0) }
    }
    private var learnAhead: Binding<Int> {
        Binding { Int(preferences.scheduling.learnAheadSecs / 60) } set: { preferences.scheduling.learnAheadSecs = UInt32($0 * 60) }
    }
    private var timebox: Binding<Int> {
        Binding { Int(preferences.reviewing.timeLimitSecs / 60) } set: { preferences.reviewing.timeLimitSecs = UInt32($0 * 60) }
    }
    private var showPlayButtons: Binding<Bool> {
        Binding { !preferences.reviewing.hideAudioPlayButtons } set: { preferences.reviewing.hideAudioPlayButtons = !$0 }
    }
    private func backups(_ key: WritableKeyPath<Anki_Config_Preferences.BackupLimits, UInt32>) -> Binding<Int> {
        Binding { Int(preferences.backups[keyPath: key]) } set: { preferences.backups[keyPath: key] = UInt32($0) }
    }

    @MainActor private func load() async {
        guard model.isLoaded, let backend = model.backend else { return }
        do {
            let current = try await backend.perform { try $0.getPreferences() }
            saved = current
            preferences = current
            loaded = true
        } catch {
            failure = ActionFailure("Couldn’t load the preferences", error: error)
        }
    }

    private func save(_ new: Anki_Config_Preferences) {
        guard loaded, new != saved, let backend = model.backend else { return }
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
