import AnkiKit
import AppKit
import FieldEditor
import SwiftUI

/// Every visual decision in the app lives here: colours, spacing, type and
/// sizes. Views read from `Theme` instead of hard-coding values, so the app
/// can be restyled from this one file.
enum Theme {
    /// The main window's own palette: warm neutrals in place of the system
    /// greys, one electric accent, and muted queue colours. Each colour has
    /// a light and a dark value and follows the system appearance.
    enum Palette {
        static let canvas = dynamic(0xFAF9F6, 0x1D1C1A)
        static let sidebar = dynamic(0xF1EFEA, 0x161513)
        static let surface = dynamic(cardSurface.light, cardSurface.dark)
        static let raised = dynamic(0xF6F4F0, 0x2D2C29)
        static let hover = dynamic(0x000000, 0xFFFFFF, alpha: (0.04, 0.05))
        static let selection = dynamic(0x000000, 0xFFFFFF, alpha: (0.07, 0.09))
        static let hairline = dynamic(0x000000, 0xFFFFFF, alpha: (0.08, 0.07))

        static let text = dynamic(0x1D1C1A, 0xEEECE8)
        static let secondary = dynamic(0x6B675F, 0xA29E97)
        static let tertiary = dynamic(0x9E9A92, 0x6E6A64)

        static let accent = dynamic(0x2F6BFF, 0x4C8BFF)
        static let blue = dynamic(0x1A5CFF, 0x6AA2FF)
        static let coral = dynamic(0xCA342A, 0xF2786D)
        static let green = dynamic(0x247C47, 0x6CC78E)
        static let amber = dynamic(0x936113, 0xE9AE52)
        static let violet = dynamic(0x7C5CE6, 0xA78BFA)
        static let teal = dynamic(0x1E9AAE, 0x5CC8D8)
        /// Anki's own star blue, for Today.
        static let star = dynamic(0x2E9BEA, 0x55B8F7)

        /// Behind the card while studying. The card's web page paints the
        /// same values (ReviewerWebController), so the two meet seamlessly.
        static let cardSurface = (light: UInt32(0xFFFFFF), dark: UInt32(0x252421))

        static func css(_ hex: UInt32) -> String { String(format: "#%06X", hex) }

