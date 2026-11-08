import AnkiKit
import Foundation

/// The collection config's JSON values (column lists, saved searches...),
/// which desktop reads and writes as plain JSON under string keys.
extension AnkiBackend {
    nonisolated func configJSON<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        var request = Anki_Generic_String()
        request.val = key
        guard let json = try? getConfigJson(request).json else { return nil }
        return try? JSONDecoder().decode(T.self, from: json)
    }

    /// Not undoable, as desktop's `set_config` for browser settings.
    nonisolated func setConfigJSON(_ key: String, _ value: some Encodable) throws {
        var request = Anki_Config_SetConfigJsonRequest()
        request.key = key
        request.valueJson = try JSONEncoder().encode(value)
        try setConfigJsonNoUndo(request)
    }
}
