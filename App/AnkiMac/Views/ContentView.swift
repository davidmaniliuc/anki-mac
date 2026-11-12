import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(CollectionModel.self) private var model
    @State private var layout = WindowLayout()

    var body: some View {
        Group {
            if model.choosingProfile {
                ProfilesView()
                    .frame(minWidth: Theme.Window.minWidth, minHeight: Theme.Window.minHeight)
            } else {
                decks
            }
        }
        .background(Theme.Palette.canvas.ignoresSafeArea())
        // The window keeps its title for the Window menu, but none is drawn
        // in the title bar; each page names itself. The toolbar stays
        // see-through over the sidebar and the page.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                IconButton("sidebar.left", help: "Toggle Sidebar (⌃⌘S)") { layout.toggleSidebar() }
            }
            .plain()
        }
        .environment(layout)
        .focusedSceneValue(\.windowLayout, layout)
        .background(WindowReader { model.mainWindow = $0 })
        .alert(
            model.failure?.title ?? "",
            isPresented: Binding { model.failure != nil } set: { if !$0 { model.failure = nil } }
        ) {
            Button("OK") {}
        } message: {
            Text(verbatim: model.failure?.detail ?? "")
        }
    }

    /// The sidebar beside the content, or floating over it in a small window.
    /// Studying puts the sidebar away; it comes back when the session ends.
    private var decks: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < Theme.Layout.compactWidth
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if layout.sidebarVisible && !compact {
                        DeckSidebar()
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    detail
                }
                if layout.sidebarVisible && compact {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { layout.toggleSidebar(false) }
                        .transition(.opacity)
                    DeckSidebar()
                        .shadow(color: .black.opacity(0.35), radius: 24, x: 6)
                        .transition(.move(edge: .leading))
                }
            }
            .environment(\.compact, compact)
            .onChange(of: compact, initial: true) { _, compact in
                layout.sidebarFloats = compact
                layout.sidebarVisible = !compact && model.session == nil
            }
        }
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onChange(of: model.session == nil) { _, ended in
            layout.toggleSidebar(ended && !layout.sidebarFloats)
        }
        .onSidebarSwipe(in: { [weak model] in model?.mainWindow }) { layout.toggleSidebar($0) }
        .navigationTitle(model.selectedDeck?.name ?? "AnkiMac")
        .navigationSubtitle(model.profileName ?? "")
        // Undo acts on the card being studied, or else on the deck list.
        .focusedSceneValue(\.cardTarget, model.session.map { $0 as any CardCommandTarget } ?? model)
        .frame(minWidth: Theme.Window.minWidth, minHeight: Theme.Window.minHeight)
        .onChange(of: model.selectedDeckID) { _, deckID in
            // Picking another deck in the sidebar leaves the session.
            if let session = model.session, session.deckID != deckID {
                model.stopStudying()
            }
        }
        .sheet(item: Binding { model.filteredDeck } set: { model.filteredDeck = $0 }) { deck in
            FilteredDeckSheet(
                deck: deck,
                cancel: { model.filteredDeck = nil },
                built: { model.filteredDeckBuilt($0) },
                showInBrowser: { search in
                    BrowserWindowController.show(collection: model)
                    BrowserWindowController.current?.model.search(text: search)
                })
        }
        .sheet(item: Binding { model.maintenanceTool } set: { model.maintenanceTool = $0 }) { tool in
            MaintenanceToolView(model: model, tool: tool)
        }
        .modifier(DeckPrompts())
        .modifier(ImportExportPrompts())
        .modifier(SyncPrompts())
        .alert(
            Tr.preferencesBackups,
            isPresented: Binding { model.backupMessage != nil } set: { if !$0 { model.backupMessage = nil } }
        ) {
            Button("OK") {}
        } message: {
            Text(model.backupMessage ?? "")
        }
    }
}

extension ContentView {
    private var detail: some View {
        ZStack {
            // Always here, hidden while not studying, so the card's web view
            // is attached once (see StudyView).
            StudyView(session: model.session)
            if model.session == nil {
                if let deck = model.selectedDeck {
                    DeckOverview(deck: deck)
                } else if model.isLoaded {
                    TodayView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.canvas)
    }
}

/// Hands over the window a view is in, once it's in one.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { WindowReaderView(found: found) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowReaderView: NSView {
        let found: (NSWindow) -> Void

        init(found: @escaping (NSWindow) -> Void) {
            self.found = found
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { found(window) }
        }
    }
}

/// File › Import and Export, and packages opened from Finder.
private struct ImportExportPrompts: ViewModifier {
    @Environment(CollectionModel.self) private var model

