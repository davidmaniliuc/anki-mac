import AnkiKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File > Export… and the Browser's Export Notes…, with desktop's formats and options.
struct ImportExportSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let selectedNoteIDs: [Int64]?
    let initialDeckID: Int64?

    @State private var format: ExportFormat = .deckPackage
    @State private var deckID: Int64?
    @State private var withScheduling = false
    @State private var withDeckConfigs = false
    @State private var withMedia = true
    @State private var legacy = false
    @State private var withHTML = false
    @State private var withTags = true
    @State private var withDeck = true
    @State private var withNotetype = true
    @State private var withGUID = false
    @State private var started = false

    private var formats: [ExportFormat] {
        // A selection of notes can't be a whole-collection package.
        selectedNoteIDs == nil ? ExportFormat.allCases : ExportFormat.allCases.filter { $0 != .collectionPackage }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text(Tr.actionsExport).font(.title2.weight(.semibold))
            Form {
                Picker(plain(Tr.exportingExportFormat), selection: $format) {
                    ForEach(formats) { Text($0.title).tag($0) }
                }
                if selectedNoteIDs != nil {
                    LabeledContent(Tr.decksDeck, value: Tr.exportingSelectedNotes)
                } else if format != .collectionPackage {
                    Picker(Tr.decksDeck, selection: $deckID) {
                        Text(Tr.exportingAllDecks).tag(Int64?.none)
                        ForEach(flatDecks, id: \.id) { Text($0.fullName).tag(Optional($0.id)) }
                    }
                }
                optionsView
            }
            .formStyle(.grouped)
            HStack {
                if model.packageOperationInProgress {
                    ProgressView().controlSize(.small)
                    Text(Tr.exportingExportingFile).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Tr.actionsCancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.packageOperationInProgress)
                Button(Tr.exportingExport, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.packageOperationInProgress)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: 480)
        .task {
            deckID = initialDeckID
            if selectedNoteIDs != nil { format = .notes }
        }
        .onChange(of: model.packageOperationInProgress) { _, running in
            if started && !running { dismiss() }
        }
    }

    @ViewBuilder private var optionsView: some View {
        switch format {
        case .deckPackage:
            Toggle(Tr.exportingIncludeSchedulingInformation, isOn: $withScheduling)
            Toggle(Tr.exportingIncludeDeckConfigs, isOn: $withDeckConfigs)
            Toggle(Tr.exportingIncludeMedia, isOn: $withMedia)
            Toggle(Tr.exportingSupportOlderAnkiVersions, isOn: $legacy)
        case .collectionPackage:
            Toggle(Tr.exportingIncludeMedia, isOn: $withMedia)
            Toggle(Tr.exportingSupportOlderAnkiVersions, isOn: $legacy)
        case .notes:
            Toggle(Tr.exportingIncludeHtmlAndMediaReferences, isOn: $withHTML)
            Toggle(Tr.exportingIncludeTags, isOn: $withTags)
            Toggle(Tr.exportingIncludeDeck, isOn: $withDeck)
            Toggle(Tr.exportingIncludeNotetype, isOn: $withNotetype)
            Toggle(Tr.exportingIncludeGuid, isOn: $withGUID)
        case .cards:
            Toggle(Tr.exportingIncludeHtmlAndMediaReferences, isOn: $withHTML)
        }
    }

    /// Desktop's labels carry HTML bold and a trailing colon.
    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }

    private var flatDecks: [DeckNode] {
        func flatten(_ nodes: [DeckNode]) -> [DeckNode] {
            nodes.flatMap { [$0] + flatten($0.children ?? []) }
        }
        return flatten(model.decks)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.title = Tr.actionsExport
        if let type = UTType(filenameExtension: format.extensionName) { panel.allowedContentTypes = [type] }
        let base = selectedNoteIDs != nil ? Tr.exportingSelectedNotes
            : format == .collectionPackage ? Tr.exportingCollection
            : deckID.flatMap(model.deck)?.name ?? Tr.exportingCollection
        panel.nameFieldStringValue = base + "." + format.extensionName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            started = true
            model.export(format: format, to: url, deckID: selectedNoteIDs == nil ? deckID : nil,
                selectedNoteIDs: selectedNoteIDs, withScheduling: withScheduling,
                withDeckConfigs: withDeckConfigs, withMedia: withMedia, legacy: legacy,
                withHTML: withHTML, withTags: withTags, withDeck: withDeck,
                withNotetype: withNotetype, withGUID: withGUID)
        }
    }
}

