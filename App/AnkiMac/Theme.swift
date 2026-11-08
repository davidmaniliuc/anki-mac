import SwiftUI

/// Every visual decision in the app lives here: colours, spacing, type and
/// sizes. Views read from `Theme` instead of hard-coding values, so the app
/// can be restyled from this one file.
enum Theme {
    enum Colors {
        /// Anki's colour coding for the three queues, kept so long-time users
        /// recognise the counts at a glance. System colours adapt to dark mode.
        static let newCards = Color.blue
        static let learnCards = Color.red
        static let reviewCards = Color.green
        /// A count of zero is shown, but recedes.
        static let zeroCount = Color.secondary.opacity(0.5)
    }

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 32
    }

    enum Fonts {
        static let sidebarCount = Font.callout.monospacedDigit()
        static let overviewTitle = Font.largeTitle.weight(.semibold)
        static let overviewCount = Font.system(size: 34, weight: .medium).monospacedDigit()
        static let overviewCountLabel = Font.callout
        static let studyCounts = Font.body.monospacedDigit()
        static let intervalCaption = Font.caption.monospacedDigit()
    }

    enum Sidebar {
        static let minWidth: CGFloat = 200
        static let idealWidth: CGFloat = 260
    }

    enum Study {
        /// Answer buttons share one width so none looks more important by
        /// size; they shrink towards the minimum in narrow windows.
        static let answerButtonWidth: CGFloat = 96
        static let answerButtonMinWidth: CGFloat = 52
        static let barPadding: CGFloat = 12
        static let cardMinHeight: CGFloat = 200
    }

    enum Window {
        static let minWidth: CGFloat = 720
        static let minHeight: CGFloat = 480
    }
}
