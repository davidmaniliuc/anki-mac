import AnkiKit
import Foundation
import Security

/// Stores the complete backend auth value so redirected endpoints survive relaunch.
/// Each login belongs to one profile, or to one collection opened with
/// `-CollectionPath` (a test fixture, a copy), which so starts logged out and
/// can never sync, and perhaps overwrite, a profile's AnkiWeb account.
nonisolated enum SyncKeychain {
    private static let service = "net.ankiweb.sync"

    static func load(account: String) -> Anki_Sync_SyncAuth? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? Anki_Sync_SyncAuth(serializedBytes: data)
    }

    static func save(_ auth: Anki_Sync_SyncAuth, account: String) {
        guard let data = try? auth.serializedData() else { return }
        SecItemDelete(baseQuery(account) as CFDictionary)
        var query = baseQuery(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    /// Files a login under another account, as a profile's rename does.
    static func move(from old: String, to new: String) {
        guard let auth = load(account: old) else { return }
        save(auth, account: new)
        delete(account: old)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
