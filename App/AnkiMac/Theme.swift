import AnkiKit
import AppKit
import FieldEditor
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
        static let xxSmall: CGFloat = 2
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

    enum FilteredDeck {
        static let sheetWidth: CGFloat = 480
        static let sheetHeight: CGFloat = 560
        static let secondsWidth: CGFloat = 60
    }

    enum Browser {
        static let defaultSize = CGSize(width: 1100, height: 700)
        static let minWidth: CGFloat = 640
        static let minHeight: CGFloat = 360
        static let columnWidth: CGFloat = 160
        static let columnMinWidth: CGFloat = 40
        static let cellFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        static let cellPadding: CGFloat = 4
        static let sidebarIconSize: CGFloat = 16
        static let sidebarHeaderFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        /// Sheets for the Cards and Notes actions (set due date, change deck...).
        static let sheetWidth: CGFloat = 420
        static let deckListHeight: CGFloat = 260
        static let tagSuggestions = 8
        static let editorMinWidth: CGFloat = 260
        static let editorFraction: CGFloat = 0.4
        /// Edits are saved once typing pauses this long, as desktop's.
        static let editorSaveDelay = Duration.milliseconds(600)

        /// Whole-row tints for flagged, marked, suspended and buried cards, in
        /// desktop's colour scheme. Translucent, so the alternating row
        /// background shows through; stronger in dark mode, where a faint tint
        /// disappears.
        static func rowColor(_ color: Anki_Search_BrowserRow.Color) -> NSColor? {
            rowColors[color]
        }

        private static let rowColors: [Anki_Search_BrowserRow.Color: NSColor] = [
            .flagRed: tint(.systemRed),
            .flagOrange: tint(.systemOrange),
            .flagGreen: tint(.systemGreen),
            .flagBlue: tint(.systemBlue),
            .flagPink: tint(.systemPink),
            .flagTurquoise: tint(.systemTeal),
            .flagPurple: tint(.systemPurple),
            .marked: tint(.systemIndigo),
            .suspended: tint(.systemYellow),
            .buried: tint(.systemBrown),
        ]

        private static func tint(_ base: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return base.withAlphaComponent(dark ? 0.38 : 0.28)
            }
        }
    }

    enum DeckOptions {
        static let defaultSize = CGSize(width: 640, height: 760)
        static let minSize = CGSize(width: 480, height: 400)
        static let numberFieldWidth: CGFloat = 64
        static let stepsFieldWidth: CGFloat = 160
        static let customSchedulingHeight: CGFloat = 140
        static let helpWidth: CGFloat = 360
        static let helpMaxHeight: CGFloat = 480
        /// Desktop's alert colours for the notes under a setting.
        static let infoColor = Color.blue
        static let warningColor = Color.orange
        static let dangerColor = Color.red
        static let simulatorSize = CGSize(width: 620, height: 760)
        static let simulatorMinSize = CGSize(width: 460, height: 480)
        static let chartHeight: CGFloat = 260
        /// How often a running FSRS job's progress is read.
        static let progressInterval = Duration.milliseconds(100)
    }

    enum AddCards {
        static let defaultSize = CGSize(width: 560, height: 680)
        static let minSize = CGSize(width: 400, height: 300)
        static let checkDelay = Duration.milliseconds(300)
        static let addedMessageDuration = Duration.seconds(1.5)
        static let toastInset: CGFloat = 60
        static let tagSuggestions = 8
    }

    enum Editor {
        static let defaultFontSize: CGFloat = 20
        static let fieldInset = NSSize(width: 6, height: 6)
        static let minFieldHeight: CGFloat = 32
        static let minFieldWidth: CGFloat = 80
        static let sourceMinHeight: CGFloat = 80
        static let cornerRadius: CGFloat = 6
        static let labelFont = Font.callout
        static let sourceFont = Font.body.monospaced()
        static let fieldBackground = Color(nsColor: .textBackgroundColor)
        static let fieldBorder = Color(nsColor: .separatorColor)
        /// Desktop's red tint on a first field that duplicates another note.
        static let duplicateBackground = Color.red.opacity(0.18)

        /// How text, chips and images look inside a field.
        static func fieldStyle(font: NSFont) -> FieldStyle {
            FieldStyle(
                font: font,
                codeFont: .monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .regular),
                textColor: .textColor,
                unknownTagBackground: NSColor.systemYellow.withAlphaComponent(0.18),
                chipFont: .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
                chipFill: NSColor.secondaryLabelColor.withAlphaComponent(0.15),
                chipText: .secondaryLabelColor,
                imageMaxHeight: 160)
        }
    }

    /// Flag colours in the sidebar and menus, matching the row tints.
    static func flagColor(_ flag: CardFlag) -> Color {
        switch flag {
        case .none: .secondary
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .turquoise: .teal
        case .purple: .purple
        }
    }
}
