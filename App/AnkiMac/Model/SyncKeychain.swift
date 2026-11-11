import AnkiKit
import Foundation
import Security

/// Stores the complete backend auth value so redirected endpoints survive relaunch.
/// The login belongs to one collection: one opened with `-CollectionPath`
/// (a test fixture, a copy) starts logged out, so it can never sync, and
/// perhaps overwrite, the app profile's AnkiWeb account.
enum SyncKeychain {
    private static let service = "net.ankiweb.sync"
    private static let account = UserDefaults.standard.string(forKey: "CollectionPath") ?? "default"

    static func load() -> Anki_Sync_SyncAuth? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? Anki_Sync_SyncAuth(serializedBytes: data)
    }

    static func save(_ auth: Anki_Sync_SyncAuth) {
        guard let data = try? auth.serializedData() else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