        private static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let hex = isDark ? dark : light
                let alpha = isDark ? alpha.1 : alpha.0
                return NSColor(
                    srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
            })
        }
    }

    enum Colors {
        /// Anki's colour coding for the three queues, kept so long-time users
        /// recognise the counts at a glance, in the palette's softer shades.
        static let newCards = Palette.blue
        static let learnCards = Palette.coral
        static let reviewCards = Palette.green
        /// A count of zero is shown, but recedes.
        static let zeroCount = Palette.tertiary
    }

    /// The main window's frame: the strip under the traffic lights, the
    /// sidebar, and the width below which everything tightens up.
    enum Layout {
        static let sidebarWidth: CGFloat = 248
        /// Below this window width the sidebar floats over the content
        /// instead of pushing it aside.
        static let compactWidth: CGFloat = 720
        static let radius: CGFloat = 12
        static let rowRadius: CGFloat = 7
        static let rowHeight: CGFloat = 30
        /// Each level of a deck tree steps in this far.
        static let indent: CGFloat = 14
        static let pageWidth: CGFloat = 680
        static let pageMargin: CGFloat = 56
        static let compactPageMargin: CGFloat = 18
        /// A list row's content keeps to the page's edge; its hover wash
        /// reaches this far past it on both sides, as in Things.
        static let washOutset: CGFloat = 12
        /// How far two fingers travel sideways before the sidebar moves.
        static let swipeDistance: CGFloat = 60
    }

    enum Spacing {
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
        static let xLarge: CGFloat = 32
    }

    /// SF Pro for the interface, with rounded figures for numbers.
    enum Fonts {
        static let title = Font.system(size: 30, weight: .bold)
        /// Sized for the title bar, where it sits beside the session's counts.
        static let studyTitle = Font.system(size: 13, weight: .semibold)
        static let compactTitle = Font.system(size: 24, weight: .bold)
        static let eyebrow = Font.system(size: 11, weight: .semibold)
        static let eyebrowTracking: CGFloat = 0.8
        /// Sidebar rows: regular, so only the selected row (semibold) steps
        /// forward.
        static let row = Font.system(size: 13.5)
        static let listRow = Font.system(size: 14.5, weight: .medium)
        static let body = Font.system(size: 14)
        static let lead = Font.system(size: 15)
        static let caption = Font.system(size: 12)
        static let panelTitle = Font.system(size: 17, weight: .semibold)
        static let button = Font.system(size: 14, weight: .semibold)
        static let chip = Font.system(size: 12.5, weight: .medium)
        static let keyCap = Font.system(size: 10.5, weight: .semibold, design: .rounded)
        static let sidebarCount = Font.system(size: 12, weight: .medium, design: .rounded).monospacedDigit()
        /// The page's one big count: how many are due.
        static let bigNumber = Font.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit()
        static let queueCount = Font.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit()
        static let studyCounts = Font.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit()
        static let intervalCaption = Font.system(size: 12, weight: .medium, design: .rounded).monospacedDigit()
    }

    /// The card browser's sidebar; the main window's is in Layout.
    enum Sidebar {
        static let minWidth: CGFloat = 200
    }

    enum Study {
        /// Answer buttons share the width evenly up to this, so none looks
        /// more important by size; in a small window they shrink together.
        static let answerButtonMaxWidth: CGFloat = 140
        /// Show Answer is one line, so it is smaller than the grades and
        /// sits in the middle of their row.
        static let showAnswerWidth: CGFloat = 200
        static let showAnswerHeight: CGFloat = 38
        static let answerButtonHeight: CGFloat = 58
        static let compactAnswerButtonHeight: CGFloat = 48
        static let cardMinHeight: CGFloat = 120
        static let cardMaxWidth: CGFloat = 860
        /// The study page's one side edge: the card, the answer bar and the
        /// deck name in the title bar all keep to it.
        static let margin: CGFloat = 40
        static let compactMargin: CGFloat = 12
        /// Keeps the title bar's deck name and counts clear of the actions
        /// at its right.
        static let titleActionsInset: CGFloat = 110
        /// Past the window controls and the sidebar button.
        static let titleControlsInset: CGFloat = 132
        static let cardRadius: CGFloat = 18
        /// How long the message after a card action stays over the card.
        static let feedbackDuration: Duration = .seconds(2.5)
        /// Keeps the message above the answer bar.
        static let feedbackBottomInset: CGFloat = 90
        static let editorWidth: CGFloat = 560
        static let editorHeight: CGFloat = 420
    }

    enum Window {
        /// Small enough to study in a corner of the screen.
        static let minWidth: CGFloat = 360
        static let minHeight: CGFloat = 340
    }

    enum Profiles {
        static let width: CGFloat = 420
        static let listHeight: CGFloat = 220
    }

    enum Overview {
        static let descriptionWidth: CGFloat = 520
        static let descriptionMaxHeight: CGFloat = 220
        static let descriptionSheetSize = CGSize(width: 480, height: 360)
    }

    enum StudyDeck {
        static let sheetHeight: CGFloat = 420
    }

    enum CustomStudy {
        static let sheetWidth: CGFloat = 480
        static let sheetHeight: CGFloat = 520
        static let valueWidth: CGFloat = 64
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
        static let previewSize = CGSize(width: 480, height: 520)
        static let previewMinSize = CGSize(width: 300, height: 240)
        static let cellFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        static let cellPadding: CGFloat = 4
        static let sidebarIconSize: CGFloat = 16
        static let sidebarHeaderFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        /// Sheets for the Cards and Notes actions (set due date, change deck...).
        static let sheetWidth: CGFloat = 420
        static let deckListHeight: CGFloat = 260
        static let changeNotetypeSheetWidth: CGFloat = 480
        static let changeNotetypeFormHeight: CGFloat = 380
        static let findDuplicatesSize = CGSize(width: 531, height: 345)
        static let findDuplicatesMinSize = CGSize(width: 420, height: 260)
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

    enum Statistics {
        static let defaultSize = CGSize(width: 1000, height: 800)
        static let minSize = CGSize(width: 560, height: 400)
        /// Graphs sit side by side once each can be this wide, as desktop's
        /// one to three columns.
        static let graphMinWidth: CGFloat = 520
        static let chartHeight: CGFloat = 220
        static let pdfWidth: CGFloat = 760
        static let printedCardRadius: CGFloat = 8
        static let searchWidth: CGFloat = 220
        /// Desktop asks d3 for about 7 ticks along x and 5 up y.
        static let xTickCount: Double = 7
        static let yTickCount: Double = 5
        /// The gap between bars, as a share of each side of a bar.
        static let barInset = 0.06
        /// d3's inner band padding for the hour and button bars.
        static let bandPadding = 0.1
        static let axisFont = Font.caption2.monospacedDigit()
        static let gridLine = Color.secondary.opacity(0.25)
        static let hoverColumn = Color.primary.opacity(0.06)
        /// The running total behind the bars, as desktop's faint overlay.
        static let areaFill = Color.primary.opacity(0.07)
        static let tooltipFont = Font.callout.monospacedDigit()
        static let tooltipRadius: CGFloat = 6
        static let tooltipOffset: CGFloat = 14
        /// Lines a table label up with the labels that have a colour swatch.
        static let swatchIndent: CGFloat = 16
        static let pieSize: CGFloat = 180
        static let calendarGap: CGFloat = 2
        static let calendarLabelWidth: CGFloat = 14
        /// Desktop's colours for the retention table.
        static let youngRetention = Color(hex: 0x64c476)
        static let matureRetention = Color(hex: 0x31a354)
        static let pass = Color(hex: 0x3bc464)
        static let fail = Color(hex: 0xc43b3b)
        static let cardInfoSize = CGSize(width: 640, height: 760)
        static let cardInfoMinSize = CGSize(width: 560, height: 300)
        /// Desktop's colours for a review log's type and a failed rating: the
        /// queue colours, so a Learn row reads as new, Review as review.
        static let revlogLearn = Colors.newCards
        static let revlogReview = Colors.reviewCards
        static let revlogRelearn = Colors.learnCards
        /// The forgetting curve's gradient: below, at and above desired retention.
        static let curveLow = Color(red: 1, green: 0.388, blue: 0.278)
        static let curveTarget = Color(red: 0.275, green: 0.510, blue: 0.706)
        static let curveHigh = Color(red: 0, green: 0.5, blue: 0)
        static let curveHeight: CGFloat = 220
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

    enum Notetypes {
        static let managerSize = CGSize(width: 640, height: 500)
        static let managerMinSize = CGSize(width: 640, height: 500)
        static let nameSheetWidth: CGFloat = 340
        static let optionsSheetSize = CGSize(width: 560, height: 440)
        static let fieldsSheetSize = CGSize(width: 600, height: 460)
        static let fieldListWidth: CGFloat = 180
        static let cardsDefaultSize = CGSize(width: 1040, height: 680)
        static let cardsMinSize = CGSize(width: 760, height: 480)
        static let editorMinHeight: CGFloat = 120
        static let editorFont = Font.system(.body, design: .monospaced)
        static let previewDelay = Duration.milliseconds(200)
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
        static let mathEditorWidth: CGFloat = 320
        static let mathEditorMinHeight: CGFloat = 60
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
                imageMaxHeight: 160,
                mathImage: { math in
                    MainActor.assumeIsolated { MathRenderer.shared.image(math, fontSize: font.pointSize) }
                })
        }
    }

    /// The mask editor, in desktop's colours (ts/routes/image-occlusion/tools/lib.ts).
    enum ImageOcclusion {
        static let border = NSColor(srgbRed: 0x21 / 255, green: 0x21 / 255, blue: 0x21 / 255, alpha: 1)
        static let textBackground = NSColor.white
        static let textFont = "Arial"
        /// A new label's size, in points on the image fitted to the view, as
        /// desktop sizes it on its canvas.
        static let textFontSize: CGFloat = 40
        static let textPadding: CGFloat = 5
        static let selection = NSColor.controlAccentColor
        static let handleSize: CGFloat = 8
        static let translucentAlpha: CGFloat = 0.4
        /// Smaller masks are dropped, as desktop does.
        static let minShapeSize: CGFloat = 5
        /// How close a click must be to a polygon's first point to close it.
        static let closeDistance: CGFloat = 8
        static let zoomStep: CGFloat = 1.25
        static let minZoom: CGFloat = 0.05
        static let maxZoom: CGFloat = 8
        static let canvasBackground = NSColor.underPageBackgroundColor
        static let pickerSpacing: CGFloat = 12
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
