import AnkiKit
import AppKit
import SwiftUI

/// Tools › Check Database, Check Media and Empty Cards: each runs on
/// appearing and reports in a sheet, with desktop's actions.
struct MaintenanceToolView: View {
    let model: CollectionModel
    let tool: MaintenanceTool
    @Environment(\.dismiss) private var dismiss
    @State private var busy = true
    @State private var lines: [ReportLine] = []
    @State private var status: String?
    @State private var media = Anki_Media_CheckMediaResponse()
    @State private var emptyCards = Anki_CardRendering_EmptyCardsReport()
    @State private var keepNotes = false
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text(tool.title).font(.title2.weight(.semibold))
            if busy {
                ProgressView(tool == .database ? Tr.databaseCheckCheckingIntegrity : Tr.actionsProcessing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                reportList
            }
            if let status { Text(status).foregroundStyle(.secondary) }
            if tool == .emptyCards, !emptyCards.notes.isEmpty {
                Toggle(Tr.emptyCardsPreserveNotesCheckbox, isOn: $keepNotes)
            }
            HStack {
                if tool == .media { mediaButtons }
                Spacer()
                Button(Tr.actionsClose) { dismiss() }.keyboardShortcut(.cancelAction)
                if tool == .emptyCards, !emptyCards.notes.isEmpty {
                    Button(Tr.emptyCardsDeleteButton) { deleteEmptyCards() }
                        .keyboardShortcut(.defaultAction).disabled(busy)
                }
            }
        }
        .padding(Theme.Spacing.large)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 480)
        .task { await run() }
        .confirmationDialog(Tr.mediaCheckDeleteUnusedConfirm, isPresented: $confirmTrash) {
            Button(Tr.mediaCheckDeleteUnused, role: .destructive) { trashUnused() }
            Button(Tr.actionsCancel, role: .cancel) {}
        }
    }

    private var reportList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(lines) { line in
                    if let noteID = line.noteID {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Button(String(noteID)) { showInBrowser("nid:\(noteID)") }.buttonStyle(.link)
                            Text(line.text).foregroundStyle(line.allEmpty ? .red : .primary)
                        }
                    } else {
                        Text(line.text).fontWeight(line.heading ? .semibold : .regular)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.medium)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var mediaButtons: some View {
        if !media.unused.isEmpty {
            Button(Tr.mediaCheckDeleteUnused) { confirmTrash = true }
        }
        if !media.missing.isEmpty {
            Button(Tr.mediaCheckAddTag) { tagMissing() }
        }
        if media.haveTrash {
            Button(Tr.mediaCheckEmptyTrash) { emptyTrash() }
            Button(Tr.mediaCheckRestoreTrash) { restoreTrash() }
        }
        Button("View Files") {
            if let folder = model.paths?.mediaFolder { NSWorkspace.shared.open(folder) }
        }
    }

    @MainActor private func run() async {
        guard let backend = model.backend else { busy = false; return }
        busy = true
        do {
            switch tool {
            case .database:
                let folder = model.paths?.backups
                let problems = try await backend.perform { backend in
                    // Desktop backs up first; the check can't be undone.
                    if let folder { _ = try? backend.backUp(.manual, to: folder) }
                    return try backend.checkDatabase().problems
                }
                lines = (problems + [Tr.databaseCheckRebuilt]).map { ReportLine(text: $0) }
                await model.refreshDecks()
            case .media:
                media = try await backend.perform { try $0.checkMedia() }
                lines = media.report.split(separator: "\n", omittingEmptySubsequences: false).map { ReportLine(text: String($0)) }
            case .emptyCards:
                emptyCards = try await backend.perform { try $0.getEmptyCards() }
                lines = emptyCards.notes.isEmpty ? [ReportLine(text: Tr.emptyCardsNotFound)] : ReportLine.parse(emptyCards.report)
            }
        } catch {
            lines = [ReportLine(text: "\(error)")]
        }
        busy = false
    }

    private func trashUnused() {
        let names = media.unused
        act(Tr.mediaCheckDeleteUnusedComplete(count: names.count)) { backend in
            var request = Anki_Media_TrashMediaFilesRequest()
            request.fnames = names
            try backend.trashMediaFiles(request)
        }
    }

    private func tagMissing() {
        let ids = media.missingMediaNotes
        act(nil) { backend in
            var request = Anki_Tags_NoteIdsAndTagsRequest()
            request.noteIds = ids
            request.tags = Tr.mediaCheckMissingMediaTag
            _ = try backend.addNoteTags(request)
        }
    }

    private func emptyTrash() { act(Tr.mediaCheckTrashEmptied) { try $0.emptyTrash() } }
    private func restoreTrash() { act(Tr.mediaCheckTrashRestored) { try $0.restoreTrash() } }

    private func deleteEmptyCards() {
        let keep = keepNotes
        let ids = emptyCards.notes.flatMap { note in
            // Keeping the notes leaves their first card.
            keep && note.willDeleteNote ? Array(note.cardIds.dropFirst()) : note.cardIds
        }
        act(Tr.emptyCardsDeletedCount(cards: ids.count), then: { dismiss() }) { backend in
            var request = Anki_Cards_RemoveCardsRequest()
            request.cardIds = ids
            _ = try backend.removeCards(request)
        }
    }

    /// Runs an operation, then the check again (or `then`), and refreshes the deck list.
    private func act(
        _ done: String?, then: (@MainActor () -> Void)? = nil,
        _ operation: @escaping @Sendable (AnkiBackend) throws -> Void
    ) {
        guard let backend = model.backend else { return }
        busy = true
        Task {
            do {
                try await backend.perform(operation)
                await model.refreshDecks()
                if let then { then() } else { await run() }
                status = done
            } catch {
                busy = false
                status = "\(error)"
            }
        }
    }

    private func showInBrowser(_ search: String) {
        BrowserWindowController.show(collection: model)
        BrowserWindowController.current?.model.search(text: search)
    }
}

/// One line of a report. The empty cards report is HTML from the backend:
/// a bold line per note type, then one `[anki:nid:ID] text` item per note.
private struct ReportLine: Identifiable {
    let id = UUID()
    var text: String
    var heading = false
    var noteID: Int64?
    var allEmpty = false

    static func parse(_ html: String) -> [ReportLine] {
        var result: [ReportLine] = []
        let pattern = /<div><b>(.*?)<\/b><\/div>|<li class=(\S*)>\[anki:nid:(\d+)\] (.*?)<\/li>/
        for match in html.matches(of: pattern) {
            if let heading = match.output.1 {
                result.append(ReportLine(text: String(heading), heading: true))
            } else if let nid = match.output.3.flatMap({ Int64($0) }), let text = match.output.4 {
                result.append(
                    ReportLine(text: String(text), noteID: nid, allEmpty: match.output.2 == "allempty"))
            }
        }
        return result.isEmpty ? [ReportLine(text: html)] : result
    }
}
