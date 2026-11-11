import Foundation

/// A card's user flag, stored in the low three bits of `Card.flags`. The raw
/// value is what the backend and the reviewer page's `--flag-N` colours use.
nonisolated enum CardFlag: Int, CaseIterable, Sendable {
    case none, red, orange, green, blue, pink, turquoise, purple

    init(cardFlags: UInt32) {
        self = CardFlag(rawValue: Int(cardFlags & 0b111)) ?? .none
    }

    var title: String {
        switch self {
        case .none: "None"
        case .red: Tr.actionsFlagRed
        case .orange: Tr.actionsFlagOrange
        case .green: Tr.actionsFlagGreen
        case .blue: Tr.actionsFlagBlue
        case .pink: Tr.actionsFlagPink
        case .turquoise: Tr.actionsFlagTurquoise
        case .purple: Tr.actionsFlagPurple
        }
    }

    /// The flags a user can set, in desktop's Ctrl+1 to Ctrl+7 order.
    static let assignable = allCases.filter { $0 != .none }
}
