import AnkiKit
import AppKit
import SwiftUI

/// Tools › Check Database, Check Media and Empty Cards: each takes the check
/// the Tools menu started, with the backend's progress at the foot, and
/// reports on a sheet drawn as Deck Options' settings, with desktop's
/// actions. A check with nothing to report closes and says so in the
/// window's notice, as desktop's tooltip.
struct MaintenanceToolView: View {
    let model: CollectionModel
    let tool: MaintenanceTool
    @Environment(\.dismiss) private var dismiss
    @State private var busy = true
    /// What the backend says it's doing, or what's being done.
    @State private var progress: String?
    /// How far Check Database is through its stage, when it says.
    @State private var fraction: Double?
    /// The report has arrived, so its actions replace Cancel.
    @State private var loaded = false
    @State private var status: (text: String, level: WarningLevel)?
    @State private var problems: [String] = []
    @State private var media = Anki_Media_CheckMediaResponse()
    @State private var mediaReport = MediaReport()
    @State private var emptyCards = Anki_CardRendering_EmptyCardsReport()
    @State private var emptyNotes: [EmptyNotesGroup] = []
    @State private var keepNotes = false
    @State private var confirmTrash = false

    var body: some View {
        SettingsSheet(title: tool.title, width: Theme.Maintenance.width, maxHeight: Theme.Maintenance.maxHeight) {
            if loaded {
                switch tool {
                case .database: databaseReport
                case .media: mediaReportView
                case .emptyCards: emptyCardsReport
                }
            }
        } footer: {
            footer
        }
        .task { await run() }
        .confirmationDialog(Tr.mediaCheckDeleteUnusedConfirm, isPresented: $confirmTrash) {
            Button(Tr.mediaCheckDeleteUnused, role: .destructive) { trashUnused() }
            Button(Tr.actionsCancel, role: .cancel) {}
        }
    }

    // MARK: Reports

