import AppKit
import SwiftUI

/// Desktop's profile manager, in the main window while no profile is open:
/// the profiles, and Open, Add, Rename, Delete, Open Backup, Downgrade &
/// Quit and Quit.
struct ProfilesView: View {
    @Environment(CollectionModel.self) private var model
    @State private var names: [String] = []
    @State private var selection: String?
    @State private var prompt: NamePrompt?
    @State private var promptText = ""
    @State private var deleting: String?
    @State private var warning: String?

    private enum NamePrompt { case add, rename(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.profilesProfiles)
                .font(.title2.weight(.semibold))
            List(names, id: \.self, selection: $selection) { name in
                Text(name)
            }
            .contextMenu(forSelectionType: String.self) { _ in
            } primaryAction: { selected in
                if let name = selected.first { open(name) }
            }
            .frame(height: Theme.Profiles.listHeight)
            .onKeyPress(.return) {
                guard let selection else { return .ignored }
                open(selection)
                return .handled
            }
            HStack {
                Button(Tr.actionsAdd) { ask(.add) }
                Button(Tr.actionsRename) { if let selection { ask(.rename(selection)) } }
                    .disabled(selection == nil)
                Button(Tr.actionsDelete) { delete() }
                    .disabled(selection == nil)
                Spacer()
                Button(Tr.profilesOpen) { if let selection { open(selection) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            Divider()
            HStack {
                Button(Tr.profilesOpenBackup) { if let selection { model.openBackup(of: selection) } }
                    .disabled(selection == nil)
                Button(Tr.profilesDowngradeAndQuit) { model.downgradeAndQuit(names) }
                Spacer()
                Button(Tr.profilesQuit) { NSApp.terminate(nil) }
            }
        }
        .disabled(model.packageOperationInProgress)
        .padding(Theme.Spacing.large)
        .frame(width: Theme.Profiles.width)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Tr.profilesProfiles)
        .onAppear { reload(selecting: Profiles.lastLoaded) }
        .alert(promptTitle, isPresented: Binding { prompt != nil } set: { if !$0 { prompt = nil } }) {
            TextField(Tr.actionsName, text: $promptText)
            Button(Tr.actionsCancel, role: .cancel) {}
            Button("OK") { finishPrompt() }
        }
        .alert(
            Tr.qtMiscAllCardsNotesAndMediaFor2(name: deleting ?? ""),
            isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } }
        ) {
            Button(Tr.actionsCancel, role: .cancel) {}
            Button(Tr.actionsDelete, role: .destructive) { confirmDelete() }
        }
        .alert(warning ?? "", isPresented: Binding { warning != nil } set: { if !$0 { warning = nil } }) {
            Button("OK") {}
        }
    }

    private var promptTitle: String {
        if case .rename = prompt { Tr.actionsNewName } else { Tr.actionsName }
    }

    private func reload(selecting name: String?) {
        do {
            names = try Profiles.names()
        } catch {
            warning = "\(error)"
        }
        selection = name.flatMap { names.contains($0) ? $0 : nil } ?? names.first
    }

    private func open(_ name: String) {
        Task { await model.openProfile(name) }
    }

    private func ask(_ kind: NamePrompt) {
        if case .rename(let name) = kind { promptText = name } else { promptText = "" }
        prompt = kind
    }

    private func finishPrompt() {
        guard let prompt else { return }
        let name = promptText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            switch prompt {
            case .add:
                if let problem = Profiles.problem(with: name, among: names) {
                    warning = problem
                    return
                }
                try Profiles.create(name)
            case .rename(let old):
                guard name != old else { return }
                if let problem = Profiles.problem(with: name, among: names.filter { $0 != old }) {
                    warning = problem
                    return
                }
                try Profiles.rename(old, to: name)
            }
            reload(selecting: name)
        } catch {
            warning = "\(error)"
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
            warning = "\(error)"
        }
        reload(selecting: nil)
    }
}
