import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(CollectionModel.self) private var model

    var body: some View {
        NavigationSplitView {
            DeckSidebar()
        } detail: {
            ZStack {
                StudyView(session: model.session)
                if model.session == nil {
                    if let deck = model.selectedDeck {
                        DeckOverview(deck: deck)
                    } else if model.isLoaded {
                        ContentUnavailableView(
                            "No Deck Selected", systemImage: "rectangle.stack",
                            description: Text("Choose a deck in the sidebar."))
                    }
                }
            }
        }
        .navigationTitle(model.selectedDeck?.name ?? "AnkiMac")
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
        .modifier(DeckPrompts())
        .alert(
            "Something went wrong",
            isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }
        ) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
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
