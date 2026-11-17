import AppKit
import SwiftUI

/// Desktop's profile manager, a sheet on the main window while no
/// profile is open: the profiles as rows, Open as the page's primary with Add,
/// Rename and Delete as chips, and behind a hairline Open Backup,
/// Downgrade & Quit and Quit as quiet buttons. A profile is named in its
/// row, as a deck is in the sidebar, not in desktop's prompt.
struct ProfilesView: View {
    @Environment(CollectionModel.self) private var model
    @State private var names: [String] = []
    @State private var selection: String?
    @State private var editing: Editing?
    @State private var draft = ""
    @State private var deleting: String?
    @State private var warning: String?

    private enum Editing: Equatable { case add, rename(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            PageTitle(eyebrow: "", title: Tr.profilesProfiles) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: Theme.Profiles.titleIconSize))
                    .foregroundStyle(Theme.Palette.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(names, id: \.self) { name in
                    if editing == .rename(name) {
                        nameField
                    } else {
                        // One profile needs no choosing, so it shows no selection;
                        // nor do the others while a name is typed, so only its row is washed.
                        ProfileRow(name: name, selected: name == selection && names.count > 1, editing: editing != nil) {
                            selection = name
                        } open: {
                            if editing == nil { open(name) }
                        }
                    }
                }
                if editing == .add { nameField }
            }
            // Up and Down as shortcuts rather than key presses: a focusable
            // list keeps the name field in it from taking focus. Off while a
            // name is typed, so the field has the arrows.
            .background {
                Group {
                    Button("") { step(-1) }.keyboardShortcut(.upArrow, modifiers: [])
                    Button("") { step(1) }.keyboardShortcut(.downArrow, modifiers: [])
                }
                .opacity(0)
                .accessibilityHidden(true)
                .disabled(editing != nil)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Tr.profilesProfiles)
            ActionRow {
                Button { if let selection { open(selection) } } label: {
                    Text(Tr.profilesOpen)
                }
                // As tall as the chips beside it: on a sheet this small the page's
                // 36pt primary towers over the row.
                .buttonStyle(PrimaryButtonStyle(compact: true, muted: selection == nil || editing != nil))
                .keyboardShortcut(.defaultAction)
                .fixedSize()
                // Off while a name is typed, so Return ends the typing.
                .disabled(selection == nil || editing != nil)
            } secondary: {
                Button(Tr.actionsAdd) { begin(.add) }
                    .keyboardShortcut("n")
                    .help("\(Tr.actionsAdd) (⌘N)")
                Button(Tr.actionsRename) { if let selection { begin(.rename(selection)) } }
                    .disabled(selection == nil)
                // Set a little apart: it can't be taken back.
                // Off with the row while a name is typed, so ⌫ stays the field's.
                Button(Tr.actionsDelete) { delete() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(selection == nil)
                    .help("\(Tr.actionsDelete) (⌫)")
                    .padding(.leading, Theme.Spacing.small)
            }
            .disabled(editing != nil)
            // Rarely needed, so quiet and behind a hairline; the two that
            // quit sit together at the trailing edge.
            HStack(spacing: Theme.Spacing.xSmall) {
                footerButton(Tr.profilesOpenBackup) { if let selection { model.openBackup(of: selection) } }
                    .disabled(selection == nil)
                Spacer(minLength: Theme.Spacing.small)
                footerButton(Tr.profilesDowngradeAndQuit) { model.downgradeAndQuit(names) }
                    .help(String(
                        localized: "Lets an older version of Anki open these profiles, then quits.",
                        comment: "Help for the profile list's Downgrade & Quit"))
                footerButton(Tr.profilesQuit) { model.quit() }
            }
            .disabled(editing != nil)
            // The words keep to the page's edges; the washes reach past them.
            .padding(.horizontal, -Theme.Spacing.small)
            .padding(.top, Theme.Spacing.medium)
            .overlay(alignment: .top) { Rectangle().fill(Theme.Palette.hairline).frame(height: 1) }
            .padding(.top, Theme.Spacing.medium)
        }
        .padding(.horizontal, Theme.Layout.pageMargin)
        .padding(.vertical, Theme.Layout.pageMargin)
        .frame(width: Theme.Profiles.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .disabled(model.packageOperationInProgress)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
        // Without animation: Open leaves its muted look as the sheet comes
        // down, and animating that slides it in from the window's top.
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { reload(selecting: Profiles.lastLoaded) }
        }
        .alert(
            Tr.qtMiscAllCardsNotesAndMediaFor2(name: deleting ?? ""),
            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } }
        ) {
            Button(Tr.actionsCancel, role: .cancel) {}
            Button(Tr.actionsDelete, role: .destructive) { confirmDelete() }
        }
        // The main window is out of sight, so a profile that won't open says so here.
        .alert(
            model.failure?.title ?? "",
            isPresented: Binding { model.failure != nil } set: { if !$0 { model.failure = nil } }
        ) {
            Button(Tr.customStudyOk) {}
        } message: {
            Text(verbatim: model.failure?.detail ?? "")
        }
        .alert(warning ?? "", isPresented: Binding { warning != nil } set: { if !$0 { warning = nil } }) {
            Button(Tr.customStudyOk) {}
        }
    }

    private var nameField: some View {
        RowNameField(name: $draft, problem: problem, font: Theme.Fonts.listRow, height: Theme.Layout.listRowHeight,
            end: finishEditing)
    }

    /// Why the typed name can't be used, checked as it is typed; nothing while it's empty.
    private var problem: String? {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard let editing, !name.isEmpty else { return nil }
        switch editing {
        case .add: return Profiles.problem(with: name, among: names)
        case .rename(let old):
            return name == old ? nil : Profiles.problem(with: name, among: names.filter { $0 != old })
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.chip)
                .frame(height: Theme.Layout.controlHeight)
        }
        .buttonStyle(QuietButtonStyle(inset: Theme.Spacing.small))
    }

    /// Up and Down move the selection, stopping at the ends.
    private func step(_ offset: Int) {
        guard !names.isEmpty else { return }
        let index = selection.flatMap { names.firstIndex(of: $0) } ?? (offset > 0 ? -1 : names.count)
        selection = names[min(max(index + offset, 0), names.count - 1)]
    }

    private func reload(selecting name: String?) {
        do {
            names = try Profiles.names()
        } catch {
            warning = ActionFailure.reason(error)
        }
        selection = name.flatMap { names.contains($0) ? $0 : nil } ?? names.first
    }

    private func open(_ name: String) {
        Task { await model.openProfile(name) }
    }

    private func begin(_ kind: Editing) {
        if case .rename(let name) = kind { draft = name } else { draft = "" }
        editing = kind
    }

    /// Return keeps the name, unless it has a problem, which stays under it
    /// with the typing kept; clicking away keeps it only if it can be used,
    /// and Esc puts things back.
    private func finishEditing(_ ending: RowNameField.Ending) {
        guard let kind = editing else { return }
        let name = draft.trimmingCharacters(in: .whitespaces)
        if ending == .submit, problem != nil {
            NSSound.beep()
            return
        }
        editing = nil
        guard ending != .cancel, problem == nil, !name.isEmpty else { return }
        do {
            switch kind {
            case .add: try Profiles.create(name)
            case .rename(let old):
                guard name != old else { return }
                try Profiles.rename(old, to: name)
            }
            reload(selecting: name)
        } catch {
            warning = ActionFailure.reason(error)
        }
    }

    private func delete() {
        guard let selection else { return }
        guard names.count > 1 else {
            warning = Tr.qtMiscThereMustBeAtLeastOne
            return
        }
        deleting = selection
    }

    private func confirmDelete() {
        guard let name = deleting else { return }
        do {
            try Profiles.remove(name)
        } catch {
            warning = ActionFailure.reason(error)
        }
        reload(selecting: nil)
    }
}

/// A profile in the list: a click selects it, a double click opens it.
/// The selected row has the selection wash, as the sidebar's does. The
/// page's title carries the person symbol, so the row is the name alone.
private struct ProfileRow: View {
    let name: String
    let selected: Bool
    let editing: Bool
    let select: () -> Void
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Text(name).font(Theme.Fonts.listRow).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRow(height: Theme.Layout.listRowHeight,
                wash: editing ? .clear : selected ? Theme.Palette.selection : hovered ? Theme.Palette.hover : .clear)
            .contentShape(.rect)
            .onHover { hovered = $0 }
            .onClick(select, doubleClick: open)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, select)
            .accessibilityAction(named: Tr.profilesOpen, open)
    }
}