    func body(content: Content) -> some View {
        content
        .sheet(isPresented: Binding { model.exportSheetPresented } set: { model.exportSheetPresented = $0 }) {
            ImportExportSheet(selectedNoteIDs: model.selectedExportNoteIDs, initialDeckID: model.exportDeckID)
                .environment(model)
        }
        .sheet(isPresented: Binding { model.packageImportPresented } set: { model.packageImportPresented = $0 }) {
            if let url = model.packageImportURL { ImportOptionsSheet(url: url).environment(model) }
        }
        .sheet(item: Binding { model.csvImport } set: { model.csvImport = $0 }) { draft in
            CsvImportSheet(draft: draft).environment(model)
        }
        .sheet(item: Binding { model.importResult } set: { model.importResult = $0 }) { result in
            ImportLogSheet(result: result)
        }
        .alert(
            Tr.importingImportingComplete,
            isPresented: Binding { model.importMessage != nil } set: { if !$0 { model.importMessage = nil } }
        ) {
            Button("OK") {}
        } message: {
            Text(model.importMessage ?? "")
        }
    }
}

private struct SyncPrompts: ViewModifier {
    @Environment(CollectionModel.self) private var model

    func body(content: Content) -> some View {
        content
        .sheet(isPresented: Binding { model.syncLoginPresented } set: { model.syncLoginPresented = $0 }) {
            SyncLoginSheet().environment(model)
        }
        .alert("Sync", isPresented: Binding { model.syncConflictPresented } set: { model.syncConflictPresented = $0 }) {
            if model.syncConflict == .fullUpload {
                Button(Tr.syncUploadToAnkiweb) { Task { await model.resolveSyncConflict(upload: true) } }
                Button("Cancel", role: .cancel) { Task { await model.resolveSyncConflict(upload: nil) } }
            } else if model.syncConflict == .fullDownload {
                Button(Tr.syncDownloadFromAnkiweb) { Task { await model.resolveSyncConflict(upload: false) } }
                Button("Cancel", role: .cancel) { Task { await model.resolveSyncConflict(upload: nil) } }
            } else {
                Button(Tr.syncUploadToAnkiweb) { Task { await model.resolveSyncConflict(upload: true) } }
                Button(Tr.syncDownloadFromAnkiweb) { Task { await model.resolveSyncConflict(upload: false) } }
                Button("Cancel", role: .cancel) { Task { await model.resolveSyncConflict(upload: nil) } }
            }
        } message: {
            Text(model.syncConflict == .fullUpload ? Tr.syncConfirmEmptyUpload : model.syncConflict == .fullDownload ? Tr.syncConfirmEmptyDownload : Tr.syncConflictExplanation2)
        }
        .alert("Sync", isPresented: Binding { model.syncAlert != nil } set: { if !$0 { model.syncAlert = nil } }) {
            Button("OK") { model.syncAlert = nil }
        } message: { Text(model.syncAlert ?? "") }
    }
}

/// Custom Study, the Unbury question,
/// and keeping the deck list current when the window comes back to the front.
private struct DeckPrompts: ViewModifier {
    @Environment(CollectionModel.self) private var model

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding { model.customStudy } set: { model.customStudy = $0 }) { study in
                CustomStudySheet(
                    study: study,
                    cancel: { model.customStudy = nil },
                    done: { model.customStudyDone(selecting: $0) })
            }
            .sheet(isPresented: Binding { model.studyDeckPresented } set: { model.studyDeckPresented = $0 }) {
                StudyDeckSheet().environment(model)
            }
            .sheet(item: Binding { model.descriptionEdit } set: { model.descriptionEdit = $0 }) { edit in
                DeckDescriptionSheet(edit: edit, cancel: { model.descriptionEdit = nil }, save: model.saveDescription)
            }
            .confirmationDialog(
                Tr.studyingWhatWouldYouLikeToUnbury,
                isPresented: Binding { model.unburyPrompt != nil } set: { if !$0 { model.unburyPrompt = nil } },
                presenting: model.unburyPrompt
            ) { deckID in
                Button(Tr.studyingManuallyBuriedCards) { model.unbury(deckID, mode: .userOnly) }
                Button(Tr.studyingBuriedSiblings) { model.unbury(deckID, mode: .schedOnly) }
                Button(Tr.studyingAllBuriedCards) { model.unbury(deckID) }
                Button("Cancel", role: .cancel) {}
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                // The browser may have changed cards or decks, and Undo's label.
                guard model.isLoaded, model.session == nil,
                    let window = note.object as? NSWindow, window === model.reviewer.webView?.window
                else { return }
                Task { await model.refreshDecks() }
            }
    }
}
