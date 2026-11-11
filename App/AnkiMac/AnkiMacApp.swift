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
                .task {
                    BenchDriver.trace("first_task")
                    appDelegate.model = model
                    await model.open()
                    if let path = UserDefaults.standard.string(forKey: "BenchEventsPath") {
                        bench = BenchDriver(model: model, path: path)
                        bench?.run()
                    }
                }
        }
        .commands {
            SidebarCommands()
            StudyCommands(model: model)
            CardCommands()
            DeckOptionsCommands(model: model)
            FormatCommands()
            CommandGroup(before: .windowList) {
                Button("Browse") { BrowserWindowController.show(collection: model) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(!model.isLoaded)
                Divider()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: CollectionModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.close()
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
            let options = KeyDeckOptions.shared.controller
            Button(Tr.deckConfigSaveButton) { options?.save() }
                .keyboardShortcut("s")
                .disabled(options == nil)
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
            Button(Tr.actionsDelete) { if let deck { model.deleteDeck(deck.id) } }
                .disabled(deck == nil)
            Divider()
            Button("Options…") {
                if let deck { model.showOptions(deck) }
            }
            .disabled(deck == nil)
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

/// The Study menu. Every control in the study screen is here too, with the
/// single-key shortcuts Anki users know.
struct StudyCommands: Commands {
    let model: CollectionModel

    var body: some Commands {
        CommandMenu("Study") {
            let session = model.session
            Button("Study Now") { model.startStudying() }
                .disabled(session != nil || (model.selectedDeck?.dueCount ?? 0) == 0)
            Divider()
            Button("Show Answer") { session?.showAnswer() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(session?.phase != .question)
            ForEach(Rating.allCases, id: \.self) { rating in
                Button(rating.title) { session?.answer(rating) }
                    .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue + 1)")), modifiers: [])
                    .disabled(session?.phase != .answer)
            }
            Divider()
            Button("Replay Audio") { session?.replayAudio() }
                .keyboardShortcut("r", modifiers: [])
                .disabled(session == nil || session?.phase == .finished)
            Button("Edit Note…") { session?.editCurrentNote() }
                .keyboardShortcut("e", modifiers: [])
                .disabled(session?.card == nil)
            Button(Tr.studyingPauseAudio) { session?.toggleAudioPause() }
                .keyboardShortcut("5", modifiers: [])
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
            // Card Info lands with the stats-cardinfo branch; this is the call site to wire.
            Button("Card Info…") { session?.showCardInfo() }
                .keyboardShortcut("i", modifiers: [])
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

/// Undo, and the Cards menu: flag, suspend, mark and delete, for the card
/// being studied or the rows selected in the browser, whichever window is
/// in front. Shortcuts follow desktop, with Command for its Ctrl, except the
/// flags, which keep Control+1 to 7 as in the study screen.
struct CardCommands: Commands {
    @FocusedValue(\.cardTarget) private var focused

    /// The browser, when its (AppKit) window is key; otherwise the SwiftUI
    /// scene's focused target.
    private var target: (any CardCommandTarget)? {
        KeyBrowser.shared.model ?? focused
    }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            let label = target?.undoLabel ?? ""
            Button(label.isEmpty ? "Undo" : "Undo \(label)") { target?.undo() }
                .keyboardShortcut("z")
                .disabled(label.isEmpty)
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
            }
            .disabled(!hasBrowserSelection)
        }
    }

    private var browser: BrowserModel? { KeyBrowser.shared.model }

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
