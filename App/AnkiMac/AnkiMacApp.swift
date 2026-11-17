import AppKit
import SwiftUI

@main
struct AnkiMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = CollectionModel()
    @State private var bench: BenchDriver?

    init() {
        BenchDriver.trace("app_init")
    }

    var body: some Scene {
        Window("AnkiMac", id: "main") {
            ContentView()
                .environment(model)
                // Files opened from Finder wait for a profile to open.
                .onChange(of: model.isLoaded) { _, loaded in
                    if loaded { appDelegate.openPendingDocuments() }
                }
                .task {
                    BenchDriver.trace("first_task")
                    appDelegate.model = model
                    await model.start()
                    if let path = UserDefaults.standard.string(forKey: "BenchEventsPath") {
                        bench = BenchDriver(model: model, path: path)
                        bench?.run()
                    }
                }
        }
        .commands {
            LayoutCommands()
            StudyCommands(model: model)
            CardCommands(model: model)
            DeckOptionsCommands(model: model)
            SyncCommands(model: model)
            ToolsCommands(model: model)
            FormatCommands()
            ImportExportCommands(model: model)
            CommandGroup(before: .windowList) {
                Button("Browse") { BrowserWindowController.show(collection: model) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(!model.isLoaded)
                Divider()
            }
        }
        Settings {
            PreferencesView(model: model)
                .environment(model)
        }
    }
}

struct SyncCommands: Commands {
    let model: CollectionModel

    var body: some Commands {
        CommandMenu("Account") {
            Button(model.syncIsRunning ? "Cancel Sync" : model.syncAuth == nil ? Tr.syncLogInButton : "Sync") {
                if model.syncIsRunning { model.cancelSync() }
                else { Task { await model.synchronize() } }
            }
            .keyboardShortcut("y")
            .disabled(!model.isLoaded)
            if model.syncAuth != nil {
                Button(Tr.syncLogOutButton) { model.logOut() }
                Toggle("Sync Media", isOn: Binding(get: { model.syncMediaEnabled }, set: { model.syncMediaEnabled = $0 }))
            }
            Divider()
            Toggle("Automatically Sync on Open and Close", isOn: Binding(
                get: { model.autoSync }, set: { model.autoSync = $0 }))
                .disabled(!model.isLoaded)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: CollectionModel?
    private var pendingDocuments: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model, model.isLoaded else { pendingDocuments.append(contentsOf: urls); return }
        urls.forEach { model.openPackage($0) }
    }

    func openPendingDocuments() {
        let urls = pendingDocuments
        pendingDocuments.removeAll()
        urls.forEach { model?.openPackage($0) }
    }

    /// A lone `Window` scene quits the app when it closes unless told otherwise.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon brings the main window back once it's closed,
    /// also while another window, like the browser, is still open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let model, model.mainWindow?.isVisible != true { model.openMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.close()
    }
}

struct ImportExportCommands: Commands {
    let model: CollectionModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(Tr.qtAccelSwitchProfile) { Task { await model.switchProfile() } }
                .disabled(!model.isLoaded || model.profileName == nil || model.packageOperationInProgress || model.syncIsRunning)
            Divider()
            Button(Tr.actionsImport + "…") { model.promptForImport() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!model.isLoaded || model.packageOperationInProgress)
            Button(Tr.actionsExport + "…") {
                model.selectedExportNoteIDs = nil
                model.exportDeckID = nil
                model.exportSheetPresented = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!model.isLoaded || model.packageOperationInProgress)
            Divider()
            Button(Tr.qtAccelCreateBackup) { model.createBackup() }
                .disabled(!model.isLoaded || model.packageOperationInProgress)
            Button(Tr.qtAccelLoadBackup + "…") { model.promptForBackupRestore() }
                .disabled(!model.isLoaded || model.packageOperationInProgress)
        }
    }
}

