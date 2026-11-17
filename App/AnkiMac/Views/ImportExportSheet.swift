import AnkiKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File › Export… and the Browser's Export Notes…, with desktop's formats and
/// options, drawn as Deck Options' settings: the format and what to include
/// as quiet menus, the format's options as switches, then Cancel and Export.
struct ImportExportSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let selectedNoteIDs: [Int64]?
    /// Takes the sheet down when AppKit presented it, out of SwiftUI's reach.
    var close: (() -> Void)?
    /// Says what was exported; the main window's notice when nil.
    var notify: ((String) -> Void)?

    // Desktop's defaults, from its exporting.ui and ExportDialog.
    @State private var format: ExportFormat
    @State private var deckID: Int64?
    @State private var withScheduling: Bool
    @State private var withDeckConfigs = false
    @State private var withMedia = true
    @State private var legacy = false
    @State private var withHTML = true
    @State private var withTags = true
    @State private var withDeck = false
    @State private var withNotetype = false
    @State private var withGUID = false
    @State private var started = false

    init(
        selectedNoteIDs: [Int64]?, initialDeckID: Int64?, close: (() -> Void)? = nil,
        notify: ((String) -> Void)? = nil
    ) {
        self.selectedNoteIDs = selectedNoteIDs
        self.close = close
        self.notify = notify
        _format = State(initialValue: selectedNoteIDs == nil ? .deckPackage : .notes)
        _deckID = State(initialValue: initialDeckID)
        // A deck's own export leaves its scheduling out, as desktop's.
        _withScheduling = State(initialValue: initialDeckID == nil)
    }

    private var formats: [ExportFormat] {
        // A selection of notes can't be a whole-collection package.
        selectedNoteIDs == nil ? ExportFormat.allCases : ExportFormat.allCases.filter { $0 != .collectionPackage }
    }

    var body: some View {
        SettingsSheet(
            eyebrow: selectedNoteIDs.map { Tr.browsingNoteCount(count: $0.count) } ?? "",
            title: Tr.actionsExport, width: Theme.ImportExport.width
        ) {
            OptionSection {
                OptionRow(title: rowTitle(Tr.exportingExportFormat), revertible: false) {
                    OptionPicker(selection: $format, choices: formats.map { ($0, $0.title) })
                }
                // A collection package holds every deck, so there's nothing to include.
                if format != .collectionPackage {
                    OptionRow(title: rowTitle(Tr.exportingInclude), revertible: false) {
                        if selectedNoteIDs != nil {
                            Text(Tr.exportingSelectedNotes)
                                .font(Theme.DeckOptions.rowFont)
                                .foregroundStyle(Theme.Palette.secondary)
                        } else {
                            deckMenu
                        }
                    }
                }
                optionRows
            }
            .disabled(model.packageOperationInProgress)
        } footer: {
            if model.packageOperationInProgress {
                ProgressView().controlSize(.small)
                Text(Tr.exportingExportingFile)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            } else if let failure = model.packageFailure {
                OptionWarning(text: failure, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(
                action: Tr.exportingExport, disabled: model.packageOperationInProgress,
                cancelDisabled: model.packageOperationInProgress, cancel: finish, submit: save)
        }
        .task { model.packageFailure = nil }
        // A failure stays on the sheet, beside its buttons, so it can be tried again.
        .onChange(of: model.packageOperationInProgress) { _, running in
            if started && !running && model.packageFailure == nil { finish() }
        }
        .onChange(of: format) { model.packageFailure = nil }
        .modifier(PackageProgressAnnouncements(status: Tr.exportingExportingFile))
    }

    private func finish() {
        if let close { close() } else { dismiss() }
    }

    @ViewBuilder private var optionRows: some View {
        switch format {
        case .deckPackage:
            switchRow(Tr.exportingIncludeSchedulingInformation, isOn: $withScheduling)
            switchRow(Tr.exportingIncludeDeckConfigs, isOn: $withDeckConfigs)
            switchRow(Tr.exportingIncludeMedia, isOn: $withMedia)
            switchRow(Tr.exportingSupportOlderAnkiVersions, isOn: $legacy)
        case .collectionPackage:
            switchRow(Tr.exportingIncludeMedia, isOn: $withMedia)
            switchRow(Tr.exportingSupportOlderAnkiVersions, isOn: $legacy)
        case .notes:
            switchRow(Tr.exportingIncludeHtmlAndMediaReferences, isOn: $withHTML)
            switchRow(Tr.exportingIncludeTags, isOn: $withTags)
            switchRow(Tr.exportingIncludeDeck, isOn: $withDeck)
            switchRow(Tr.exportingIncludeNotetype, isOn: $withNotetype)
            switchRow(Tr.exportingIncludeGuid, isOn: $withGUID)
        case .cards:
            switchRow(Tr.exportingIncludeHtmlAndMediaReferences, isOn: $withHTML)
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        OptionRow(title: title, revertible: false) { SwitchControl(title: title, isOn: isOn) }
    }

    /// All Decks, then the deck tree as nested menus, as Add's.
    private var deckMenu: some View {
        let name = deckID.flatMap(model.deck)?.name ?? Tr.exportingAllDecks
        return Menu {
            Toggle(Tr.exportingAllDecks, isOn: Binding { deckID == nil } set: { _ in deckID = nil })
            Divider()
            DeckMenuItems(decks: model.decks, current: deckID, pick: { deckID = $0 })
        } label: {
            QuietMenuLabel(value: name.replacingOccurrences(of: "::", with: " \u{203A} "), truncation: .head)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.trailing, -Theme.Layout.menuPadding)
        .accessibilityLabel(rowTitle(Tr.exportingInclude))
        // The path's parents read as a list, not as "colon colon".
        .accessibilityValue(name.replacingOccurrences(of: "::", with: ", "))
    }

    /// Desktop's file name: the deck as the menu names it, with what a file
    /// name can't hold made "_", or a collection stamped with the time.
    private var fileName: String {
        let stem: String
        if format == .collectionPackage {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd@HH-mm-ss"
            stem = Tr.exportingCollection + "-" + formatter.string(from: .now)
        } else {
            let deck = selectedNoteIDs != nil ? Tr.exportingSelectedNotes
                : deckID.flatMap(model.deck)?.name ?? Tr.exportingAllDecks
            stem = deck.replacing(/[\\\/?<>:*|"^]/, with: "_")
        }
        return stem + "." + format.extensionName
    }

    /// The save panel is a sheet on this one, so nothing here changes while it's open.
    private func save() {
        let panel = NSSavePanel()
        panel.title = Tr.actionsExport
        if let type = UTType(filenameExtension: format.extensionName) { panel.allowedContentTypes = [type] }
        panel.nameFieldStringValue = fileName
        let export = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            started = true
            model.export(format: format, to: url, deckID: selectedNoteIDs == nil ? deckID : nil,
                selectedNoteIDs: selectedNoteIDs, withScheduling: withScheduling,
                withDeckConfigs: withDeckConfigs, withMedia: withMedia, legacy: legacy,
                withHTML: withHTML, withTags: withTags, withDeck: withDeck,
                withNotetype: withNotetype, withGUID: withGUID, notify: notify)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: export)
        } else {
            panel.begin(completionHandler: export)
        }
    }
}

/// VoiceOver hears what the foot shows: the work starting, then why it
/// failed. Success closes the sheet and the window's notice says it.
private struct PackageProgressAnnouncements: ViewModifier {
    @Environment(CollectionModel.self) private var model
    let status: String

    func body(content: Content) -> some View {
        content
            .onChange(of: model.packageOperationInProgress) { _, running in
                if running { AccessibilityNotification.Announcement(status).post() }
            }
            .onChange(of: model.packageFailure) { _, failure in
                if let failure { AccessibilityNotification.Announcement(failure).post() }
            }
    }
}

/// Options for importing an .apkg, as desktop's import page offers them:
/// the file's name as the Headline, then Import options and Updates under
/// their eyebrows, as the text import sheet's sections.
struct ImportOptionsSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var options: Anki_ImportExport_ImportAnkiPackageOptions

    init(url: URL, presets: Anki_ImportExport_ImportAnkiPackageOptions) {
        self.url = url
        _options = State(initialValue: presets)
    }

    var body: some View {
        SettingsSheet(title: url.lastPathComponent, width: Theme.ImportExport.width) {
            Group {
                OptionSection(
                    title: Tr.importingImportOptions,
                    help: [
                        (Tr.importingAlsoImportProgress, Tr.importingIncludeReviewsHelp),
                        (Tr.importingWithDeckConfigs, Tr.importingWithDeckConfigsHelp),
                    ]
                ) {
                    switchRow(Tr.importingAlsoImportProgress, help: Tr.importingIncludeReviewsHelp,
                        isOn: $options.withScheduling)
                    switchRow(Tr.importingWithDeckConfigs, help: Tr.importingWithDeckConfigsHelp,
                        isOn: $options.withDeckConfigs)
                }
                OptionSection(
                    title: Tr.importingUpdates,
                    help: [
                        (Tr.importingMergeNotetypes, Tr.importingMergeNotetypesHelp),
                        (Tr.importingUpdateNotes, Tr.importingUpdateNotesHelp),
                        (Tr.importingUpdateNotetypes, Tr.importingUpdateNotetypesHelp),
                    ]
                ) {
                    switchRow(Tr.importingMergeNotetypes, help: Tr.importingMergeNotetypesHelp,
                        isOn: $options.mergeNotetypes)
                    OptionRow(title: Tr.importingUpdateNotes, help: Tr.importingUpdateNotesHelp, revertible: false) {
                        OptionPicker(selection: $options.updateNotes, choices: updateChoices)
                    }
                    OptionRow(
                        title: Tr.importingUpdateNotetypes, help: Tr.importingUpdateNotetypesHelp, revertible: false
                    ) {
                        OptionPicker(selection: $options.updateNotetypes, choices: updateChoices)
                    }
                }
            }
            .disabled(model.packageOperationInProgress)
        } footer: {
            if model.packageOperationInProgress {
                ProgressView().controlSize(.small)
                Text(Tr.actionsProcessing)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            } else if let failure = model.packageFailure {
                OptionWarning(text: failure, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(
                action: Tr.actionsImport, disabled: model.packageOperationInProgress,
                cancelDisabled: model.packageOperationInProgress, cancel: { dismiss() },
                submit: { model.importPackage(url, options: options) })
        }
        .onChange(of: options) { model.packageFailure = nil }
        .modifier(PackageProgressAnnouncements(status: Tr.actionsProcessing))
    }

    private func switchRow(_ title: String, help: String, isOn: Binding<Bool>) -> some View {
        OptionRow(title: title, help: help, revertible: false) { SwitchControl(title: title, isOn: isOn) }
    }

    private var updateChoices: [(Anki_ImportExport_ImportAnkiPackageUpdateCondition, String)] {
        [(.ifNewer, Tr.importingUpdateIfNewer), (.always, Tr.importingUpdateAlways), (.never, Tr.importingUpdateNever)]
    }
}

/// Desktop's Import Log: how many notes the file held, what became of them
/// as rows with Show as a chip, then every note as a dense row with its
/// status, as desktop's details table. A click shows a note in the Browser.
struct ImportLogSheet: View {
    @Environment(CollectionModel.self) private var model
    let result: ImportResult
    @State private var statusWidth: CGFloat = 0

    private var summaries: [ImportSummary] { result.summaries.filter { !$0.notes.isEmpty } }

    var body: some View {
        SettingsSheet(
            eyebrow: result.fileName, title: Tr.importingImportLog, width: Theme.ImportExport.width,
            maxHeight: Theme.ImportExport.logMaxHeight
        ) {
            OptionSection(title: Tr.importingOverview) {
                Text(figures(result.found == 0 ? Tr.importingNoNotesInFile
                    : Tr.importingNotesFoundInFile2(notes: result.found)))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .optionNote()
                ForEach(summaries) { summary in
                    summaryRow(summary)
                }
            }
            if !summaries.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    Eyebrow(Tr.importingDetails)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Theme.Spacing.xSmall)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(summaries) { summary in
                            ForEach(summary.notes) { note in
                                ImportedNoteRow(note: note, status: summary.status, statusWidth: statusWidth,
                                    open: summary.canBrowse ? { show([note]) } : nil)
                            }
                        }
                    }
                    // The status column is as wide as its widest word in
                    // this language; the lazy rows can't all be measured.
                    .background(alignment: .leading) {
                        ZStack {
                            ForEach(summaries) { Text($0.status).font(Theme.Maintenance.rowFont) }
                        }
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { statusWidth = $0 }
                    }
                }
            }
        } footer: {
            Spacer(minLength: Theme.Spacing.small)
            CloseButton(disabled: false) { model.importResult = nil }
        }
    }

    /// An outcome's glyph, as desktop's, then its sentence and Show.
    private func summaryRow(_ summary: ImportSummary) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: symbol(summary.kind))
                .font(Theme.ImportExport.summarySymbol)
                .foregroundStyle(summary.kind == .failed ? Theme.DeckOptions.dangerColor : Theme.Palette.secondary)
                .frame(width: Theme.ImportExport.summarySymbolWidth)
                .accessibilityHidden(true)
            Text(figures(summary.summary(count: summary.notes.count)))
                .font(Theme.DeckOptions.rowFont)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Spacer(minLength: Theme.Spacing.small)
            if summary.canBrowse {
                Button(Tr.importingShow) { show(summary.notes) }
                    .buttonStyle(ChipButtonStyle())
            }
        }
    }

    private func symbol(_ kind: ImportSummary.Kind) -> String {
        switch kind {
        case .added: "plus.square"
        case .skipped: "checkmark.circle"
        case .updated: "arrow.triangle.2.circlepath"
        case .failed: "xmark.square"
        }
    }

    private func show(_ notes: [ImportedNote]) {
        BrowserWindowController.show(collection: model)
        BrowserWindowController.current?.model.search(
            text: "nid:" + notes.map { String($0.noteID) }.joined(separator: ","))
    }
}

