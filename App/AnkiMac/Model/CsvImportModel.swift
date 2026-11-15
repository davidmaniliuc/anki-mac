import AnkiKit
import Foundation
import Observation
import SwiftUI

typealias CsvMetadata = Anki_ImportExport_CsvMetadata

/// A file column as the mapping pickers list it. Indices are one-based, as the backend counts them.
struct CsvColumn: Identifiable {
    let index: Int
    /// What the column holds: its header, its first value, or its reserved role.
    let name: String
    let title: String
    let shortTitle: String
    /// Holds the note type, deck or GUID, so no field can take it.
    let isReserved: Bool
    var id: Int { index }
}

extension CsvMetadata {
    var columns: [CsvColumn] {
        columnLabels.enumerated().map { offset, label in
            let index = offset + 1
            let column = UInt32(index)
            let reserved: String? =
                column == notetypeColumn ? Tr.notetypesNotetype
                : column == deckColumn ? Tr.decksDeck
                : column == guidColumn ? "GUID" : nil
            let sample = preview.first?.vals[safe: offset] ?? ""
            let name = reserved ?? (label.isEmpty ? sample : label)
            let title = name.isEmpty ? "\(index)" : "\(index): \(name)"
            return CsvColumn(
                index: index, name: name, title: title, shortTitle: reserved == nil && label.isEmpty ? "\(index)" : title,
                isReserved: reserved != nil)
        }
    }

    func fieldColumn(_ field: Int) -> UInt32 {
        globalNotetype.fieldColumns[safe: field] ?? 0
    }

    mutating func setFieldColumn(_ field: Int, to column: UInt32) {
        var mapped = globalNotetype
        while mapped.fieldColumns.count <= field { mapped.fieldColumns.append(0) }
        mapped.fieldColumns[field] = column
        globalNotetype = mapped
    }
}

/// The text import dialog. `metadata` is the whole state, as the backend describes the file
/// and the choices made so far; the import request is built from it.
@Observable final class CsvImportModel: Identifiable {
    let url: URL
    let notetypes: [Anki_Notetypes_NotetypeNameId]
    let decks: [Anki_Decks_DeckNameId]
    /// The deck the file names but the collection lacks, which importing creates.
    let newDeckName: String?
    private(set) var metadata: CsvMetadata
    private(set) var fieldNames: [String]
    private(set) var isRefreshing = false
    private(set) var refreshError: String?
    private let backend: AnkiBackend
    private var generation = 0

    private init(
        url: URL, backend: AnkiBackend, metadata: CsvMetadata, fieldNames: [String],
        notetypes: [Anki_Notetypes_NotetypeNameId], decks: [Anki_Decks_DeckNameId]
    ) {
        self.url = url
        self.backend = backend
        self.metadata = metadata
        self.fieldNames = fieldNames
        self.notetypes = notetypes
        self.decks = decks
        if case .deckName(let name)? = metadata.deck { newDeckName = name } else { newDeckName = nil }
    }

    static func load(url: URL, backend: AnkiBackend) async throws -> CsvImportModel {
        var request = Anki_ImportExport_CsvMetadataRequest()
        request.path = url.path
        let (metadata, fieldNames) = try await fetch(backend, request)
        var decksRequest = Anki_Decks_GetDeckNamesRequest()
        decksRequest.skipEmptyDefault = false
        decksRequest.includeFiltered = false
        let decksQuery = decksRequest
        let (notetypes, decks) = try await backend.perform {
            (try $0.getNotetypeNames().entries, try $0.getDeckNames(decksQuery).entries)
        }
        return CsvImportModel(
            url: url, backend: backend, metadata: metadata, fieldNames: fieldNames,
            notetypes: notetypes, decks: decks)
    }

    nonisolated private static func fetch(
        _ backend: AnkiBackend, _ request: Anki_ImportExport_CsvMetadataRequest
    ) async throws -> (CsvMetadata, [String]) {
        try await backend.perform { backend in
            let metadata = try backend.getCsvMetadata(request)
            guard case .globalNotetype(let notetype)? = metadata.notetype else { return (metadata, []) }
            var id = Anki_Notetypes_NotetypeId()
            id.ntid = notetype.id
            return (metadata, try backend.getFieldNames(id).vals)
        }
    }

    var importRequest: Anki_ImportExport_ImportCsvRequest {
        var request = Anki_ImportExport_ImportCsvRequest()
        request.path = url.path
        request.metadata = metadata
        request.metadata.preview = []
        return request
    }

    func binding<T>(_ keyPath: WritableKeyPath<CsvMetadata, T>) -> Binding<T> {
        Binding { self.metadata[keyPath: keyPath] } set: { value in self.edit { $0[keyPath: keyPath] = value } }
    }

    func fieldColumn(_ field: Int) -> Binding<UInt32> {
        Binding { self.metadata.fieldColumn(field) } set: { column in
            self.edit { $0.setFieldColumn(field, to: column) }
        }
    }

    /// 0 stands for the file's new deck, as in desktop's deck picker.
    var deck: Binding<Int64> {
        Binding { self.metadata.deckID } set: { id in
            self.edit { if id != 0 { $0.deckID = id } else { $0.deckName = self.newDeckName ?? "" } }
        }
    }

    /// Changing the delimiter, HTML setting or note type changes how the file reads, so the backend
    /// answers again, as it does for desktop's page. Tags and duplicate handling carry over.
    func edit(_ change: (inout CsvMetadata) -> Void) {
        let before = metadata
        change(&metadata)
        guard metadata.delimiter != before.delimiter || metadata.isHtml != before.isHtml
            || metadata.globalNotetype.id != before.globalNotetype.id else { return }
        refetch(edited: metadata, before: before)
    }

    func completeTags(_ prefix: String) -> [String] {
        var request = Anki_Tags_CompleteTagRequest()
        request.input = prefix
        request.matchLimit = UInt32(Theme.Browser.tagSuggestions)
        return (try? backend.completeTag(request).tags) ?? []
    }

    private func refetch(edited: CsvMetadata, before: CsvMetadata) {
        generation += 1
        let mine = generation
        isRefreshing = true
        refreshError = nil
        var request = Anki_ImportExport_CsvMetadataRequest()
        request.path = url.path
        request.delimiter = edited.delimiter
        request.isHtml = edited.isHtml
        if case .globalNotetype(let notetype)? = edited.notetype { request.notetypeID = notetype.id }
        if case .deckID(let id)? = edited.deck { request.deckID = id }
        let query = request
        let backend = backend
        Task {
            do {
                var (fresh, names) = try await Self.fetch(backend, query)
                guard mine == generation else { return }
                fresh.globalTags = edited.globalTags
                fresh.updatedTags = edited.updatedTags
                fresh.dupeResolution = edited.dupeResolution
                fresh.matchScope = edited.matchScope
                metadata = fresh
                fieldNames = names
            } catch {
                guard mine == generation else { return }
                metadata = before
                refreshError = ActionFailure.reason(error)
            }
            isRefreshing = false
        }
    }
}
