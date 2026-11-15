import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.openWindow) private var openWindow
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
        .safeAreaPadding(.top, layout.fullScreen ? Theme.Window.fullScreenBand : 0)
        // The scroll views' edge effect fills the band with a backdrop of
        // what's behind the window, a grey strip once the toolbar has left
        // for the bar that comes down; the sidebar and page show through.
        .scrollEdgeEffectHidden(layout.fullScreen, for: .top)
        .overlay(alignment: .topLeading) {
            if layout.fullScreen {
                IconButton("sidebar.left", help: "Toggle Sidebar (⌃⌘S)") { layout.toggleSidebar() }
                    .frame(height: Theme.Window.fullScreenBand)
                    .padding(.leading, Theme.Spacing.small)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard let window = layout.window, note.object as? NSWindow === window else { return }
            layout.fullScreen = true
            FullScreenTitlebar.dress(window, true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { note in
            guard let window = layout.window, note.object as? NSWindow === window else { return }
            layout.fullScreen = false
            FullScreenTitlebar.dress(window, false)
        }
        .background(Theme.Palette.canvas.ignoresSafeArea())
        // The window keeps its title for the Window menu, but none is drawn
        // in the title bar; each page names itself. The toolbar stays
        // see-through over the sidebar and the page.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // In full screen the toolbar would be drawn as an opaque grey bar
        // over the sidebar and the page; it hides with the menu bar instead.
        .windowToolbarFullScreenVisibility(.onHover)
        .toolbar {
            // In full screen the page draws its own, and the bar that comes
            // down with the menu bar shows only the traffic lights. The item
            // stays, hidden: without it the toolbar goes and the bar shrinks
            // to a plain title bar, the lights moving with it.
            ToolbarItem(placement: .navigation) {
                IconButton("sidebar.left", help: "Toggle Sidebar (⌃⌘S)") { layout.toggleSidebar() }
                    .opacity(layout.fullScreen ? 0 : 1)
                    .allowsHitTesting(!layout.fullScreen)
                    .accessibilityHidden(layout.fullScreen)
            }
            .plain()
        }
        .environment(layout)
        .focusedSceneValue(\.windowLayout, layout)
        .background(WindowReader {
            model.mainWindow = $0
            model.openMainWindow = { openWindow(id: "main") }
            layout.window = $0
            // The bar that comes down in full screen is as opaque as the
            // window's background colour, so that is clear and the content
            // paints the canvas itself. The title bar is see-through too.
            $0.titlebarAppearsTransparent = true
            $0.isOpaque = false
            $0.backgroundColor = .clear
            // The toolbar's menu would offer Icon and Text, which its items
            // have no text for. SwiftUI adds the toolbar after the window.
            DispatchQueue.main.async { [weak window = $0] in
                window?.toolbar?.allowsDisplayModeCustomization = false
            }
        })
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
    private var decks: some View {
        GeometryReader { proxy in
            let docked = layout.sidebarVisible && !layout.sidebarFloats
            let page = layout.pageWidth ?? proxy.size.width - (docked ? Theme.Layout.sidebarWidth : 0)
            ZStack(alignment: .leading) {
                if docked || layout.pageWidth != nil {
                    DeckSidebar()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                // While the window's right edge moves, the page keeps its
                // width against it and slides over the sidebar.
                detail
                    .frame(width: layout.pageWidth)
                    .padding(.leading, docked && layout.pageWidth == nil ? Theme.Layout.sidebarWidth : 0)
                    .frame(width: proxy.size.width, alignment: .trailing)
                if layout.sidebarVisible && layout.sidebarFloats {
                    Color.black.opacity(Theme.Layout.scrimOpacity)
                        .ignoresSafeArea()
                        .onTapGesture { layout.toggleSidebar(false) }
                        .transition(.opacity)
                    DeckSidebar()
                        .shadow(
                            color: .black.opacity(Theme.Layout.floatingShadowOpacity),
                            radius: Theme.Layout.floatingShadowRadius, x: Theme.Layout.floatingShadowOffset)
                        .transition(.move(edge: .leading))
                }
            }
            .environment(\.compact, page < Theme.Layout.compactPageWidth)
            .onChange(of: proxy.size.width < Theme.Layout.compactWidth, initial: true) { _, narrow in
                layout.windowWidthChanged(narrow: narrow)
            }
        }
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .onSidebarSwipe(in: { [weak model] in model?.mainWindow }) { layout.toggleSidebar($0) }
        .overlay(alignment: .bottom) {
            // One container, so the two capsules materialize as glass and
            // blend when they sit together.
            GlassEffectContainer(spacing: Theme.Spacing.small) {
                VStack(spacing: Theme.Spacing.small) {
                    if let capsule = model.mediaSyncCapsule {
                        MediaSyncCapsule(state: capsule)
                            .glassEffectTransition(.materialize)
                    }
                    if let notice = model.notice {
                        Text(notice)
                            .padding(.horizontal, Theme.Spacing.medium)
                            .padding(.vertical, Theme.Spacing.small)
                            .glassEffect(in: Capsule())
                            .glassEffectTransition(.materialize)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.xLarge)
            .animation(.default, value: model.notice)
            .animation(.smooth, value: model.mediaSyncCapsule == nil)
        }
        .overlay(alignment: .top) {
            if model.quickFindPresented {
                ZStack(alignment: .top) {
                    // A click anywhere else closes it, as in Things.
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { model.quickFindPresented = false }
                    QuickFind().padding(.top, Theme.QuickFind.topInset)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(.snappy(duration: 0.15), value: model.quickFindPresented)
        .navigationTitle(model.selectedDeck?.name ?? "AnkiMac")
        .navigationSubtitle(model.profileName ?? "")
        // Undo acts on the card being studied, or else on the deck list.
        .focusedSceneValue(\.cardTarget, model.session.map { $0 as any CardCommandTarget } ?? model)
        // A docked sidebar keeps its width, so the window can't be narrowed
        // past it and the page's minimum. Not while the window slides,
        // which would snap it to the new minimum.
        .frame(
            minWidth: Theme.Window.minWidth
                + (layout.sidebarVisible && !layout.sidebarFloats && layout.pageWidth == nil ? Theme.Layout.sidebarWidth : 0),
            minHeight: Theme.Window.minHeight)
        .onChange(of: model.page) { _, page in
            // Picking another deck, Today or Statistics in the sidebar leaves the session.
            if let session = model.session, page != .deck(session.deckID) {
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
                    if model.page == .statistics, let statistics = model.statistics {
                        StatisticsView(model: statistics)
                    } else {
                        TodayView()
                    }
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

/// Media syncs after the collection, often for a while, so its progress
/// floats over the window rather than squeezing into the Sync button.
/// Always two lines, and it only ever grows, so the glass holds its shape
/// while the counts change.
private struct MediaSyncCapsule: View {
    let state: MediaSyncCapsuleState
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            ZStack {
                if case .complete = state {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Palette.green)
                        .transition(.opacity)
                } else {
                    ProgressView().controlSize(.small)
                        .transition(.opacity)
                }
            }
            .frame(width: Theme.MediaSync.iconSize, height: Theme.MediaSync.iconSize)
            VStack(alignment: .leading, spacing: Theme.MediaSync.lineSpacing) {
                Text(title).font(Theme.Fonts.chip)
                if let detail {
                    Text(detail)
                        .font(Theme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(width, $0) }
            .frame(minWidth: max(width, Theme.MediaSync.minWidth), alignment: .leading)
        }
        .padding(.leading, Theme.MediaSync.leadingInset)
        .padding(.trailing, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
        .glassEffect(in: Capsule())
        .animation(.snappy(duration: 0.2), value: width)
        .animation(.smooth(duration: 0.25), value: isComplete)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var isComplete: Bool {
        if case .complete = state { return true }
        return false
    }

    private var title: String { isComplete ? Tr.syncMediaComplete : "Syncing Media" }

    /// The counts, or that it's starting before the first count arrives.
    private var detail: String? {
        switch state {
        case .syncing(let progress): progress.isEmpty ? Tr.syncMediaStarting : progress
        case .complete(let progress): progress.isEmpty ? nil : progress
        }
    }
}
