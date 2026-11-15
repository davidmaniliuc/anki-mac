import AppKit
import SwiftUI

/// The band with the note type, the deck and Add, then the fields and the
/// tags, on the canvas as the main window's pages are.
struct AddCardsView: View {
    @Bindable var model: AddCardsModel
    let chrome: BandChrome
    let collection: CollectionModel
    let actions: AddCardsActions

    var body: some View {
        VStack(spacing: 0) {
            band
            NoteEditorView(
                editor: model.editor,
                sticky: (isOn: model.isSticky, toggle: model.toggleSticky),
                duplicateField: model.problem == .duplicate ? 0 : nil,
                cardLayout: actions.cardLayout)
            hints
            Theme.Palette.hairline.frame(height: 1)
            TagRow(tags: $model.tags, complete: model.completeTags)
                .padding(Theme.Spacing.medium)
        }
        .background(Theme.Palette.canvas)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        .overlay(alignment: .bottom) {
            if let added = model.addedMessage {
                Text(added)
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                    .glassEffect(in: Capsule())
                    .glassEffectTransition(.materialize)
                    .padding(Theme.AddCards.toastInset)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.default, value: model.addedMessage)
        // The toast is gone before VoiceOver would reach it.
        .onChange(of: model.addedMessage) { _, added in
            if let added { AccessibilityNotification.Announcement(added).post() }
        }
        // No actions: the system's own OK, in the user's language.
        .alert(
            model.message ?? "", isPresented: Binding { model.message != nil } set: { if !$0 { model.message = nil } }
        ) {}
        .alert(Tr.addingYouHaveAClozeDeletionNote, isPresented: $model.confirmingMissingCloze) {
            Button("Cancel", role: .cancel) {}
            Button(Tr.actionsAdd) { Task { _ = await model.add(confirmedCloze: true) } }
        }
    }

    /// Under the traffic lights, as the Browser's: the note type and deck as
    /// quiet menus, then History and Add, the window's one prominent action.
    private var band: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            notetypeMenu
            deckMenu
                .layoutPriority(-1)
            Spacer(minLength: Theme.Spacing.small)
            historyMenu
            Button(action: actions.add) {
                HStack(spacing: Theme.Layout.keyCapGap) {
                    Text(Tr.actionsAdd)
                    KeyCap("\u{2318}\u{21A9}", onAccent: true)
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true, muted: !model.addable))
            .keyboardShortcut(.return, modifiers: .command)
            .help("\(Tr.actionsAdd) (\u{2318}\u{21A9})")
            .padding(.leading, Theme.Spacing.xSmall)
        }
        // Clear of the traffic lights, which in full screen come down over
        // the band in a pill of their own.
        .padding(.leading, chrome.fullScreen ? Theme.Spacing.medium : Theme.Band.leading)
        .padding(.trailing, Theme.Spacing.medium)
        .frame(height: Theme.Band.height)
        .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
    }

    private var notetypeMenu: some View {
        Menu {
            Picker(Tr.notetypesType, selection: Binding { model.notetypeID } set: { id in
                Task { await model.changeNotetype(to: id) }
            }) {
                ForEach(model.notetypes) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            QuietMenuLabel(title: Tr.notetypesType, value: model.notetypes.first { $0.id == model.notetypeID }?.name ?? "")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Tr.notetypesType)
    }

    /// The deck tree as nested menus, as Statistics' deck menu, holding the
    /// decks a note can be added to.
    private var deckMenu: some View {
        let name = model.decks.first { $0.id == model.deckID }?.name ?? ""
        let allowed = Set(model.decks.map(\.id))
        return Menu {
            DeckMenuItems(
                decks: DeckNode.keeping(allowed, in: collection.decks), current: model.deckID,
                pick: { model.deckID = $0 })
        } label: {
            QuietMenuLabel(
                title: Tr.decksDeck, value: name.replacingOccurrences(of: "::", with: " \u{203A} "), truncation: .head)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Tr.decksDeck)
        .accessibilityValue(name)
    }

    /// Off until a note is added, as desktop's History button.
    private var historyMenu: some View {
        Menu {
            ForEach(model.history.reversed()) { entry in
                Button(Tr.addingEdit(val: entry.text)) { actions.showInBrowser("nid:\(entry.id)") }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(Theme.AddCards.historySymbol)
                .foregroundStyle(model.history.isEmpty ? Theme.Palette.tertiary : Theme.Palette.secondary)
                .frame(width: Theme.AddCards.historySize.width, height: Theme.AddCards.historySize.height)
                .modifier(MenuHover(shape: RoundedRectangle(cornerRadius: Theme.Layout.rowRadius), inset: 0))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.history.isEmpty)
        .help(Tr.addingHistory)
        .accessibilityLabel(Tr.addingHistory)
    }

    /// Desktop's notes under the fields: duplicates and misplaced clozes.
    @ViewBuilder private var hints: some View {
        if let problem = model.problem {
            HStack {
                if problem == .duplicate {
                    Button(Tr.editingShowDuplicates) { actions.showInBrowser(model.duplicateSearch) }
                        .buttonStyle(.link)
                } else {
                    OptionWarning(text: problem.hint)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.bottom, Theme.Spacing.small)
        }
    }
}

/// The editors' tags: a tag symbol before the field, with no box of its own.
struct TagRow: View {
    @Binding var tags: [String]
    let complete: (String) -> [String]

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "tag")
                .font(Theme.Editor.tagSymbol)
                .foregroundStyle(Theme.Palette.secondary)
                .accessibilityHidden(true)
            TagField(tags: $tags, complete: complete, borderless: true)
        }
    }
}
