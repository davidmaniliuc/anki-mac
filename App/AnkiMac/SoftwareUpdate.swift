import Combine
import Foundation
import Sparkle
import SwiftUI

/// In-app updates, through Sparkle.
///
/// The updater starts only in a build that carries both `SUFeedURL` (fixed in
/// Info.plist) and `SUPublicEDKey`, which Info.plist takes from the
/// `SPARKLE_PUBLIC_ED_KEY` build setting. Only the release workflow sets that,
/// so a local build never offers to replace itself with the latest release,
/// and "Check for Updates…" is absent from its menu rather than broken.
///
/// Updates are trusted by their EdDSA signature: Sparkle accepts an update
/// whose code signature differs from the installed copy's (ad-hoc, or another
/// certificate) because that signature validated.
///
/// An `ObservableObject` because the state comes in through KVO on
/// `SPUUpdater`, which Sparkle documents as a Combine publisher.
final class SoftwareUpdate: ObservableObject {
    /// False while a check is already running (Sparkle's rule for the menu item).
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    init(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) {
        controller = Self.isConfigured(infoDictionary)
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        controller?.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Both keys present and non-empty: an unset build setting expands to an
    /// empty string, not to a missing key.
    nonisolated static func isConfigured(_ info: [String: Any]?) -> Bool {
        func value(_ key: String) -> String {
            ((info?[key] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        }
        return !value("SUFeedURL").isEmpty && !value("SUPublicEDKey").isEmpty
    }
}

/// The app menu's "Check for Updates…", present only in a build that can
/// update itself.
struct UpdateCommands: Commands {
    @ObservedObject var updates: SoftwareUpdate

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if updates.isAvailable {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
            }
        }
    }
}
