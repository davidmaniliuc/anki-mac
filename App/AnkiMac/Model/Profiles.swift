import Foundation

/// Where a collection's own settings and AnkiWeb login are filed: a profile,
/// or a collection opened with `-CollectionPath`, which keeps its own.
nonisolated struct SettingsScope: Hashable, Sendable {
    /// The Keychain account, and the prefix of the settings' defaults keys.
    let key: String

    static func profile(_ name: String) -> SettingsScope { SettingsScope(key: "profile:\(name)") }

    /// The login was filed under the collection's path before profiles.
    static func collection(_ path: String) -> SettingsScope { SettingsScope(key: path) }

    /// The settings desktop keeps per profile.
    static let keys = [
        "autoSync", "syncMedia", "syncUsername", "autoSyncMediaMinutes", "networkTimeout", "customSyncUrl",
        "allowedUrlSchemes",
    ]

    /// The open collection's, for what reads its settings without the model,
    /// such as a link on a card.
    @MainActor static var open: SettingsScope?

    func defaultsKey(_ name: String) -> String { "\(key)/\(name)" }

    func bool(_ name: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: defaultsKey(name)) as? Bool ?? fallback
    }

    func integer(_ name: String, default fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: defaultsKey(name)) as? Int ?? fallback
    }

    func string(_ name: String) -> String? {
        UserDefaults.standard.string(forKey: defaultsKey(name))
    }

    func strings(_ name: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey(name)) ?? []
    }

    func set(_ value: Any?, for name: String) {
        UserDefaults.standard.set(value, forKey: defaultsKey(name))
    }

    /// Moves the settings and login to another scope, or forgets them.
    func move(to new: SettingsScope?) {
        for name in Self.keys {
            if let new, let value = UserDefaults.standard.object(forKey: defaultsKey(name)) {
                UserDefaults.standard.set(value, forKey: new.defaultsKey(name))
            }
            UserDefaults.standard.removeObject(forKey: defaultsKey(name))
        }
        if let new {
            SyncKeychain.move(from: key, to: new.key)
        } else {
            SyncKeychain.delete(account: key)
        }
    }
}

/// Desktop's profiles (aqt/profiles.py): each is a folder in the app's data
/// folder holding its collection, media and backups, with its own AnkiWeb
/// login and sync settings.
nonisolated enum Profiles {
    static func base() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "AnkiMac")
    }

    static func folder(_ name: String) throws -> URL {
        try base().appending(path: name, directoryHint: .isDirectory)
    }

    /// The profiles, creating desktop's "User 1" when there are none.
    static func names() throws -> [String] {
        let base = try base()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let names = try FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .map(\.lastPathComponent)
        .filter { $0 != reserved }
        guard !names.isEmpty else {
            try create(Tr.profilesUser1)
            return [Tr.profilesUser1]
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Desktop keeps add-ons in a folder beside the profiles.
    private static let reserved = "addons21"

    /// The profile opened last, which the next launch opens.
    static var lastLoaded: String? {
        get { UserDefaults.standard.string(forKey: "lastLoadedProfile") }
        set { UserDefaults.standard.set(newValue, forKey: "lastLoadedProfile") }
    }

    /// Why a name can't be used, as desktop's checks say it; nil when it can.
    static func problem(with name: String, among names: [String]) -> String? {
        if names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) || name == reserved {
            return Tr.qtMiscNameExists
        }
        if let bad = name.first(where: { ":*?\"<>|/\\".contains($0) }) {
            return Tr.qtMiscTheFollowingCharacterCanNotBe(val: String(bad))
        }
        if name.hasPrefix(".") { return Tr.qtMiscTheFollowingCharacterCanNotBe(val: ".") }
        return nil
    }

    static func create(_ name: String) throws {
        try FileManager.default.createDirectory(at: folder(name), withIntermediateDirectories: true)
    }

    /// Renames the folder, through a temporary name when only the case
    /// changes, as desktop does, and carries the settings and login over.
    static func rename(_ old: String, to new: String) throws {
        let from = try folder(old), to = try folder(new)
        do {
            if old.caseInsensitiveCompare(new) == .orderedSame {
                let temporary = try folder(old + "-temp")
                try FileManager.default.moveItem(at: from, to: temporary)
                try FileManager.default.moveItem(at: temporary, to: to)
            } else {
                try FileManager.default.moveItem(at: from, to: to)
            }
        } catch {
            throw ProfileError(message: Tr.profilesAnkiCouldNotRenameYourProfile)
        }
        SettingsScope.profile(old).move(to: .profile(new))
        if lastLoaded == old { lastLoaded = new }
    }

    /// Moves the profile's folder to the Trash and forgets its login.
    static func remove(_ name: String) throws {
        try FileManager.default.trashItem(at: folder(name), resultingItemURL: nil)
        SettingsScope.profile(name).move(to: nil)
        if lastLoaded == name { lastLoaded = nil }
    }

    /// Before profiles, the app's one collection was "User 1" and its
    /// settings and login were the app's; they become that profile's.
    static func adoptAppSettings() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "profilesAdoptedAppSettings") else { return }
        defaults.set(true, forKey: "profilesAdoptedAppSettings")
        let user1 = SettingsScope.profile(Tr.profilesUser1)
        for name in SettingsScope.keys {
            if let value = defaults.object(forKey: name) { user1.set(value, for: name) }
            defaults.removeObject(forKey: name)
        }
        SyncKeychain.move(from: "default", to: user1.key)
    }
}

nonisolated struct ProfileError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
