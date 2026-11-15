import AnkiKit
import AppKit
import SwiftUI

/// Importing a .csv, .tsv or .txt file, with the options desktop's import page
/// offers, drawn as Deck Options' settings: the file's name over sections of
/// rows under hairlines, then Cancel and Import at the trailing edge.
struct CsvImportSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: CsvImportModel

    private var metadata: CsvMetadata { draft.metadata }
    private var columns: [CsvColumn] { metadata.columns }
    private var separatorTitle: String {
        metadata.forceDelimiter ? Tr.importingFieldSeparator : Tr.importingFieldSeparatorGuessed
    }

    var body: some View {
        SettingsSheet(
            title: draft.url.lastPathComponent, width: Theme.CsvImport.size.width,
            height: Theme.CsvImport.size.height
        ) {
            Group {
                fileSection
                optionsSection
                mappingSection
            }
            // A re-query replaces the mapping, so an edit made meanwhile would be lost.
            .disabled(draft.isRefreshing)
        } footer: {
            footer
        }
    }

    // MARK: Sections

    private var fileSection: some View {
        OptionSection(
            title: Tr.importingFile,
            help: [
                (separatorTitle, Tr.importingFieldSeparatorHelp),
                (Tr.importingAllowHtmlInFields, Tr.importingAllowHtmlInFieldsHelp),
            ]
        ) {
            OptionRow(title: separatorTitle, help: Tr.importingFieldSeparatorHelp, revertible: false) {
                OptionPicker(
                    selection: draft.binding(\.delimiter),
                    choices: [
                        (.tab, Tr.importingTab), (.pipe, Tr.importingPipe), (.semicolon, Tr.importingSemicolon),
                        (.colon, Tr.importingColon), (.comma, Tr.importingComma), (.space, Tr.studyingSpace),
                    ])
                .disabled(metadata.forceDelimiter)
            }
            OptionRow(title: Tr.importingAllowHtmlInFields, help: Tr.importingAllowHtmlInFieldsHelp, revertible: false) {
                SwitchControl(title: Tr.importingAllowHtmlInFields, isOn: draft.binding(\.isHtml))
                    .disabled(metadata.forceIsHtml)
            }
            CsvPreview(metadata: metadata, columns: columns)
        }
    }

    private var optionsSection: some View {
        OptionSection(
            title: Tr.importingImportOptions,
            help: [
                (Tr.notetypesNotetype, Tr.importingNotetypeHelp),
                (Tr.decksDeck, Tr.importingDeckHelp),
                (Tr.importingExistingNotes, Tr.importingExistingNotesHelp),
                (Tr.importingMatchScope, Tr.importingMatchScopeHelp),
                (Tr.importingTagAllNotes, Tr.importingTagAllNotesHelp),
                (Tr.importingTagUpdatedNotes, Tr.importingTagUpdatedNotesHelp),
            ]
        ) {
            notetypeRow
            deckRow
            if let name = draft.newDeckName, metadata.deckID == 0 {
                OptionWarning(text: Tr.importingNewDeckWillBeCreated(name: name), level: .info)
            }
            OptionRow(title: Tr.importingExistingNotes, help: Tr.importingExistingNotesHelp, revertible: false) {
                OptionPicker(
                    selection: draft.binding(\.dupeResolution),
                    choices: [
                        (.update, Tr.importingUpdate), (.preserve, Tr.importingPreserve),
                        (.duplicate, Tr.importingDuplicate),
                    ])
            }
            OptionRow(title: Tr.importingMatchScope, help: Tr.importingMatchScopeHelp, revertible: false) {
                OptionPicker(
                    selection: draft.binding(\.matchScope),
                    choices: [(.notetype, Tr.notetypesNotetype), (.notetypeAndDeck, Tr.importingNotetypeAndDeck)])
            }
            tagsRow(Tr.importingTagAllNotes, help: Tr.importingTagAllNotesHelp, tags: draft.binding(\.globalTags))
            tagsRow(
                Tr.importingTagUpdatedNotes, help: Tr.importingTagUpdatedNotesHelp, tags: draft.binding(\.updatedTags))
        }
    }

    private var mappingSection: some View {
        OptionSection(title: Tr.importingFieldMapping) {
            if case .globalNotetype? = metadata.notetype {
                ForEach(Array(draft.fieldNames.enumerated()), id: \.offset) { index, name in
                    // The first field must take some column, so it has no "nothing".
                    columnRow(name, selection: draft.fieldColumn(index), allowsNothing: index > 0)
                }
            }
            columnRow(Tr.editingTags, selection: draft.binding(\.tagsColumn), allowsNothing: true)
        }
    }

    // MARK: Rows

    /// The note type is one for the whole file, or a column of it, which desktop shows no choice for.
    @ViewBuilder private var notetypeRow: some View {
        if case .globalNotetype? = metadata.notetype {
            OptionRow(title: Tr.notetypesNotetype, help: Tr.importingNotetypeHelp, revertible: false) {
                OptionPicker(
                    selection: draft.binding(\.globalNotetype.id),
                    choices: draft.notetypes.map { ($0.id, $0.name) })
            }
        } else if let column = columns[safe: Int(metadata.notetypeColumn) - 1] {
            OptionRow(title: Tr.notetypesNotetype, revertible: false) { columnName(column.title) }
        }
    }

    @ViewBuilder private var deckRow: some View {
        if case .deckColumn? = metadata.deck {
            OptionRow(title: Tr.decksDeck, revertible: false) {
                columnName(columns[safe: Int(metadata.deckColumn) - 1]?.title ?? "")
            }
        } else {
            OptionRow(title: Tr.decksDeck, help: Tr.importingDeckHelp, revertible: false) { deckMenu }
        }
    }

    /// The deck tree as nested menus, as Add's, holding the decks a note can
    /// go to, led by the deck the file names when the collection lacks it.
    private var deckMenu: some View {
        let deck = draft.deck
        let name = deck.wrappedValue == 0
            ? draft.newDeckName ?? "" : draft.decks.first { $0.id == deck.wrappedValue }?.name ?? ""
        return Menu {
            if let newDeck = draft.newDeckName {
                Toggle(newDeck, isOn: Binding { deck.wrappedValue == 0 } set: { _ in deck.wrappedValue = 0 })
                Divider()
            }
            DeckMenuItems(
                decks: DeckNode.keeping(Set(draft.decks.map(\.id)), in: model.decks), current: deck.wrappedValue,
                pick: { deck.wrappedValue = $0 })
        } label: {
            QuietMenuLabel(value: name.replacingOccurrences(of: "::", with: " \u{203A} "), truncation: .head)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.trailing, -Theme.Layout.menuPadding)
        .accessibilityLabel(Tr.decksDeck)
        .accessibilityValue(name)
    }

    private func tagsRow(_ title: String, help: String, tags: Binding<[String]>) -> some View {
        OptionRow(title: title, help: help, revertible: false) {
            TagField(tags: tags, complete: draft.completeTags)
                .frame(width: Theme.CsvImport.tagFieldWidth)
        }
    }

    private func columnRow(_ title: String, selection: Binding<UInt32>, allowsNothing: Bool) -> some View {
        OptionRow(title: title, revertible: false) {
            ColumnPicker(selection: selection, columns: columns, allowsNothing: allowsNothing)
        }
    }

    /// A column that holds the choice for each note: named, not chosen.
    private func columnName(_ title: String) -> some View {
        Text(title)
            .font(Theme.DeckOptions.rowFont)
            .foregroundStyle(Theme.Palette.secondary)
            .lineLimit(1)
    }

    // MARK: Footer

    /// What's happening, or what went wrong, then the dialog's buttons.
    @ViewBuilder private var footer: some View {
        if draft.isRefreshing || model.packageOperationInProgress {
            ProgressView().controlSize(.small)
            Text(Tr.actionsProcessing)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
        } else if let error = draft.refreshError {
            OptionWarning(text: error, level: .danger).lineLimit(2)
        }
        Spacer(minLength: Theme.Spacing.small)
        DialogButtons(
            action: Tr.actionsImport, disabled: draft.isRefreshing || model.packageOperationInProgress,
            cancelDisabled: model.packageOperationInProgress, cancel: { dismiss() },
            submit: { model.importCsv(draft) })
    }
}