/// Options for importing an .apkg, as desktop's import page offers them.
struct ImportOptionsSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var options = Anki_ImportExport_ImportAnkiPackageOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text(url.lastPathComponent).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            Form {
                Section(Tr.importingImportOptions) {
                    Toggle(Tr.importingMergeNotetypes, isOn: $options.mergeNotetypes)
                        .help(Tr.importingMergeNotetypesHelp)
                    Toggle(Tr.importingIncludeReviews, isOn: $options.withScheduling)
                        .help(Tr.importingIncludeReviewsHelp)
                    Toggle(Tr.importingWithDeckConfigs, isOn: $options.withDeckConfigs)
                        .help(Tr.importingWithDeckConfigsHelp)
                }
                Section(Tr.importingUpdates) {
                    Picker(Tr.importingUpdateNotes, selection: $options.updateNotes) { updateChoices }
                        .help(Tr.importingUpdateNotesHelp)
                    Picker(Tr.importingUpdateNotetypes, selection: $options.updateNotetypes) { updateChoices }
                        .help(Tr.importingUpdateNotetypesHelp)
                }
            }
            .formStyle(.grouped)
            HStack {
                if model.packageOperationInProgress {
                    ProgressView().controlSize(.small)
                    Text(Tr.actionsProcessing).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Tr.actionsCancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.packageOperationInProgress)
                Button(Tr.actionsImport) { model.importPackage(url, options: options) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.packageOperationInProgress)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: 480)
        .task {
            guard let backend = model.backend else { return }
            if let presets = try? await backend.perform({ try $0.getImportAnkiPackagePresets() }) { options = presets }
        }
    }

    @ViewBuilder private var updateChoices: some View {
        Text(Tr.importingUpdateIfNewer).tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.ifNewer)
        Text(Tr.importingUpdateAlways).tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.always)
        Text(Tr.importingUpdateNever).tag(Anki_ImportExport_ImportAnkiPackageUpdateCondition.never)
    }
}

/// Desktop's Import Log: how many notes were found and what became of them.
struct ImportLogSheet: View {
    @Environment(CollectionModel.self) private var model
    let result: ImportResult

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(Tr.importingImportLog).font(.title2.weight(.semibold))
            if result.found == 0 {
                Text(Tr.importingNoNotesInFile)
            } else {
                Text(Tr.importingNotesFoundInFile2(notes: result.found))
                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                    line(result.new) { Tr.importingNotesAdded(count: $0) }
                    line(result.updated) { Tr.importingNotesUpdated(count: $0) }
                    line(result.duplicate) { Tr.importingExistingNotesSkipped(count: $0) }
                    line(result.conflicting) {
                        result.mergedNotetypes ? Tr.importingConflictingNotesSkipped(count: $0)
                            : Tr.importingConflictingNotesSkipped2(count: $0)
                    }
                    line(result.failed) { Tr.importingNotesFailed(count: $0) }
                }
                .padding(.leading, Theme.Spacing.medium)
            }
            HStack { Spacer(); Button("OK") { model.importResult = nil }.keyboardShortcut(.defaultAction) }
        }
        .padding(Theme.Spacing.large)
        .frame(width: 420)
    }

    @ViewBuilder private func line(_ count: Int, _ text: (Int) -> String) -> some View {
        if count > 0 { Text(text(count)) }
    }
}
