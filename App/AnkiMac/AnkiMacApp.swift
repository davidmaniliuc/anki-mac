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
            Toggle("Mark Note", isOn: Binding { card?.isMarked ?? false } set: { _ in target?.toggleMark() })
                .keyboardShortcut("k")
                .disabled(card == nil)
            Divider()
            Button("Delete Notes…") { deleteNotes() }
                .keyboardShortcut(.delete)
                .disabled(!(target?.canDeleteNotes ?? false))
        }
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