/// A field's column as a quiet menu that reads as a column, not as a card:
/// the index in rounded figures, as the preview heads it, then what the
/// column holds in Pencil, losing its end where a long value would crowd
/// the field's name.
private struct ColumnPicker: View {
    @Environment(\.optionTitle) private var title
    @Binding var selection: UInt32
    let columns: [CsvColumn]
    let allowsNothing: Bool

    var body: some View {
        let chosen = columns.first { UInt32($0.index) == selection }
        Menu {
            Picker(title, selection: $selection) {
                if allowsNothing {
                    Text(Tr.changeNotetypeNothing).tag(UInt32(0))
                }
                ForEach(columns) { column in
                    Text(column.title).tag(UInt32(column.index)).selectionDisabled(column.isReserved)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Theme.Spacing.xSmall) {
                if let chosen {
                    Text("\(chosen.index)")
                        .font(Theme.CsvImport.columnIndexFont)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize()
                    if !chosen.name.isEmpty {
                        Text(chosen.name)
                            .foregroundStyle(Theme.Palette.secondary)
                            .truncationMode(.tail)
                    }
                } else {
                    Text(Tr.changeNotetypeNothing)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.Fonts.menuChevron)
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .font(Theme.Fonts.chip)
            .lineLimit(1)
            .frame(height: Theme.Layout.controlHeight)
            .modifier(MenuHover(shape: RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: Theme.CsvImport.columnMenuMaxWidth, alignment: .trailing)
        .padding(.trailing, -Theme.Layout.menuPadding)
        .accessibilityLabel(title)
        .accessibilityValue(chosen?.title ?? Tr.changeNotetypeNothing)
    }
}

/// The first rows of the file as the backend split them, headed by column,
/// as dense as the Browser's table: no grid, one hairline under the titles.
private struct CsvPreview: View {
    let metadata: CsvMetadata
    let columns: [CsvColumn]
    private static let maxColumns = 1000

    var body: some View {
        let rows = metadata.preview.map { Array($0.vals.prefix(Self.maxColumns)) }
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: Theme.CsvImport.previewColumnGap, verticalSpacing: 0) {
                    GridRow {
                        ForEach(columns.prefix(Self.maxColumns)) { column in
                            cell(column.shortTitle, font: Theme.Fonts.eyebrow)
                                .foregroundStyle(Theme.Palette.secondary)
                                .frame(height: Theme.CsvImport.previewHeaderHeight)
                        }
                    }
                    // Room for the hairline, drawn across the whole section below.
                    Color.clear.frame(height: 1)
                    ForEach(rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(rows[row].indices, id: \.self) { cell(rows[row][$0]) }
                        }
                        .frame(height: Theme.CsvImport.previewRowHeight)
                    }
                }
            }
            .scrollIndicators(.automatic)
            // Under the titles, as wide as the section's hairlines however narrow the file.
            .overlay(alignment: .top) {
                Theme.Palette.hairline.frame(height: 1).offset(y: Theme.CsvImport.previewHeaderHeight)
            }
            if columns.count > Self.maxColumns {
                Text(Tr.importingPreviewTruncated(count: Self.maxColumns))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
            }
        }
    }

    private func cell(_ text: String, font: Font = Theme.CsvImport.previewFont) -> some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Theme.CsvImport.previewColumnMaxWidth, alignment: .leading)
    }
}
