import AnkiKit
import Foundation

/// An action that didn't happen, for an alert: what it was, as the title,
/// and why, with what to do next when that's known.
nonisolated struct ActionFailure: Equatable, Sendable {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    /// The error's reason, then `recovery` when what's left on screen needs saying.
    init(_ title: String, error: Error, recovery: String? = nil) {
        self.init(title, detail: [Self.reason(error), recovery].compactMap { $0 }.joined(separator: "\n\n"))
    }

    /// The backend's own message, or the system's, never the raw Swift error.
    static func reason(_ error: Error) -> String {
        (error as? AnkiError)?.message ?? error.localizedDescription
    }
}