    /// What the check fixed, a row each.
    @ViewBuilder private var databaseReport: some View {
        if !problems.isEmpty {
            OptionSection {
                ForEach(problems.indices, id: \.self) { index in
                    Text(figures(problems[index]))
                        .font(Theme.DeckOptions.rowFont)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// The counts as rows, each with the actions on what it counts, then
    /// each list of files under upstream's sentence for it.
    @ViewBuilder private var mediaReportView: some View {
        OptionSection {
            ForEach(mediaReport.summary) { line in
                HStack(spacing: Theme.Spacing.small) {
                    Text(figures(line.text))
                        .font(Theme.DeckOptions.rowFont)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: Theme.Spacing.small)
                    mediaActions(for: line)
                }
            }
        }
        ForEach(mediaReport.sections) { section in
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    Text(figures(section.header))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.small)
                    CopyButton(lines: section.items)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(section.items.indices, id: \.self) { index in
                        Text(verbatim: section.items[index])
                            .font(Theme.Maintenance.rowFont)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(height: Theme.Maintenance.rowHeight)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    @ViewBuilder private func mediaActions(for line: MediaReport.Line) -> some View {
        Group {
            switch line.kind {
            case .missing? where !media.missing.isEmpty:
                Button(Tr.mediaCheckAddTag) { tagMissing() }
                // As desktop, when what's missing includes LaTeX's images.
                if media.missing.contains(where: { $0.hasPrefix("latex-") }) {
                    Button(Tr.mediaCheckRenderLatex) { renderLatex() }
                }
            case .unused? where !media.unused.isEmpty:
                Button(Tr.mediaCheckDeleteUnused) { confirmTrash = true }
            case .trash?:
                Button(Tr.mediaCheckRestoreTrash) { restoreTrash() }
                Button(Tr.mediaCheckEmptyTrash) { emptyTrash() }
            default:
                EmptyView()
            }
        }
        .buttonStyle(ChipButtonStyle())
        .disabled(busy)
    }

    /// Keep notes, then each note type's notes as dense rows. A note that
    /// would go with its cards reads red, as desktop's, until it's kept.
    @ViewBuilder private var emptyCardsReport: some View {
        OptionSection {
            OptionRow(title: Tr.emptyCardsPreserveNotesCheckbox, revertible: false) {
                SwitchControl(title: Tr.emptyCardsPreserveNotesCheckbox, isOn: $keepNotes)
            }
        }
        ForEach(emptyNotes) { group in
            VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                if !group.noteType.isEmpty {
                    Eyebrow(group.noteType)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Theme.Spacing.xSmall)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(group.notes) { note in
                        EmptyNoteRow(note: note, goes: note.wholeNote && !keepNotes) {
                            showInBrowser("nid:\(note.id)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer

    /// View Files for media, then what's happening or what came of it, then
    /// Cancel while the check runs and the report's buttons once it's in.
    @ViewBuilder private var footer: some View {
        if tool == .media, loaded {
            Button(Tr.addonsViewFiles) {
                if let folder = model.paths?.mediaFolder { NSWorkspace.shared.open(folder) }
            }
            .buttonStyle(ChipButtonStyle())
        }
        if busy {
            if let fraction {
                ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.small)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(progress ?? Tr.actionsProcessing)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
        } else if let status {
            OptionWarning(text: status.text, level: status.level).lineLimit(Theme.Maintenance.statusLines)
        }
        Spacer(minLength: Theme.Spacing.small)
        if !loaded {
            // Desktop can't stop a database check halfway.
            Button(Tr.actionsCancel, action: cancel)
                .buttonStyle(ChipButtonStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(tool == .database && busy)
        } else if tool == .emptyCards {
            // Deleting isn't the default, as desktop's, so it takes ⌘⌫, not Return.
            DialogButtons(
                action: Tr.emptyCardsDeleteButton, key: "\u{2318}\u{232B}",
                shortcut: KeyboardShortcut(.delete, modifiers: .command), disabled: busy, cancelDisabled: busy,
                cancel: { dismiss() }, submit: deleteEmptyCards)
        } else {
            CloseButton(disabled: busy) { dismiss() }
        }
    }

    // MARK: Running

    /// Takes the check the Tools menu started, or runs it again after an
    /// action, and shows its report. False when it failed.
    @MainActor @discardableResult private func run() async -> Bool {
        guard let backend = model.backend else {
            dismiss()
            return false
        }
        busy = true
        status = nil
        if tool == .database { progress = Tr.databaseCheckCheckingIntegrity }
        let poll = pollProgress(backend)
        defer {
            poll.cancel()
            progress = nil
            fraction = nil
            busy = false
        }
        do {
            let pending = model.maintenanceCheck
            model.maintenanceCheck = nil
            let report: MaintenanceReport
            if let pending {
                report = try await pending.value
            } else {
                report = try await tool.check(backend, backups: model.paths?.backups)
            }
            if tool == .database { await model.refreshDecks() }
            if let notice = report.nothingToReport {
                finish(notice)
                return true
            }
            switch report {
            case .database(let found):
                problems = found
                status = (Tr.databaseCheckRebuilt, .info)
            case .media(let response):
                media = response
                mediaReport = MediaReport(response)
            case .emptyCards(let report, let noteTypes):
                emptyCards = report
                emptyNotes = EmptyNotesGroup.parse(report, noteTypes: noteTypes)
            }
            loaded = true
            return true
        } catch let error as AnkiError where error.backend?.kind == .interrupted {
            dismiss()
            return false
        } catch {
            status = (ActionFailure.reason(error), .danger)
            return false
        }
    }

    /// Shows the backend's stage at the foot ("Checking cards...",
    /// "Checked 1,200...") until cancelled.
    private func pollProgress(_ backend: AnkiBackend) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Theme.DeckOptions.progressInterval)
                guard let latest = try? await backend.perform({ try $0.latestProgress() }), !Task.isCancelled
                else { continue }
                switch latest.value {
                case .databaseCheck(let check)? where !check.stage.isEmpty:
                    progress = check.stage
                    fraction = check.stageTotal > 0 ? min(Double(check.stageCurrent) / Double(check.stageTotal), 1) : nil
                case .mediaCheck(let text)? where !text.isEmpty: progress = text
                default: break
                }
            }
        }
    }

    private func cancel() {
        if tool == .media, busy, let backend = model.backend {
            // The check stops and throws, which closes the sheet.
            Task { try? await backend.perform { try $0.setWantsAbort() } }
        } else {
            dismiss()
        }
    }

    /// Nothing to report: the window says so, as desktop's tooltip.
    private func finish(_ notice: String) {
        model.showNotice(notice)
        dismiss()
    }

    // MARK: Actions

    private func trashUnused() {
        let names = media.unused
        act { backend in
            var request = Anki_Media_TrashMediaFilesRequest()
            request.fnames = names
            try backend.trashMediaFiles(request)
            return Tr.mediaCheckDeleteUnusedComplete(count: names.count)
        }
    }

    private func tagMissing() {
        let ids = media.missingMediaNotes
        act { backend in
            var request = Anki_Tags_NoteIdsAndTagsRequest()
            request.noteIds = ids
            request.tags = Tr.mediaCheckMissingMediaTag
            return Tr.browsingNotesUpdated(count: Int(try backend.addNoteTags(request).count))
        }
    }

    private func renderLatex() {
        guard let folder = model.paths?.mediaFolder else { return }
        act { backend in
            try LatexRenderer.renderMissing(backend, mediaFolder: folder) { checked in
                Task { @MainActor in progress = Tr.mediaCheckChecked(count: Tr.number(checked)) }
            }
            return Tr.mediaCheckAllLatexRendered
        }
    }

    private func emptyTrash() { act { try $0.emptyTrash(); return Tr.mediaCheckTrashEmptied } }
    private func restoreTrash() { act { try $0.restoreTrash(); return Tr.mediaCheckTrashRestored } }

    /// Runs a media action, then the check again, and says what it did.
    private func act(_ operation: @escaping @Sendable (AnkiBackend) throws -> String) {
        guard let backend = model.backend else { return }
        busy = true
        status = nil
        Task {
            do {
                let done = try await backend.perform(operation)
                await model.refreshDecks()
                // A failed check keeps its own message.
                if await run() { status = (done, .info) }
            } catch {
                busy = false
                progress = nil
                status = (ActionFailure.reason(error), .danger)
                // As desktop, the note whose LaTeX failed shows in the Browser.
                if let failure = error as? LatexRenderer.Failure { showInBrowser("nid:\(failure.noteID)") }
            }
        }
    }

    private func deleteEmptyCards() {
        guard let backend = model.backend else { return }
        let keep = keepNotes
        let ids = emptyCards.notes.flatMap { note in
            // Keeping the notes leaves their first card.
            keep && note.willDeleteNote ? Array(note.cardIds.dropFirst()) : note.cardIds
        }
        busy = true
        progress = Tr.emptyCardsDeleting
        status = nil
        Task {
            do {
                try await backend.perform { backend in
                    var request = Anki_Cards_RemoveCardsRequest()
                    request.cardIds = ids
                    _ = try backend.removeCards(request)
                }
                await model.refreshDecks()
                finish(Tr.emptyCardsDeletedCount(cards: ids.count))
            } catch {
                busy = false
                progress = nil
                status = (ActionFailure.reason(error), .danger)
            }
        }
    }

    private func showInBrowser(_ search: String) {
        BrowserWindowController.show(collection: model)
        BrowserWindowController.current?.model.search(text: search)
    }
}

/// A report's line in the row's face with each number in the rounded one,
/// as every count is.
private func figures(_ line: String) -> AttributedString {
    var text = AttributedString(line)
    for match in line.matches(of: #/\d+(?:[.,]\d+)*/#) {
        let start = text.characters.index(text.startIndex, offsetBy: line.distance(from: line.startIndex, to: match.range.lowerBound))
        let end = text.characters.index(start, offsetBy: match.output.count)
        text[start..<end].swiftUI.font = Theme.Maintenance.figures
    }
    return text
}

/// The sheet's one primary when there is nothing left to do but read:
/// Close, which Return and Esc both press, as a Mac alert's OK.
private struct CloseButton: View {
    let disabled: Bool
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            HStack(spacing: Theme.Layout.keyCapGap) {
                Text(Tr.actionsClose)
                KeyCap("\u{21A9}", onAccent: true)
            }
        }
        .buttonStyle(PrimaryButtonStyle(compact: true))
        .keyboardShortcut(.defaultAction)
        .disabled(disabled)
        .background {
            Button(Tr.actionsClose, action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(disabled)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

/// A note with empty cards: its id in rounded Pencil, as desktop links it,
/// then which cards are empty. A click shows it in the Browser, the arrow
/// appearing under the pointer as a row's actions do.
private struct EmptyNoteRow: View {
    let note: EmptyNote
    /// The note would be deleted with its cards.
    let goes: Bool
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: Theme.Spacing.small) {
                Text(verbatim: String(note.id))
                    .font(Theme.Maintenance.figures)
                    .foregroundStyle(Theme.Palette.secondary)
                Text(figures(note.text))
                    .font(Theme.Maintenance.rowFont)
                    .foregroundStyle(goes ? Theme.DeckOptions.dangerColor : Theme.Palette.text)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.small)
                Image(systemName: "arrow.up.forward.app")
                    .font(Theme.Maintenance.browseSymbol)
                    .foregroundStyle(Theme.Palette.secondary)
                    .opacity(hovered ? 1 : 0)
            }
            .padding(.horizontal, Theme.Spacing.small)
            .frame(height: Theme.Maintenance.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
            .fill(hovered ? Theme.Palette.hover : .clear))
        .padding(.horizontal, -Theme.Spacing.small)
        .onHover { hovered = $0 }
        .help(Tr.searchViewInBrowser)
        .accessibilityElement(children: .combine)
        // The red says the note goes with its cards; VoiceOver says it.
        .accessibilityValue(goes ? Tr.emptyCardsDeleteEmptyNotes : "")
        .accessibilityHint(Tr.searchViewInBrowser)
    }
}

/// Copies a report's list, a line each, as desktop's report could be.
private struct CopyButton: View {
    let lines: [String]

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(Theme.Maintenance.copySymbol)
                .frame(width: Theme.Maintenance.copySize.width, height: Theme.Maintenance.copySize.height)
        }
        .buttonStyle(QuietButtonStyle(inset: 0))
        .help(Tr.actionsCopy)
        .accessibilityLabel(Tr.actionsCopy)
    }
}

/// Check Media's report: the backend writes the counts as one paragraph,
/// then each list as a paragraph under its sentence, in the collection's
/// language. Which count is which comes from their fixed order, and the
/// missing and unused files from the response, so neither depends on the
/// wording.
private struct MediaReport {
    enum Kind { case trash, missing, unused }

    struct Line: Identifiable {
        let id: Int
        let text: String
        /// What the line counts, for the counts that have actions.
        let kind: Kind?
    }

    struct Section: Identifiable {
        let id: Int
        let header: String
        let items: [String]
    }

    var summary: [Line] = []
    var sections: [Section] = []

    /// What a template says before its first number or name.
    private static func lead(_ template: String) -> String { String(template.prefix { !$0.isNumber }) }
    private static let fileLeads = [
        Tr.mediaCheckOversizeFile(filename: "0"), Tr.mediaCheckSubfolderFile(filename: "0"),
        Tr.mediaCheckRenamedFile(old: "0", new: "0"),
    ].map { lead($0) }

    init() {}

    init(_ response: Anki_Media_CheckMediaResponse) {
        // Fluent's isolation marks around the numbers.
        let text = response.report.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.split(separator: "\n").map(String.init) }
            .filter { !$0.isEmpty }
        guard let first = paragraphs.first else { return }
        // The trash folder's count comes first when it has files, then the
        // missing and the unused files'.
        let kinds: [Kind] = (response.haveTrash ? [.trash] : []) + [.missing, .unused]
        summary = first.enumerated().map { index, line in
            Line(id: index, text: line, kind: kinds.indices.contains(index) ? kinds[index] : nil)
        }
        // The lists end with the missing files, then the unused ones, each
        // only when there are any, sorted as the backend sorts them.
        let lists = Array(paragraphs.dropFirst())
        var files = [[String]?](repeating: nil, count: lists.count)
        var last = lists.count - 1
        for names in [response.unused, response.missing] where !names.isEmpty && last >= 0 {
            files[last] = names.sorted()
            last -= 1
        }
        sections = lists.enumerated().map { index, lines in
            Section(id: index, header: lines[0], items: files[index] ?? lines.dropFirst().map(Self.fileName))
        }
    }

    /// A renamed, oversized or subfolder file's line without upstream's
    /// lead, when it's in English; otherwise as written.
    private static func fileName(_ line: String) -> String {
        guard let lead = fileLeads.first(where: { !$0.isEmpty && line.hasPrefix($0) }) else { return line }
        return String(line.dropFirst(lead.count))
    }
}

private struct EmptyNote: Identifiable {
    let id: Int64
    let text: String
    /// Every card of the note is empty, so it goes with them.
    let wholeNote: Bool
}

/// Empty Cards' report is HTML from the backend: a bold line per note type,
/// then one `[anki:nid:ID] text` item per note.
private struct EmptyNotesGroup: Identifiable {
    let id: Int
    var noteType: String
    var notes: [EmptyNote]

    private static let item = /<div><b>(.*?)<\/b><\/div>|<li class=(\S*)>\[anki:nid:(\d+)\] (.*?)<\/li>/

    /// Each group is named by its notes' note type, since the report's
    /// "Empty cards for Basic:" is in the collection's language.
    static func parse(_ report: Anki_CardRendering_EmptyCardsReport, noteTypes: [Int64: String]) -> [EmptyNotesGroup] {
        // Failing that, an English heading loses all but the note type.
        let template = Tr.emptyCardsForNoteType(notetype: "\u{0}").components(separatedBy: "\u{0}")
        var groups: [EmptyNotesGroup] = []
        for match in report.report.matches(of: item) {
            if let heading = match.output.1.map(String.init) {
                var name = heading
                if template.count == 2, name.hasPrefix(template[0]), name.hasSuffix(template[1]) {
                    name = String(name.dropFirst(template[0].count).dropLast(template[1].count))
                }
                groups.append(EmptyNotesGroup(id: groups.count, noteType: name, notes: []))
            } else if let nid = match.output.3.flatMap({ Int64($0) }), let text = match.output.4 {
                if groups.isEmpty { groups.append(EmptyNotesGroup(id: 0, noteType: "", notes: [])) }
                groups[groups.count - 1].notes.append(
                    EmptyNote(id: nid, text: String(text), wholeNote: match.output.2 == "allempty"))
            }
        }
        if groups.isEmpty {
            // A report this can't read still lists the notes.
            let notes = report.notes.map { EmptyNote(id: $0.noteID, text: "", wholeNote: $0.willDeleteNote) }
            groups = [EmptyNotesGroup(id: 0, noteType: "", notes: notes)]
        }
        // A group under a heading holds one note type's notes.
        for index in groups.indices where !groups[index].noteType.isEmpty {
            if let note = groups[index].notes.first, let name = noteTypes[note.id] { groups[index].noteType = name }
        }
        return groups
    }
}
