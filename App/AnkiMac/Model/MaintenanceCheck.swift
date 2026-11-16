import AnkiKit
import Foundation

/// What a Tools check found.
nonisolated enum MaintenanceReport: Sendable {
    /// What Check Database fixed.
    case database([String])
    case media(Anki_Media_CheckMediaResponse)
    /// The empty cards, with each listed note's note type by name, since
    /// the report names them in the backend's language.
    case emptyCards(Anki_CardRendering_EmptyCardsReport, noteTypes: [Int64: String])

    /// The notice for a check with nothing to report, as desktop's tooltip.
    var nothingToReport: String? {
        switch self {
        case .database(let problems): problems.isEmpty ? Tr.databaseCheckRebuilt : nil
        case .media: nil
        case .emptyCards(let report, _): report.notes.isEmpty ? Tr.emptyCardsNotFound : nil
        }
    }
}

extension MaintenanceTool {
    /// Runs the check. Check Database backs up first, as desktop does, since
    /// what it fixes can't be undone.
    nonisolated func check(_ backend: AnkiBackend, backups: URL?) async throws -> MaintenanceReport {
        switch self {
        case .database:
            .database(try await backend.perform { backend in
                if let backups { _ = try? backend.backUp(.manual, to: backups) }
                return try backend.checkDatabase().problems
            })
        case .media:
            .media(try await backend.perform { try $0.checkMedia() })
        case .emptyCards:
            try await backend.perform { backend in
                let report = try backend.getEmptyCards()
                return .emptyCards(report, noteTypes: try Self.noteTypes(of: report.notes.map(\.noteID), backend))
            }
        }
    }

    private nonisolated static func noteTypes(of notes: [Int64], _ backend: AnkiBackend) throws -> [Int64: String] {
        guard !notes.isEmpty else { return [:] }
        let names = Dictionary(
            try backend.getNotetypeNames().entries.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let query: [String: Any] = [
            "kind": "query", "args": [], "first_row_only": false,
            "sql": "select id, mid from notes where id in (\(notes.map(String.init).joined(separator: ",")))",
        ]
        let reply = try backend.dbCommand(try JSONSerialization.data(withJSONObject: query))
        var noteTypes: [Int64: String] = [:]
        for row in (try JSONSerialization.jsonObject(with: reply) as? [[Any]]) ?? [] {
            guard row.count == 2, let nid = (row[0] as? NSNumber)?.int64Value,
                let mid = (row[1] as? NSNumber)?.int64Value
            else { continue }
            noteTypes[nid] = names[mid]
        }
        return noteTypes
    }
}

extension CollectionModel {
    /// Starts a Tools check. Its sheet opens once the check has run for a
    /// moment, or as soon as it has something to report, so a quick check
    /// that finds nothing only says so in the notice, as desktop's progress
    /// window shows only for slow work.
    func runMaintenance(_ tool: MaintenanceTool) {
        guard let backend, maintenanceTool == nil, maintenanceCheck == nil else { return }
        let backups = paths?.backups
        let check = Task { try await tool.check(backend, backups: backups) }
        maintenanceCheck = check
        Task {
            try? await Task.sleep(for: Theme.Maintenance.sheetDelay)
            if maintenanceCheck == check, maintenanceTool == nil { maintenanceTool = tool }
        }
        Task {
            let report = try? await check.value
            // Once the sheet is open, it has the check.
            guard maintenanceCheck == check, maintenanceTool == nil else { return }
            if let report, let notice = report.nothingToReport {
                maintenanceCheck = nil
                if tool == .database { await refreshDecks() }
                showNotice(notice)
            } else {
                maintenanceTool = tool
            }
        }
    }
}
