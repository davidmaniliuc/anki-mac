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
        .focusedSceneValue(\.cardTarget, model.session)
        .frame(minWidth: Theme.Window.minWidth, minHeight: Theme.Window.minHeight)
        .onChange(of: model.selectedDeckID) { _, deckID in
            // Picking another deck in the sidebar leaves the session.
            if let session = model.session, session.deckID != deckID {
                model.stopStudying()
            }
        }
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
