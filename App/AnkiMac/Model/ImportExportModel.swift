import AnkiKit
import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// Counts from an import's log, shown as desktop's Import Log does.
struct ImportResult: Identifiable, Equatable {
    let id = UUID()
    let found: Int
    let new: Int
    let updated: Int
    let duplicate: Int
    let conflicting: Int
    let failed: Int
    let mergedNotetypes: Bool

    init(log: Anki_ImportExport_ImportResponse.Log, mergedNotetypes: Bool) {
        // Text files log a first-field match apart. Desktop counts it with the notes the resolution
        // adds, updates or skips.
        let matched = log.firstFieldMatch.count
        found = Int(log.foundNotes)
        new = log.new.count + (log.dupeResolution == .duplicate ? matched : 0)
        updated = log.updated.count + (log.dupeResolution == .update ? matched : 0)
        duplicate = log.duplicate.count + (log.dupeResolution == .preserve ? matched : 0)
        conflicting = log.conflicting.count
        failed = log.missingNotetype.count + log.missingDeck.count + log.emptyFirstField.count
        self.mergedNotetypes = mergedNotetypes
    }
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
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = Tr.importingThisWillDeleteYourExistingCollection
            alert.addButton(withTitle: Tr.actionsImport)
            alert.addButton(withTitle: Tr.actionsCancel)
            alert.buttons[0].hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            replaceCollection(from: url)
        case "apkg", "zip":
            packageImportURL = url
            packageImportPresented = true
        case "csv", "txt", "tsv":
            presentCsvImport(url)
        default:
            errorMessage = "Unsupported file type. Choose an .apkg or .colpkg file."
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
                    importMessage = Tr.importingImportingComplete
                }
            } catch {
                collectionClosed = false
                await refreshDecks()
                errorMessage = FilteredDeckModel.message(error)
            }
        }
    }

    func importPackage(_ url: URL, options: Anki_ImportExport_ImportAnkiPackageOptions) {
        guard let backend, isLoaded, !packageOperationInProgress else { return }
        packageOperationInProgress = true
        Task {
            defer { packageOperationInProgress = false }
            do {
                var request = Anki_ImportExport_ImportAnkiPackageRequest()
                request.packagePath = url.path
                request.options = options
                let importRequest = request
                let log = try await backend.perform { try $0.importAnkiPackage(importRequest) }.log
                packageImportPresented = false
                importResult = ImportResult(log: log, mergedNotetypes: options.mergeNotetypes)
                await refreshDecks()
            } catch {
                packageImportPresented = false
                errorMessage = FilteredDeckModel.message(error)
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
                errorMessage = FilteredDeckModel.message(error)
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
                importResult = ImportResult(log: log, mergedNotetypes: false)
                await refreshDecks()
            } catch {
                csvImport = nil
                errorMessage = FilteredDeckModel.message(error)
            }
        }
    }

    func export(format: ExportFormat, to url: URL, deckID: Int64?, selectedNoteIDs: [Int64]?,
                withScheduling: Bool, withDeckConfigs: Bool, withMedia: Bool, legacy: Bool,
                withHTML: Bool, withTags: Bool, withDeck: Bool, withNotetype: Bool, withGUID: Bool) {
        guard let backend else { return }
        packageOperationInProgress = true
        Task {
            defer { packageOperationInProgress = false }
            do {
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
                    _ = try await backend.perform { try $0.exportAnkiPackage(exportRequest) }
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
                    _ = try await backend.perform { try $0.exportNoteCsv(exportRequest) }
                case .cards:
                    var request = Anki_ImportExport_ExportCardCsvRequest()
                    request.outPath = url.path
                    request.withHtml = withHTML
                    request.limit = Self.exportLimit(deckID: deckID, noteIDs: selectedNoteIDs)
                    let exportRequest = request
                    _ = try await backend.perform { try $0.exportCardCsv(exportRequest) }
                }
            } catch {
                collectionClosed = false
                errorMessage = FilteredDeckModel.message(error)
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
