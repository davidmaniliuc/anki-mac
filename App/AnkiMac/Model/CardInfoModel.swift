import AnkiKit
import Foundation
import Observation

/// The card a Card Info window shows: asks the backend for its stats whenever
/// the card changes, and keeps the last answer until the next one arrives so
/// the window doesn't flash empty while following the browser's current row.
@Observable
final class CardInfoModel {
    private(set) var stats: Anki_Stats_CardStatsResponse?
    private let backend: AnkiBackend
    private var loading: Task<Void, Never>?

    init(backend: AnkiBackend) {
        self.backend = backend
    }

    /// nil, or a card that no longer exists, shows the placeholder.
    func show(_ cardID: Int64?) {
        loading?.cancel()
        guard let cardID, cardID != 0 else {
            stats = nil
            return
        }
        loading = Task { [backend] in
            let loaded = try? await backend.perform { backend in
                var id = Anki_Cards_CardId()
                id.cid = cardID
                return try backend.cardStats(id)
            }
            guard !Task.isCancelled else { return }
            stats = loaded
        }
    }
}
