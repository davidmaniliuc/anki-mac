import AnkiKit
import AppKit
import Foundation
import UniformTypeIdentifiers

/// Why a backup is made. The backend skips an unforced one when the
/// collection hasn't changed or the last backup is within the user's
/// minimum interval.
nonisolated enum BackupKind: Sendable {
    case periodic
    case onClose
    /// File > Create Backup, and before Check Database.
    case manual

    var force: Bool { self == .manual }
}

extension AnkiBackend {
    /// Writes the backup and waits for it, so a failure surfaces here and a
    /// quit doesn't kill the backup thread. False when the backend skipped it.
    nonisolated func backUp(_ kind: BackupKind, to folder: URL) throws -> Bool {
        var request = Anki_Collection_CreateBackupRequest()
        request.backupFolder = folder.path
        request.force = kind.force
        let created = try createBackup(request).val
        try awaitBackupCompletion()
        return created
    }
}

/// Desktop's backups: the 5-minute timer, File > Create Backup and
/// Revert to Backup. The one on close is in `close()`.
extension CollectionModel {
    private static let periodicBackupInterval = Duration.seconds(5 * 60)

    func startPeriodicBackups() {
        backupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.periodicBackupInterval)
                guard !Task.isCancelled, let self else { return }
                if !backupRestored { _ = await backUp(.periodic) }
            }
        }
    }

    func createBackup() {
        Task {
            guard let created = await backUp(.manual) else { return }
            backupMessage = created ? Tr.profilesBackupCreated : Tr.profilesBackupUnchanged
        }
    }

    /// nil when it failed, after saying so.
    private func backUp(_ kind: BackupKind) async -> Bool? {
        guard let backend, let paths, isLoaded, !collectionClosed else { return nil }
        do {
            return try await backend.perform { try $0.backUp(kind, to: paths.backups) }
        } catch {
            errorMessage = Tr.profilesBackupCreationFailed(reason: FilteredDeckModel.message(error))
            return nil
        }
    }

    func promptForBackupRestore() {
        guard let folder = paths?.backups else { return }
        let panel = NSOpenPanel()
        panel.title = Tr.qtMiscRevertToBackup
        panel.directoryURL = folder
        panel.allowedContentTypes = UTType(filenameExtension: "colpkg").map { [$0] } ?? []
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.confirmBackupRestore(url)
        }
    }

    private func confirmBackupRestore(_ url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Tr.qtMiscReplaceYourCollectionWithAnEarlier2(val: url.lastPathComponent)
        alert.addButton(withTitle: Tr.actionsCancel)
        alert.addButton(withTitle: Tr.qtMiscRevertToBackup)
        alert.buttons[1].hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        replaceCollection(from: url, isBackup: true)
    }
}
