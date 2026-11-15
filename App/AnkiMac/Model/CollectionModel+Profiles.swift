import AnkiKit
import AppKit
import Foundation
import UniformTypeIdentifiers

/// The profile manager's actions that need the backend, with no profile open.
extension CollectionModel {
    /// Desktop's Open Backup: replaces the profile's collection with one of
    /// its backups, then opens it with syncing and backups off for the session.
    func openBackup(of name: String) {
        guard let backend, let paths = try? CollectionPaths.profile(name) else { return }
        let panel = NSOpenPanel()
        panel.title = Tr.qtMiscRevertToBackup
        panel.directoryURL = paths.backups
        panel.allowedContentTypes = UTType(filenameExtension: "colpkg").map { [$0] } ?? []
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let confirm = NSAlert()
        confirm.alertStyle = .warning
        confirm.messageText = Tr.qtMiscReplaceYourCollectionWithAnEarlier2(val: url.lastPathComponent)
        confirm.addButton(withTitle: Tr.actionsCancel)
        confirm.addButton(withTitle: Tr.qtMiscRevertToBackup)
        confirm.buttons[1].hasDestructiveAction = true
        guard confirm.runModal() == .alertSecondButtonReturn else { return }
        let info = NSAlert()
        info.messageText = Tr.qtMiscAutomaticSyncingAndBackupsHaveBeen
        info.runModal()
        packageOperationInProgress = true
        Task {
            defer { packageOperationInProgress = false }
            do {
                try await backend.perform { backend in
                    var request = Anki_ImportExport_ImportCollectionPackageRequest()
                    request.colPath = paths.collection.path
                    request.backupPath = url.path
                    request.mediaFolder = paths.mediaFolder.path
                    request.mediaDb = paths.mediaDB.path
                    try backend.importCollectionPackage(request)
                }
            } catch {
                failure = ActionFailure("Couldn’t restore the backup", error: error)
                return
            }
            backupRestored = true
            await openProfile(name)
        }
    }

    /// Desktop's Downgrade & Quit: leaves every profile's collection in the
    /// format older versions of Anki open, then quits; or says which
    /// couldn't be and stays.
    func downgradeAndQuit(_ names: [String]) {
        guard let backend else { return }
        packageOperationInProgress = true
        Task {
            let problems = try? await backend.perform { backend in
                names.filter { name in
                    guard let paths = try? CollectionPaths.profile(name),
                        FileManager.default.fileExists(atPath: paths.collection.path)
                    else { return false }
                    var open = Anki_Collection_OpenCollectionRequest()
                    open.collectionPath = paths.collection.path
                    open.mediaFolderPath = paths.mediaFolder.path
                    open.mediaDbPath = paths.mediaDB.path
                    var close = Anki_Collection_CloseCollectionRequest()
                    close.downgradeToSchema11 = true
                    do {
                        try backend.openCollection(open)
                        try backend.closeCollection(close)
                        return false
                    } catch {
                        try? backend.closeCollection(Anki_Collection_CloseCollectionRequest())
                        return true
                    }
                }
            }
            packageOperationInProgress = false
            let alert = NSAlert()
            guard let problems, problems.isEmpty else {
                alert.alertStyle = .warning
                alert.messageText = "The following profiles could not be downgraded: "
                    + (problems ?? names).joined(separator: ", ")
                alert.runModal()
                return
            }
            alert.messageText = "Profiles can now be opened with an older version of Anki."
            alert.runModal()
            quit()
        }
    }

    /// Quits from the profiles' sheet. AppKit won't quit while a window
    /// has a sheet attached, so the sheet comes down first.
    func quit() {
        if let window = mainWindow, let sheet = window.attachedSheet { window.endSheet(sheet) }
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
