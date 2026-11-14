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
        static let canvas = dynamic(canvasHex.light, canvasHex.dark)
        static let sidebar = dynamic(0xF1EFEA, 0x161513)
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

        /// The card's web page paints the canvas too (ReviewerWebController),
        /// so the card sits straight on the desk with no box around it.
        static let canvasHex = (light: UInt32(0xFAF9F6), dark: UInt32(0x1D1C1A))

        static func css(_ hex: UInt32) -> String { String(format: "#%06X", hex) }

        static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: (CGFloat, CGFloat) = (1, 1)) -> Color {
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
        /// Below this window width a sidebar that can't widen the window
        /// floats over the content instead of docking.
        static let compactWidth: CGFloat = 720
        /// Below this page width (the window's, less a docked sidebar) type
        /// shrinks and margins tighten. Showing or hiding the sidebar
        /// resizes the window around the page, so it never changes this.
        static let compactPageWidth: CGFloat = 472
        /// Behind the floating sidebar in a small window.
        static let scrimOpacity = 0.3
        /// Under the floating sidebar, the only shadow in the main window.
        static let floatingShadowOpacity = 0.35
        static let floatingShadowRadius: CGFloat = 24
        static let floatingShadowOffset: CGFloat = 6
        static let radius: CGFloat = 12
        static let rowRadius: CGFloat = 7
        static let rowHeight: CGFloat = 30
        /// Deck rows in a page's list, Today's and the overview's.
        static let listRowHeight: CGFloat = 50
        static let listRowRadius: CGFloat = 10
        static let focusRingWidth: CGFloat = 2
        /// The gap between a deck ring's track and its pie, as a share of the ring.
        static let ringPieInset: CGFloat = 0.08
        /// How far Up and Down scroll a page.
        static let arrowScroll: CGFloat = 60
        /// Each level of a deck tree steps in this far.
        static let indent: CGFloat = 14
        static let pageWidth: CGFloat = 680
        static let pageMargin: CGFloat = 56
        /// Room under a page's last block, so it doesn't end on the window's edge.
        static let pageBottomPadding: CGFloat = 40
        static let compactPageMargin: CGFloat = 18
        /// A list row's content keeps to the page's edge; its hover wash
        /// reaches this far past it on both sides, as in Things.
        static let washOutset: CGFloat = 12
        /// The dot on a quiet button that has something waiting (Sync).
        static let badgeDot: CGFloat = 7
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
        /// A symbol standing as a page title's icon, the size of the deck ring there.
        static let titleSymbol = Font.system(size: 24, weight: .medium)
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
        /// Show Answer is one line, so it is shorter than the grades, and
        /// as wide as its label, in the middle of their row.
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
        /// How long the message after a card action stays over the card.
        static let feedbackDuration: Duration = .seconds(2.5)
        /// Keeps the message above the answer bar.
        static let feedbackBottomInset: CGFloat = 90
        static let editorWidth: CGFloat = 560
        static let editorHeight: CGFloat = 420
    }

    /// The media sync capsule over the main window.
    enum MediaSync {
        /// How often the backend is asked how media sync is going.
        static let pollInterval: Duration = .milliseconds(250)
        /// A media sync that finishes sooner than this shows nothing.
        static let showDelay: Duration = .milliseconds(500)
        /// Once shown, the capsule stays at least this long, so it never
        /// flickers.
        static let minimumShown: Duration = .seconds(1.2)
        /// How long "complete" stays before the capsule goes.
        static let completeHold: Duration = .seconds(1.5)
        /// Wide enough for most counts, so the capsule rarely grows.
        static let minWidth: CGFloat = 200
        static let leadingInset: CGFloat = 10
        /// The spinner and the checkmark that replaces it share this box.
        static let iconSize: CGFloat = 16
        static let lineSpacing: CGFloat = 1
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

    enum QuickFind {
        static let width: CGFloat = 400
        static let topInset: CGFloat = 64
        static let listMaxHeight: CGFloat = 420
        static let fieldHeight: CGFloat = 36
        static let cornerRadius: CGFloat = 20
        /// The panel's radius less its padding, so the field's corners follow the panel's.
        static let fieldRadius: CGFloat = 12
        static let rowRadius: CGFloat = 10
        static let rowPadding: CGFloat = 5
        /// Tints the glass toward the canvas without hiding the page beneath.
        static let tintOpacity = 0.3
        static let noteLimit = 5
        /// Decks listed before anything is typed, after Today.
        static let dueLimit = 6
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
        /// Graphs sit side by side once each can be this wide, as desktop's
        /// one to three columns.
        static let graphMinWidth: CGFloat = 440
        static let maxColumns = 3
        static let columnGap: CGFloat = Spacing.xLarge
        /// Room under the hairline over each graph, and between rows of graphs.
        static let sectionPadding: CGFloat = Spacing.large
        static let rowGap: CGFloat = Spacing.xLarge
        static let chartHeight: CGFloat = 220
        static let pdfWidth: CGFloat = 760
        /// The search box under the header.
        static let searchWidth: CGFloat = 360
        /// The scope, history and range switches, as tall as a chip.
        static let controlHeight: CGFloat = 28
        static let segmentPadding: CGFloat = 10
        /// Room around a menu's label for its hover wash.
        static let menuPadding: CGFloat = Spacing.small
        static let menuChevron = Font.system(size: 9, weight: .bold)
        /// Desktop asks d3 for about 7 ticks along x and 5 up y.
        static let xTickCount: Double = 7
        static let yTickCount: Double = 5
        /// The gap between bars, as a share of each side of a bar.
        static let barInset = 0.06
        /// d3's inner band padding for the hour and button bars.
        static let bandPadding = 0.1
        /// Every number in the window is in the rounded face, as the main window's.
        static let axisFont = Font.system(size: 11, weight: .medium, design: .rounded).monospacedDigit()
        static let figures = Font.system(size: 13, weight: .medium, design: .rounded).monospacedDigit()
        static let tableFont = Font.system(size: 13)
        static let tooltipFont = Font.system(size: 12.5, weight: .medium, design: .rounded).monospacedDigit()
        static let todayLead = Fonts.lead
        static let todayLeadFigures = Font.system(size: 15, design: .rounded).monospacedDigit()
        static let todayFigures = Font.system(size: 14, design: .rounded).monospacedDigit()
        static let gridLine = Palette.hairline
        static let hoverColumn = Palette.selection
        /// The running total behind the bars, as desktop's faint overlay:
        /// the lightest wash, since it often covers most of the plot.
        static let areaFill = Palette.hover
        static let tooltipRadius: CGFloat = 8
        static let tooltipOffset: CGFloat = 14
        static let swatchSize: CGFloat = 9
        static let swatchRadius: CGFloat = 2
        /// Lines a table label up with the labels that have a colour swatch.
        static let swatchIndent: CGFloat = swatchSize + Spacing.xSmall
        static let pieSize: CGFloat = 180
        static let calendarGap: CGFloat = 2
        static let calendarRadius: CGFloat = 2
        static let calendarLabelWidth: CGFloat = 14
        /// A day stays this big at least; a narrower window scrolls the year.
        static let calendarMinCell: CGFloat = 9
        static let calendarWeeks = 54
        static let calendarEmpty = Palette.selection
        static let calendarHoverBorder: CGFloat = 1.5
        static let calendarTooltipGap: CGFloat = 6

        /// A graph's colour at strength `t` (0 to 1): mixed into the canvas
        /// rather than faded, so the bars stay opaque over the running total.
        static func shade(_ colour: Color, _ t: Double) -> Color {
            Palette.canvas.mix(with: colour, by: min(max(t, 0), 1))
        }

        /// The queue colours, for the kinds of card and review: new blue,
        /// learning coral (relearning full, first learning lighter), review
        /// green (mature full, young lighter).
        static let newCards = Colors.newCards
        static let learning = shade(Colors.learnCards, 0.55)
        static let relearning = Colors.learnCards
        static let young = shade(Colors.reviewCards, 0.55)
        static let mature = Colors.reviewCards
        static let filtered = Palette.violet
        /// Desktop's yellow for suspended cards, in the palette's warmth.
        static let suspended = Palette.dynamic(0xC99A16, 0xE3BE4E)
        static let buried = Palette.tertiary
        /// The retention table's columns.
        static let youngRetention = young
        static let matureRetention = mature
        static let pass = Colors.reviewCards
        static let fail = Colors.learnCards
        /// Again, Hard, Good and Easy, as the answer buttons colour them.
        static let grades = [Palette.coral, Palette.amber, Palette.green, Palette.blue]
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
