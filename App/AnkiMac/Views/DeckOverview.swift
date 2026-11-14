import SwiftUI

/// The selected deck before studying: what's due and Study Now, its
/// subdecks, and its other actions.
struct DeckOverview: View {
    @Environment(CollectionModel.self) private var model
    let deck: DeckNode

    private struct DescriptionLoad: Hashable {
        let deckID: Int64
        let refreshed: Date
    }

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                PageTitle(eyebrow: parentPath, title: deck.name) {
                    DeckRing(deck: deck, size: 22, selected: true)
                }
                description
            }

            if deck.dueCount > 0 {
                DueSummary(new: deck.newCount, learn: deck.learnCount, review: deck.reviewCount) {
                    studyButton
                }
            } else {
                // Desktop's overview shows its congratulations here.
                Text(Tr.schedulingCongratulationsFinished)
                    .font(Theme.Fonts.panelTitle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let children = deck.children {
                PageSection("Decks") {
                    ForEach(children) { DeckListRow(deck: $0) }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.small) { actions }
                VStack(alignment: .leading, spacing: Theme.Spacing.small) { actions }
            }
            .buttonStyle(ChipButtonStyle())
        }
        // Add Cards into this deck is the one action with no other place on
        // the page: Options is a chip below, Browse and Statistics are in
        // the sidebar.
        .pageActions {
            IconButton("plus", help: "Add Cards") {
                AddCardsWindowController.show(collection: model, deckID: deck.id)
            }
        }
        // The counts change with every refresh, so this follows unburying too.
        .task(id: deck) {
            model.selectedBuried = await model.buriedCards(in: deck)
        }
        // Reloaded with every refresh too, which follows Undo, Redo, sync and saving the Description sheet.
        .task(id: DescriptionLoad(deckID: deck.id, refreshed: model.lastRefresh)) {
            let description = deck.filtered ? nil : await model.description(of: deck.id)
            // A slower load for the deck shown before this one must not replace this deck's.
            guard !Task.isCancelled else { return }
            model.selectedDescription = description
        }
    }

    /// "Spanish › Verbs" for "Spanish::Verbs::Irregular".
    private var parentPath: String {
        deck.fullName.components(separatedBy: "::").dropLast().joined(separator: " › ")
    }

    /// Study Now (Return), the page's one prominent action.
    private var studyButton: some View {
        Button { model.startStudying() } label: {
            HStack(spacing: 10) {
                Text("Study Now")
                KeyCap("↩", onAccent: true)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
        .fixedSize()
    }

    @ViewBuilder private var actions: some View {
        if deck.filtered {
            Button(Tr.actionsRebuild) { model.rebuildFilteredDeck(deck.id) }
                .help("\(Tr.actionsRebuild) (R)")
            Button(Tr.studyingEmpty) { model.emptyFilteredDeck(deck.id) }
                .help("\(Tr.studyingEmpty) (E)")
        } else {
            Button("\(Tr.actionsCustomStudy)…") { model.showCustomStudy(deck.id) }
                .help("\(Tr.actionsCustomStudy) (C)")
            Button("\(Tr.schedulingDescription)…") { model.editDescription(deck.id) }
        }
        Button("Options…") { model.showOptions(deck) }
            .help("Options (O)")
        if model.selectedBuried.any {
            Button(model.selectedBuried.manually && model.selectedBuried.siblings
                ? "\(Tr.studyingUnbury)…" : Tr.studyingUnbury
            ) { model.askUnbury(deck.id) }
                .help("\(Tr.studyingUnbury) (U)")
        }
    }

    /// A filtered deck shows desktop's note about special decks in place of a
    /// description.
    @ViewBuilder private var description: some View {
        let text: Text? = if deck.filtered {
            Text(DeckDescription.filteredNote)
        } else if let description = model.selectedDescription, description.id == deck.id, !description.text.isEmpty {
            Text(description.body)
        } else {
            nil
        }
        if let text {
            ViewThatFits(in: .vertical) {
                text.textSelection(.enabled)
                ScrollView { text.textSelection(.enabled) }
                    .frame(maxHeight: Theme.Overview.descriptionMaxHeight)
            }
            .font(Theme.Fonts.lead)
            .foregroundStyle(Theme.Palette.secondary)
            .padding(.top, 2)
        }
    }
}
