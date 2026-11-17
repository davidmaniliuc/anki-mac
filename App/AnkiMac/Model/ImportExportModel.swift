import AnkiKit
import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// An import's log, as desktop's Import Log shows it: how many notes the
/// file held, then what became of them, each note with the reason.
struct ImportResult: Identifiable {
    let id = UUID()
    let fileName: String
    let found: Int
    /// Added, skipped, updated and failed, in desktop's order, each with notes.
    let summaries: [ImportSummary]

    init(log: Anki_ImportExport_ImportResponse.Log, fileName: String) {
        self.fileName = fileName
        found = Int(log.foundNotes)
        var summaries: [ImportSummary] = [
            ImportSummary(kind: .added, queues: [(log.new, Tr.importingAddedNewNote)]),
            ImportSummary(kind: .skipped, queues: [(log.duplicate, Tr.importingExistingNoteSkipped)]),
            ImportSummary(kind: .updated, queues: [(log.updated, Tr.importingNoteUpdatedAsFileHadNewer)]),
            ImportSummary(kind: .failed, queues: [
                (log.conflicting, Tr.importingNoteSkippedUpdateDueToNotetype2),
                (log.missingNotetype, Tr.importingNoteSkippedDueToMissingNotetype),
                (log.missingDeck, Tr.importingNoteSkippedDueToMissingDeck),
                (log.emptyFirstField, Tr.importingNoteSkippedDueToEmptyFirstField),
            ]),
        ]
        // Text files log a first-field match apart; it goes with the notes
        // the resolution adds, updates or skips.
        let (kind, reason): (ImportSummary.Kind, String) = switch log.dupeResolution {
        case .duplicate: (.added, Tr.importingDuplicateNoteAdded)
        case .preserve: (.skipped, Tr.importingExistingNoteSkipped)
        default: (.updated, Tr.importingNoteUpdatedAsFileHadNewer)
        }
        if let index = summaries.firstIndex(where: { $0.kind == kind }) {
            summaries[index].append(log.firstFieldMatch, reason: reason)
        }
        self.summaries = summaries
    }
}

/// One of the log's outcomes and the notes it befell.
struct ImportSummary: Identifiable {
    enum Kind { case added, skipped, updated, failed }

    let kind: Kind
    private(set) var notes: [ImportedNote] = []
    var id: Kind { kind }

    init(kind: Kind, queues: [([Anki_ImportExport_ImportResponse.Note], String)]) {
        self.kind = kind
        for (notes, reason) in queues { append(notes, reason: reason) }
    }

    mutating func append(_ logged: [Anki_ImportExport_ImportResponse.Note], reason: String) {
        notes += logged.map { ImportedNote(noteID: $0.id.nid, fields: $0.fields.joined(separator: ", "), reason: reason) }
    }

    /// Desktop's word for what happened, as its details table's status.
    var status: String {
        switch kind {
        case .added: Tr.addingAdded
        case .skipped, .failed: Tr.importingSkipped
        case .updated: Tr.importingUpdated
        }
    }

    func summary(count: Int) -> String {
        switch kind {
        case .added: Tr.importingNotesAdded(count: count)
        case .skipped: Tr.importingExistingNotesSkipped(count: count)
        case .updated: Tr.importingNotesUpdated(count: count)
        case .failed: Tr.importingNotesFailed(count: count)
        }
    }

    /// Notes that failed were never added, so there is nothing to show.
    var canBrowse: Bool { kind != .failed }
}

struct ImportedNote: Identifiable {
    let id = UUID()
    let noteID: Int64
    let fields: String
    let reason: String
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case deckPackage, collectionPackage, notes, cards

    var id: Self { self }
    var title: String {
        switch self {
        case .deckPackage: Tr.exportingAnkiDeckPackage
        case .collectionPackage: Tr.exportingAnkiCollectionPackage
        case .notes: Tr.exportingNotesInPlainText
        case .cards: Tr.exportingCardsInPlainText
        }
    }
    var extensionName: String {
        switch self {
        case .deckPackage: "apkg"
        case .collectionPackage: "colpkg"
        case .notes, .cards: "txt"
        }
    }
}

extension CollectionModel {
    func promptForImport() {
        let panel = NSOpenPanel()
        panel.title = Tr.actionsImport
        panel.allowedContentTypes = ["apkg", "colpkg", "zip", "csv", "tsv", "txt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openPackage(url)
        }
    }