/// A note in the log: its status in Pencil, as desktop's details table
/// heads the row, then its fields in Ink, with desktop's reason as the help
/// tag. A note that was imported shows in the Browser on a click, the arrow
/// appearing under the pointer as Empty Cards' rows.
private struct ImportedNoteRow: View {
    let note: ImportedNote
    let status: String
    let statusWidth: CGFloat
    let open: (() -> Void)?
    @State private var hovered = false

    var body: some View {
        Group {
            if let open {
                Button(action: open) { label }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
                        .fill(hovered ? Theme.Palette.hover : .clear))
                    .onHover { hovered = $0 }
                    .accessibilityHint(Tr.searchViewInBrowser)
            } else {
                label
            }
        }
        .padding(.horizontal, -Theme.Spacing.small)
        .help(note.reason)
        .accessibilityElement(children: .combine)
        .accessibilityValue(note.reason)
    }

    private var label: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(status)
                .font(Theme.Maintenance.rowFont)
                .foregroundStyle(Theme.Palette.secondary)
                .lineLimit(1)
                .frame(width: statusWidth, alignment: .leading)
            Text(verbatim: note.fields)
                .font(Theme.Maintenance.rowFont)
                .foregroundStyle(Theme.Palette.text)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.small)
            if open != nil {
                Image(systemName: "arrow.up.forward.app")
                    .font(Theme.Maintenance.browseSymbol)
                    .foregroundStyle(Theme.Palette.secondary)
                    .opacity(hovered ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.small)
        .frame(height: Theme.Maintenance.rowHeight)
        .contentShape(.rect)
    }
}
