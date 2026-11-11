import AnkiKit
import AppKit
import SwiftUI

/// Importing a .csv, .tsv or .txt file, with the options desktop's import page offers.
struct CsvImportSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: CsvImportModel

    private var metadata: CsvMetadata { draft.metadata }
    private var columns: [CsvColumn] { metadata.columns }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text(draft.url.lastPathComponent).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
            Form {
                Section(Tr.importingFile) {
                    Picker(
                        metadata.forceDelimiter ? Tr.importingFieldSeparator : Tr.importingFieldSeparatorGuessed,
                        selection: draft.binding(\.delimiter)
                    ) {
                        Text(Tr.importingTab).tag(CsvMetadata.Delimiter.tab)
                        Text(Tr.importingPipe).tag(CsvMetadata.Delimiter.pipe)
                        Text(Tr.importingSemicolon).tag(CsvMetadata.Delimiter.semicolon)
                        Text(Tr.importingColon).tag(CsvMetadata.Delimiter.colon)
                        Text(Tr.importingComma).tag(CsvMetadata.Delimiter.comma)
                        Text(Tr.studyingSpace).tag(CsvMetadata.Delimiter.space)
                    }
                    .disabled(metadata.forceDelimiter)
                    .help(Tr.importingFieldSeparatorHelp)
                    Toggle(Tr.importingAllowHtmlInFields, isOn: draft.binding(\.isHtml))
                        .disabled(metadata.forceIsHtml)
                        .help(Tr.importingAllowHtmlInFieldsHelp)
                    CsvPreview(metadata: metadata, columns: columns)
                }
                Section(Tr.importingImportOptions) {
                    notetypeRow
                    deckRow
                    Picker(Tr.importingExistingNotes, selection: draft.binding(\.dupeResolution)) {
                        Text(Tr.importingUpdate).tag(CsvMetadata.DupeResolution.update)
                        Text(Tr.importingPreserve).tag(CsvMetadata.DupeResolution.preserve)
                        Text(Tr.importingDuplicate).tag(CsvMetadata.DupeResolution.duplicate)
                    }
                    .help(Tr.importingExistingNotesHelp)
                    Picker(Tr.importingMatchScope, selection: draft.binding(\.matchScope)) {
                        Text(Tr.notetypesNotetype).tag(CsvMetadata.MatchScope.notetype)
                        Text(Tr.importingNotetypeAndDeck).tag(CsvMetadata.MatchScope.notetypeAndDeck)
                    }
                    .help(Tr.importingMatchScopeHelp)
                    LabeledContent(Tr.importingTagAllNotes) {
                        TagField(tags: draft.binding(\.globalTags), complete: draft.completeTags)
                    }
                    .help(Tr.importingTagAllNotesHelp)
                    LabeledContent(Tr.importingTagUpdatedNotes) {
                        TagField(tags: draft.binding(\.updatedTags), complete: draft.completeTags)
                    }
                    .help(Tr.importingTagUpdatedNotesHelp)
                }
                Section(Tr.importingFieldMapping) {
                    if case .globalNotetype? = metadata.notetype {
                        ForEach(Array(draft.fieldNames.enumerated()), id: \.offset) { index, name in
                            // The first field must take some column, so it has no "nothing".
                            columnPicker(name, selection: draft.fieldColumn(index), allowsNothing: index > 0)
                        }
                    }
                    columnPicker(Tr.editingTags, selection: draft.binding(\.tagsColumn), allowsNothing: true)
                }
            }
            .formStyle(.grouped)
            HStack {
                if draft.isRefreshing || model.packageOperationInProgress {
                    ProgressView().controlSize(.small)
                    Text(Tr.actionsProcessing).foregroundStyle(.secondary)
                } else if let error = draft.refreshError {
                    Text(error).foregroundStyle(.red).lineLimit(2)
                }
                Spacer()
                Button(Tr.actionsCancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.packageOperationInProgress)
                Button(Tr.actionsImport) { model.importCsv(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.isRefreshing || model.packageOperationInProgress)
            }
        }
        .padding(Theme.Spacing.large)
        .frame(width: 640, height: 660)
    }

    /// The note type is one for the whole file, or a column of it, which desktop shows no choice for.
    @ViewBuilder private var notetypeRow: some View {
        if case .globalNotetype? = metadata.notetype {
            Picker(Tr.notetypesNotetype, selection: draft.binding(\.globalNotetype.id)) {
                ForEach(draft.notetypes, id: \.id) { Text($0.name).tag($0.id) }
            }
            .help(Tr.importingNotetypeHelp)
        } else if let column = columns[safe: Int(metadata.notetypeColumn) - 1] {
            LabeledContent(Tr.notetypesNotetype, value: column.title)
        }
    }

    @ViewBuilder private var deckRow: some View {
        if case .deckColumn? = metadata.deck {
            LabeledContent(Tr.decksDeck, value: columns[safe: Int(metadata.deckColumn) - 1]?.title ?? "")
        } else {
            Picker(Tr.decksDeck, selection: draft.deck) {
                ForEach(draft.decks, id: \.id) { Text($0.name).tag($0.id) }
                if let name = draft.newDeckName { Text(name).tag(Int64(0)) }
            }
            .help(Tr.importingDeckHelp)
            if let name = draft.newDeckName, metadata.deckID == 0 {
                Text(Tr.importingNewDeckWillBeCreated(name: name)).foregroundStyle(.secondary)
            }
        }
    }

    private func columnPicker(_ label: String, selection: Binding<UInt32>, allowsNothing: Bool) -> some View {
        Picker(label, selection: selection) {
            if allowsNothing { Text(Tr.changeNotetypeNothing).tag(UInt32(0)) }
            ForEach(columns) { Text($0.title).tag(UInt32($0.index)).disabled($0.isReserved) }
        }
    }
}

/// The first rows of the file as the backend split them, headed by column.
private struct CsvPreview: View {
    let metadata: CsvMetadata
    let columns: [CsvColumn]
    private static let maxColumns = 1000

    var body: some View {
        let rows = metadata.preview.map { Array($0.vals.prefix(Self.maxColumns)) }
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(columns.prefix(Self.maxColumns)) { cell($0.shortTitle).background(.quaternary) }
                    }
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row].indices, id: \.self) { cell(rows[row][$0]) }
                        }
                    }
                }
            }
            .frame(height: 140)
            if columns.count > Self.maxColumns {
                Text(Tr.importingPreviewTruncated(count: Self.maxColumns)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func cell(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.xSmall)
            .frame(maxWidth: 220, alignment: .leading)
            .border(Color(nsColor: .separatorColor), width: 0.5)
    }
}
