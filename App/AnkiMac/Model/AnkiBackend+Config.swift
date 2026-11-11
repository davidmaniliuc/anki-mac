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

    /// A config object's string entries, such as saved searches. Entries of
    /// another type are skipped, not a reason to read nothing.
    nonisolated func configStrings(_ key: String) -> [String: String] {
        ((try? configObject(key)) ?? [:]).compactMapValues { $0 as? String }
    }

    /// Edits a config object's string entries and keeps its other entries as
    /// they are. Throws, without writing, when the stored value is not an object.
    nonisolated func editConfigStrings(_ key: String, _ edit: (inout [String: String]) -> Void) throws {
        let object = try configObject(key)
        var strings = object.compactMapValues { $0 as? String }
        edit(&strings)
        let merged = object.filter { !($0.value is String) }.merging(strings) { $1 }
        var request = Anki_Config_SetConfigJsonRequest()
        request.key = key
        request.valueJson = try JSONSerialization.data(withJSONObject: merged)
        try setConfigJsonNoUndo(request)
    }

    private nonisolated func configObject(_ key: String) throws -> [String: Any] {
        var request = Anki_Generic_String()
        request.val = key
        let json = try getConfigJson(request).json
        switch try JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed) {
        case let object as [String: Any]: return object
        case is NSNull: return [:]
        default: throw ConfigError.notAnObject(key)
        }
    }
}

private nonisolated enum ConfigError: Error, CustomStringConvertible {
    case notAnObject(String)

    var description: String {
        switch self {
        case .notAnObject(let key): "The collection's “\(key)” setting is not in the expected form, so it was left as it is."
        }
    }
}