/// Deck Options, and Save while its window is key.
struct DeckOptionsCommands: Commands {
    let model: CollectionModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Cards…") { AddCardsWindowController.show(collection: model) }
                .keyboardShortcut("n")
                .disabled(!model.isLoaded)
            let adding = KeyAddCards.shared.controller
            Button("Add Note") { adding?.add() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(adding == nil)
        }
        CommandGroup(replacing: .saveItem) {
            // Replacing the group takes the system's Close with it.
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Divider()
            let options = KeyDeckOptions.shared.controller
            let templates = KeyCardTemplates.shared.controller
            Button(Tr.deckConfigSaveButton) {
                if let options { options.save() } else { templates?.save() }
            }
            .keyboardShortcut("s")
            .disabled(options == nil && templates == nil)
            Button(Tr.deckConfigSaveToAllSubdecks) { options?.save(mode: .applyToChildren) }
                .disabled(options == nil)
        }
        CommandMenu("Deck") {
            let deck = model.selectedDeck
            Button("New Deck") { model.createDeck() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!model.isLoaded)
            Button(Tr.actionsRename) { if let deck { model.beginRenaming(deck.id) } }
                .disabled(deck == nil)
            Button("\(Tr.actionsRenameWithParents)…") { if let deck { model.beginRenamingWithParents(deck.id) } }
                .disabled(deck == nil || deck?.fullName == deck?.name)
            Button(Tr.actionsDelete) { if let deck { model.deleteDeck(deck.id) } }
                .disabled(deck == nil)
            Divider()
            Button("Options…") {
                if let deck { model.showOptions(deck) }
            }
            .disabled(deck == nil)
            Button(Tr.schedulingDescription) { if let deck { model.editDescription(deck.id) } }
                .disabled(deck == nil || deck?.filtered == true)
            Button("\(Tr.actionsCustomStudy)…") { if let deck { model.showCustomStudy(deck.id) } }
                .disabled(deck == nil || deck?.filtered == true)
            Button(model.selectedBuried.manually && model.selectedBuried.siblings
                ? "\(Tr.studyingUnbury)…" : Tr.studyingUnbury
            ) { if let deck { model.askUnbury(deck.id) } }
                .disabled(deck == nil || !model.selectedBuried.any)
            Divider()
            Button("Create Filtered Deck…") { model.editFilteredDeck() }
                .disabled(!model.isLoaded)
            Button(Tr.actionsRebuild) { if let deck { model.rebuildFilteredDeck(deck.id) } }
                .disabled(deck?.filtered != true)
            Button(Tr.studyingEmpty) { if let deck { model.emptyFilteredDeck(deck.id) } }
                .disabled(deck?.filtered != true)
        }
    }
}

enum MaintenanceTool: String, Identifiable {
    case database, media, emptyCards
    var id: String { rawValue }
    var title: String {
        switch self {
        case .database: Tr.databaseCheckTitle
        case .media: Tr.mediaCheckWindowTitle
        case .emptyCards: Tr.emptyCardsWindowTitle
        }
    }
}

struct ToolsCommands: Commands {
    let model: CollectionModel
    var body: some Commands {
        CommandMenu("Tools") {
            Button(Tr.databaseCheckTitle) { model.runMaintenance(.database) }.disabled(!model.isLoaded)
            Button(Tr.mediaCheckCheckMediaAction) { model.runMaintenance(.media) }.disabled(!model.isLoaded)
            Button(Tr.emptyCardsWindowTitle) { model.runMaintenance(.emptyCards) }.disabled(!model.isLoaded)
            Divider()
            Button("\(Tr.browsingManageNoteTypes)…") { NotetypeManagerWindowController.show(collection: model) }
                .disabled(!model.isLoaded)
        }
    }
}

/// The Study menu. Every control in the study screen is here too, with the
/// single-key shortcuts Anki users know.
struct StudyCommands: Commands {
    let model: CollectionModel