    /// Entry point for File > Import and Finder: .colpkg replaces the
    /// collection after a warning, .apkg asks for options first.
    func openPackage(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "colpkg":
            confirmReplacingCollection(from: url)
        case "apkg", "zip":
            presentPackageImport(url)
        case "csv", "txt", "tsv":
            presentCsvImport(url)
        default:
            failure = ActionFailure(Tr.importingUnableToImportFilename(filename: url.lastPathComponent), detail: "")
        }
    }

    /// Desktop's warning, on the main window. Import gets no key, so Return
    /// can't replace the collection: desktop's default is No.
    private func confirmReplacingCollection(from url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Tr.importingThisWillDeleteYourExistingCollection
        alert.addButton(withTitle: Tr.actionsImport)
        alert.addButton(withTitle: Tr.actionsCancel)
        alert.buttons[0].hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\u{1b}"
        let respond = { [weak self] (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn { self?.replaceCollection(from: url) }
        }
        if let window = mainWindow, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    /// Reads the presets first, so the sheet opens with them and Import
    /// can't be pressed before they arrive.
    private func presentPackageImport(_ url: URL) {
        guard let backend, isLoaded, !packageOperationInProgress else { return }
        Task {
            do {
                packageImportOptions = try await backend.perform { try $0.getImportAnkiPackagePresets() }
                packageImportURL = url
                packageFailure = nil
                packageImportPresented = true
            } catch {
                failure = ActionFailure("Couldn’t read the import options", error: error)
            }
        }
    }

    /// `isBackup` for Revert to Backup, which also ends backups and sync on close.
    func replaceCollection(from url: URL, isBackup: Bool = false) {
        guard let backend, let paths, isLoaded, !packageOperationInProgress else { return }
        packageOperationInProgress = true
        Task {
            defer { packageOperationInProgress = false }
            do {
                collectionClosed = true
                try await backend.perform { backend in
                    try backend.closeCollection(Anki_Collection_CloseCollectionRequest())
                    defer { try? Self.openCollection(backend, paths: paths) }
                    var request = Anki_ImportExport_ImportCollectionPackageRequest()
                    request.colPath = paths.collection.path
                    request.backupPath = url.path
                    request.mediaFolder = paths.mediaFolder.path
                    request.mediaDb = paths.mediaDB.path
                    try backend.importCollectionPackage(request)
                }
                collectionClosed = false
                await refreshDecks()
                if isBackup {
                    backupRestored = true
                    backupMessage = Tr.qtMiscAutomaticSyncingAndBackupsHaveBeen
                } else {
                    showNotice(Tr.importingImportingComplete)
                }
            } catch {
                collectionClosed = false
                await refreshDecks()
                failure = ActionFailure("Couldn’t import the collection", error: error)
            }
        }
    }

    func importPackage(_ url: URL, options: Anki_ImportExport_ImportAnkiPackageOptions) {
        guard let backend, isLoaded, !packageOperationInProgress else { return }
        packageOperationInProgress = true
        packageFailure = nil
        Task {
            defer { packageOperationInProgress = false }
            do {
                var request = Anki_ImportExport_ImportAnkiPackageRequest()
                request.packagePath = url.path
                request.options = options
                let importRequest = request
                let log = try await backend.perform { try $0.importAnkiPackage(importRequest) }.log
                packageImportPresented = false
                importResult = ImportResult(log: log, fileName: url.lastPathComponent)
                await refreshDecks()
            } catch {
                // It stays on the sheet, beside its buttons, as desktop's page shows it.
                packageFailure = ActionFailure.reason(error)
            }
        }
    }

    /// Reads the file first, so the dialog opens with the backend's guesses, and an unreadable file
    /// is an error instead.
    private func presentCsvImport(_ url: URL) {
        guard let backend, isLoaded, !packageOperationInProgress else { return }
        Task {
            do {
                csvImport = try await CsvImportModel.load(url: url, backend: backend)
            } catch {
                failure = ActionFailure("Couldn’t read this file", error: error)
            }
        }
    }

    func importCsv(_ draft: CsvImportModel) {
        guard let backend, isLoaded, !packageOperationInProgress else { return }
        packageOperationInProgress = true
        let request = draft.importRequest
        Task {
            defer { packageOperationInProgress = false }
            do {
                let log = try await backend.perform { try $0.importCsv(request) }.log
                csvImport = nil
                importResult = ImportResult(log: log, fileName: draft.url.lastPathComponent)
                await refreshDecks()
            } catch {
                csvImport = nil
                failure = ActionFailure("Couldn’t import the file", error: error)
            }
        }
    }

    func export(format: ExportFormat, to url: URL, deckID: Int64?, selectedNoteIDs: [Int64]?,
                withScheduling: Bool, withDeckConfigs: Bool, withMedia: Bool, legacy: Bool,
                withHTML: Bool, withTags: Bool, withDeck: Bool, withNotetype: Bool, withGUID: Bool,
                notify: ((String) -> Void)? = nil) {
        guard let backend else { return }
        packageOperationInProgress = true
        packageFailure = nil
        Task {
            defer { packageOperationInProgress = false }
            do {
                // Desktop's tooltip once the file is written.
                let notice: String
                switch format {
                case .deckPackage:
                    var request = Anki_ImportExport_ExportAnkiPackageRequest()
                    request.outPath = url.path
                    var options = Anki_ImportExport_ExportAnkiPackageOptions()
                    options.withScheduling = withScheduling
                    options.withDeckConfigs = withDeckConfigs
                    options.withMedia = withMedia
                    options.legacy = legacy
                    request.options = options
                    request.limit = Self.exportLimit(deckID: deckID, noteIDs: selectedNoteIDs)
                    let exportRequest = request
                    let count = try await backend.perform { try $0.exportAnkiPackage(exportRequest) }.val
                    notice = Tr.exportingNoteExported(count: Int(count))
                case .collectionPackage:
                    var request = Anki_ImportExport_ExportCollectionPackageRequest()
                    request.outPath = url.path
                    request.includeMedia = withMedia
                    request.legacy = legacy
                    guard let paths else { throw CocoaError(.fileNoSuchFile) }
                    let exportRequest = request
                    // The backend closes the collection to write the package; reopen it.
                    collectionClosed = true
                    try await backend.perform { backend in
                        do { try backend.exportCollectionPackage(exportRequest) } catch {
                            try? Self.openCollection(backend, paths: paths)
                            throw error
                        }
                        try Self.openCollection(backend, paths: paths)
                    }
                    collectionClosed = false
                    await refreshDecks()
                    notice = Tr.exportingCollectionExported
                case .notes:
                    var request = Anki_ImportExport_ExportNoteCsvRequest()
                    request.outPath = url.path
                    request.withHtml = withHTML
                    request.withTags = withTags
                    request.withDeck = withDeck
                    request.withNotetype = withNotetype
                    request.withGuid = withGUID
                    request.limit = Self.exportLimit(deckID: deckID, noteIDs: selectedNoteIDs)
                    let exportRequest = request
                    let count = try await backend.perform { try $0.exportNoteCsv(exportRequest) }.val
                    notice = Tr.exportingNoteExported(count: Int(count))
                case .cards:
                    var request = Anki_ImportExport_ExportCardCsvRequest()
                    request.outPath = url.path
                    request.withHtml = withHTML
                    request.limit = Self.exportLimit(deckID: deckID, noteIDs: selectedNoteIDs)
                    let exportRequest = request
                    let count = try await backend.perform { try $0.exportCardCsv(exportRequest) }.val
                    notice = Tr.exportingCardExported(count: Int(count))
                }
                if let notify { notify(notice) } else { showNotice(notice) }
            } catch {
                collectionClosed = false
                packageFailure = ActionFailure.reason(error)
            }
        }
    }

    private static func exportLimit(deckID: Int64?, noteIDs: [Int64]?) -> Anki_ImportExport_ExportLimit {
        var limit = Anki_ImportExport_ExportLimit()
        if let noteIDs, !noteIDs.isEmpty {
            var ids = Anki_Notes_NoteIds()
            ids.noteIds = noteIDs
            limit.noteIds = ids
        } else if let deckID {
            limit.deckID = deckID
        } else {
            limit.wholeCollection = Anki_Generic_Empty()
        }
        return limit
    }

    nonisolated private static func openCollection(_ backend: AnkiBackend, paths: CollectionPaths) throws {
        var request = Anki_Collection_OpenCollectionRequest()
        request.collectionPath = paths.collection.path
        request.mediaFolderPath = paths.mediaFolder.path
        request.mediaDbPath = paths.mediaDB.path
        try backend.openCollection(request)
    }
}