    var body: some Commands {
        CommandMenu("Study") {
            Button(Tr.statisticsTitle) { model.showStatistics() }
                .keyboardShortcut("t", modifiers: [])
                .disabled(!model.isLoaded)
            // "/" and Command-F are keys of the main window, not menu shortcuts, which would take them in other windows.
            Button("Quick Find…") { model.quickFindPresented = true }
                .disabled(!model.isLoaded)
            Divider()
            let session = model.session
            Button("Study Now") { model.startStudying() }
                .disabled(session != nil || (model.selectedDeck?.dueCount ?? 0) == 0)
            Divider()
            Button("Show Answer") { session?.showAnswer() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(session?.phase != .question)
            ForEach(Rating.allCases, id: \.self) { rating in
                Button(rating.title) { session?.answer(rating) }
                    .keyboardShortcut(AnswerKeys.key(rating).first.map { KeyboardShortcut(KeyEquivalent($0), modifiers: []) })
                    .disabled(session?.phase != .answer)
            }
            Divider()
            Button("Replay Audio") { session?.replayAudio() }
                .keyboardShortcut("r", modifiers: [])
                .disabled(session == nil || session?.phase == .finished)
            Button("Edit Note…") { session?.editCurrentNote() }
                .keyboardShortcut("e", modifiers: [])
                .disabled(session?.card == nil)
            Group {
                Button(Tr.studyingPauseAudio) { session?.toggleAudioPause() }
                    .keyboardShortcut("5", modifiers: [])
                Button(Tr.studyingAudio5s) { session?.seekAudio(by: -5) }
                    .keyboardShortcut("6", modifiers: [])
                Button(Tr.studyingAudioAnd5s) { session?.seekAudio(by: 5) }
                    .keyboardShortcut("7", modifiers: [])
                Button(Tr.studyingRecordOwnVoice + "…") { session?.recordVoice() }
                    .keyboardShortcut("v", modifiers: .shift)
                Button(Tr.studyingReplayOwnVoice) { session?.replayVoice() }
                    .keyboardShortcut("v", modifiers: [])
                Toggle(Tr.actionsAutoAdvance, isOn: Binding { session?.autoAdvance ?? false } set: { _ in session?.toggleAutoAdvance() })
                    .keyboardShortcut("a", modifiers: .shift)
            }
            .disabled(session == nil || session?.phase == .finished)
            Divider()
            // Desktop's single keys; the Cards menu has the same actions with Command shortcuts.
            Group {
                Button("Suspend Card") { session?.suspendCurrentCard() }.keyboardShortcut("@", modifiers: [])
                Button("Suspend Note") { session?.suspendCurrentNote() }.keyboardShortcut("!", modifiers: [])
                Button("Bury Card") { session?.buryCurrentCard() }.keyboardShortcut("-", modifiers: [])
                Button("Bury Note") { session?.buryCurrentNote() }.keyboardShortcut("=", modifiers: [])
            }
            .disabled(session?.card == nil)
            Divider()
            Button("Card Info…") { session?.showCardInfo(in: model) }
                .keyboardShortcut("i", modifiers: [])
                .disabled(session?.card == nil)
            Button(Tr.actionsWithEllipsis(action: Tr.actionsCreateCopy)) { session?.createCopy(in: model) }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(session?.card == nil)
            Button("\(Tr.actionsOptions)…") { if let deck = model.selectedDeck { model.showOptions(deck) } }
                .keyboardShortcut("o", modifiers: [])
                .disabled(model.selectedDeck == nil)
            Button("End Session") { model.stopStudying() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(session == nil)
        }
    }
}

/// Undo and Redo, for the text being typed or else the collection, and the Cards menu: flag, suspend, mark and delete, for the card
/// being studied or the rows selected in the browser, whichever window is
/// in front. Shortcuts follow desktop, with Command for its Ctrl, except the
/// flags, which keep Control+1 to 7 as in the study screen.
struct CardCommands: Commands {
    let model: CollectionModel
    @FocusedValue(\.cardTarget) private var focused

    /// The browser, when its (AppKit) window is key; otherwise the SwiftUI
    /// scene's focused target.
    private var target: (any CardCommandTarget)? {
        KeyBrowser.shared.model ?? focused
    }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            if let text = TextUndo.shared.state {
                Button(text.undoTitle) { TextUndo.shared.undo() }
                    .keyboardShortcut("z")
                    .disabled(!text.canUndo)
                Button(text.redoTitle) { TextUndo.shared.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!text.canRedo)
            } else {
                let state = target?.undoState ?? UndoState()
                Button(state.undoTitle) { target?.undo() }
                    .keyboardShortcut("z")
                    .disabled(!state.canUndo)
                Button(state.redoTitle) { target?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!state.canRedo)
            }
        }
        CommandMenu("Cards") {
            let card = target?.commandCard
            Menu("Flag") {
                ForEach(CardFlag.assignable, id: \.self) { flag in
                    Toggle(flag.title, isOn: Binding { card?.flag == flag } set: { _ in target?.toggleFlag(flag) })
                        .keyboardShortcut(KeyEquivalent(Character("\(flag.rawValue)")), modifiers: .control)
                }
            }
            .disabled(card == nil)
            Toggle("Suspend Card", isOn: Binding { card?.isSuspended ?? false } set: { _ in target?.toggleSuspend() })
                .keyboardShortcut("j")
                .disabled(card?.isSuspended == nil)
            Toggle("Bury Card", isOn: Binding { card?.isBuried ?? false } set: { _ in target?.toggleBury() })
                .keyboardShortcut("j", modifiers: [.command, .shift])
                .disabled(card?.isBuried == nil)
            Toggle("Mark Note", isOn: Binding { card?.isMarked ?? false } set: { _ in target?.toggleMark() })
                .keyboardShortcut("k")
                .disabled(card == nil)
            Divider()
            Button(Tr.actionsCardInfo) { showCardInfo() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(infoCardID == nil)
            Button(Tr.actionsPreviousCardInfo) { showPreviousCardInfo() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(previousInfoCardID == nil)
            Button(Tr.actionsPreview) { BrowserWindowController.current?.togglePreview() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(browser?.singleSelectedRow == nil)
            Divider()
            Button("Change Deck…") { browser?.askChangeDeck() }
                .keyboardShortcut("d")
                .disabled(!hasBrowserSelection)
            // Both the browser's selection and the card being studied.
            Group {
                Button("Set Due Date…") { target?.askSetDueDate() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Reset…") { target?.askForget() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("Reposition…") { target?.askReposition() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!(target?.canReposition ?? false))
            }
            .disabled(!(target?.canScheduleCards ?? false))
            Divider()
            Button("Delete Notes…") { deleteNotes() }
                .keyboardShortcut(.delete)
                .disabled(!(target?.canDeleteNotes ?? false))
        }
        CommandMenu("Notes") {
            Group {
                Button("Add Tags…") { browser?.askTags(adding: true) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Remove Tags…") { browser?.askTags(adding: false) }
                    .keyboardShortcut("a", modifiers: [.command, .option, .shift])
                Divider()
                Button("Find and Replace…") { browser?.askFindAndReplace() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Divider()
                Button("Change Note Type…") { browser?.askChangeNotetype() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
            .disabled(!hasBrowserSelection)
            Divider()
            Button(Tr.browsingFindDuplicates + "…") { BrowserWindowController.current?.showFindDuplicates() }
                .disabled(browser == nil)
            Divider()
            Button("Export Notes…") { browser?.exportSelectedNotes() }
                .disabled(!hasBrowserSelection)
        }
    }

    private var browser: BrowserModel? { KeyBrowser.shared.model }

    /// The card Card Info would show: the browser's current row, or the card being studied.
    private var infoCardID: Int64? {
        browser != nil ? browser?.currentCardID : (target as? StudySession)?.card?.queued.card.id
    }

    private var previousInfoCardID: Int64? {
        browser == nil ? (target as? StudySession)?.previousCardID : nil
    }

    private func showCardInfo() {
        guard let id = infoCardID else { return }
        CardInfoWindowController.show(cardID: id, kind: browser != nil ? .browser : .reviewer, collection: model)
    }

    private func showPreviousCardInfo() {
        guard let id = previousInfoCardID else { return }
        CardInfoWindowController.show(cardID: id, kind: .previousReviewer, collection: model)
    }

    private var hasBrowserSelection: Bool {
        !(browser?.selectedRows.isEmpty ?? true)
    }

    /// Command-Delete also means "delete to the start of the line" while
    /// typing in the search field, and the menu would otherwise take it.
    private func deleteNotes() {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
        } else {
            target?.deleteNotes()
        }
    }
}
