import AnkiKit
import AppKit
import SwiftUI

// The main window's building blocks: its frame (title bar, top strip,
// sidebar state), the shared page layout, and the custom controls. Values
// come from Theme.

// MARK: - Window layout

/// Whether the sidebar shows, and how: beside the content, or floating over
/// it in a small window, where it closes once something is picked.
///
/// As in Things 3, showing or hiding the docked sidebar grows or shrinks
/// the window by its width from the right edge, and the page keeps its size
/// and slides across, over the sidebar, which stays put. Where the window can't change (full screen, or
/// no room on screen) the sidebar pushes the page aside instead. Narrowing
/// the window by hand only narrows the page; the sidebar stays until it is
/// hidden.
@Observable final class WindowLayout {
    var sidebarVisible = !UserDefaults.standard.bool(forKey: "sidebarHidden") {
        didSet { if !sidebarFloats { UserDefaults.standard.set(!sidebarVisible, forKey: "sidebarHidden") } }
    }
    var sidebarFloats = false
    /// The page's width, held while the window slides around it.
    var pageWidth: CGFloat?
    @ObservationIgnored weak var window: NSWindow?
    /// Up and Down move through the sidebar until the page is clicked or
    /// scrolled; then they scroll the page, until something is picked in
    /// the sidebar again.
    var arrowsMoveSidebar = true
    /// Scrolls the page on screen by a distance; false when it can't move.
    /// `owner` tells pages apart while one replaces another.
    @ObservationIgnored var scrollPage: (owner: UUID, scroll: (CGFloat) -> Bool)?

    func toggleSidebar(_ visible: Bool? = nil) {
        let show = visible ?? !sidebarVisible
        guard show != sidebarVisible, pageWidth == nil else { return }
        let sidebar = Theme.Layout.sidebarWidth
        if let window, !window.styleMask.contains(.fullScreen), let screen = window.screen?.visibleFrame {
            var frame = window.frame
            if show, frame.width + sidebar <= screen.width {
                frame.size.width += sidebar
                frame.origin.x = max(min(frame.minX, screen.maxX - frame.width), screen.minX)
                return slide(window, to: frame, page: window.frame.width, show: true)
            }
            if !show, !sidebarFloats, frame.width - sidebar >= Theme.Window.minWidth {
                frame.size.width -= sidebar
                return slide(window, to: frame, page: frame.width, show: false)
            }
        }
        if show { sidebarFloats = (window?.frame.width ?? .infinity) < Theme.Layout.compactWidth }
        withAnimation(.smooth(duration: 0.28)) { sidebarVisible = show }
    }

    /// Moves the window's right edge by the sidebar's width, the page held
    /// at its width against it, so the page slides over the sidebar.
    private func slide(_ window: NSWindow, to frame: NSRect, page: CGFloat, show: Bool) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            pageWidth = page
            sidebarFloats = false
            sidebarVisible = show
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { self?.pageWidth = nil }
            }
        }
    }

    /// The window crossed `compactWidth`, resized by hand or by going full
    /// screen: a floating sidebar docks once there is room for it.
    func windowWidthChanged(narrow: Bool) {
        guard pageWidth == nil, !narrow, sidebarFloats else { return }
        withAnimation(.smooth(duration: 0.28)) { sidebarFloats = false }
    }

    /// After picking something in the sidebar.
    func picked() {
        arrowsMoveSidebar = true
        if sidebarFloats { toggleSidebar(false) }
    }
}

extension FocusedValues {
    @Entry var windowLayout: WindowLayout?
}

/// View › Toggle Sidebar, in place of the split view's.
struct LayoutCommands: Commands {
    @FocusedValue(\.windowLayout) private var layout

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { layout?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(layout == nil)
        }
    }
}

extension EnvironmentValues {
    /// True in a small window: smaller type, tighter margins, fewer controls.
    @Entry var compact = false
}

extension ToolbarContent {
    /// Toolbar buttons drawn plainly, without the toolbar's glass capsule.
    func plain() -> some ToolbarContent {
        sharedBackgroundVisibility(.hidden)
    }
}

// MARK: - Pages

/// The reading column the overview and Today share: centred, capped in
/// width, with margins that shrink in a small window.
struct Page<Content: View>: View {
    @Environment(\.compact) private var compact
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? Theme.Spacing.medium : Theme.Spacing.large) { content }
                .frame(maxWidth: Theme.Layout.pageWidth, alignment: .leading)
                .padding(.horizontal, compact ? Theme.Layout.compactPageMargin : Theme.Layout.pageMargin)
                .padding(.top, compact ? 0 : Theme.Spacing.small)
                .padding(.bottom, Theme.Layout.pageBottomPadding)
                .frame(maxWidth: .infinity)
        }
        .pageScrolling()
    }
}

/// What every page's scroll view shares: the arrow keys scroll it once it
/// has been clicked or scrolled (see WindowLayout), and it is clipped so it
/// scrolls out of sight below the title bar, not under the window's buttons
/// and the toolbar.
private struct PageScrolling: ViewModifier {
    @Environment(WindowLayout.self) private var layout
    @State private var position = ScrollPosition(edge: .top)
    @State private var id = UUID()
    @State private var geometry = ScrollGeometry(
        contentOffset: .zero, contentSize: .zero, contentInsets: EdgeInsets(), containerSize: .zero)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in geometry = new }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { layout.arrowsMoveSidebar = false }
            }
            .simultaneousGesture(TapGesture().onEnded { layout.arrowsMoveSidebar = false })
            .onAppear { layout.scrollPage = (id, scroll) }
            .onDisappear { if layout.scrollPage?.owner == id { layout.scrollPage = nil } }
            .clipped()
    }

    private func scroll(by distance: CGFloat) -> Bool {
        let limit = max(0, geometry.contentSize.height - geometry.containerSize.height)
        let target = min(max(0, geometry.contentOffset.y + distance), limit)
        guard target != geometry.contentOffset.y else { return false }
        withAnimation(.smooth(duration: 0.15)) { position.scrollTo(y: target) }
        return true
    }
}

extension View {
    /// For a page's scroll view.
    func pageScrolling() -> some View { modifier(PageScrolling()) }
}

/// A small heading over a large title with its icon, as Things titles a list.
struct PageTitle<Icon: View>: View {
    @Environment(\.compact) private var compact
    let eyebrow: String
    let title: String
    var lineLimit: Int? = 2
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !eyebrow.isEmpty {
                Eyebrow(eyebrow)
            }
            HStack(spacing: Theme.Spacing.medium) {
                // One width for every page's icon, so the title starts in the same place on each.
                icon.frame(width: Theme.Layout.titleIconWidth)
                Text(title)
                    .font(compact ? Theme.Fonts.compactTitle : Theme.Fonts.title)
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: lineLimit == nil)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A named list on a page, set further from what's above it than its rows
/// are from its name, so the page reads in groups.
struct PageSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            Eyebrow(title).padding(.bottom, Theme.Spacing.xSmall)
            content
        }
        .padding(.top, Theme.Spacing.medium)
    }
}

/// Small spaced capitals, for section names and the path over a title.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Fonts.eyebrow)
            .tracking(Theme.Fonts.eyebrowTracking)
            .foregroundStyle(Theme.Palette.secondary)
            .lineLimit(1)
    }
}

/// How many cards are due, large, over the three queues on one line, with
/// the page's action (if any) at the trailing edge. Unboxed: type and
/// alignment carry it. The action moves under the counts when the row is
/// too narrow.
struct DueSummary<Action: View>: View {
    let new: Int
    let learn: Int
    let review: Int
    @ViewBuilder let action: Action

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Theme.Spacing.large) {
                counts
                Spacer(minLength: Theme.Spacing.small)
                action
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                counts
                action
            }
        }
    }

    private var counts: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(new + learn + review, format: .number).font(Theme.Fonts.bigNumber)
                Text("due").font(Theme.Fonts.lead).foregroundStyle(Theme.Palette.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
                queue(new, "new", Theme.Colors.newCards)
                queue(learn, "learning", Theme.Colors.learnCards)
                queue(review, "to review", Theme.Colors.reviewCards)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(new + learn + review) due: \(new) new, \(learn) learning, \(review) to review")
    }

    private func queue(_ value: Int, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xSmall) {
            Text(value, format: .number).font(Theme.Fonts.queueCount)
                .foregroundStyle(value == 0 ? Theme.Colors.zeroCount : color)
            Text(label).font(Theme.Fonts.body)
                .foregroundStyle(value == 0 ? Theme.Palette.tertiary : Theme.Palette.secondary)
        }
    }
}

/// A deck in a page's list: its ring, name and path, its counts, and a
/// Study button that shows on hover. The row is a button that opens the
/// deck (click, or Space when it has keyboard focus); VoiceOver reads it as
/// one element with Study as an action, so the hover-only button stays
/// out of its way and out of the keyboard loop.
struct DeckListRow: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.compact) private var compact
    let deck: DeckNode
    var path = ""
    /// On Today, studying the row comes back to Today.
    var onToday = false
    @State private var hovered = false
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Layout.listRowRadius)
        HStack(spacing: Theme.Spacing.medium) {
            DeckRing(deck: deck, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.name).font(Theme.Fonts.listRow).lineLimit(1)
                if !path.isEmpty {
                    Text(path).font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.small)
            // The play button takes the counts' place under the pointer, so
            // at rest they keep to the page's edge, under the title's action.
            let playing = hovered && deck.dueCount > 0
            Group {
                if compact {
                    Text(deck.dueCount, format: .number).font(Theme.Fonts.sidebarCount)
                        .foregroundStyle(Theme.Palette.secondary)
                } else {
                    DueCounts(new: deck.newCount, learn: deck.learnCount, review: deck.reviewCount)
                        .font(Theme.Fonts.studyCounts)
                }
            }
            .opacity(playing ? 0 : 1)
            .overlay(alignment: .trailing) {
                Button(action: study) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.Palette.accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .opacity(playing ? 1 : 0)
                .disabled(!playing)
                .focusable(false)
                .help("Study \(deck.name)")
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Layout.washOutset)
        .frame(height: Theme.Layout.listRowHeight)
        .background(shape.fill(hovered ? Theme.Palette.hover : .clear))
        .overlay {
            if focused { shape.strokeBorder(Theme.Palette.accent, lineWidth: Theme.Layout.focusRingWidth) }
        }
        .padding(.horizontal, -Theme.Layout.washOutset)
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onTapGesture(perform: open)
        // Reachable with Tab when the system's keyboard navigation is on, as buttons are.
        .focusable(interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            open()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path.isEmpty ? deck.name : "\(deck.name), \(path)")
        .accessibilityValue("\(deck.newCount) new, \(deck.learnCount) learning, \(deck.reviewCount) to review")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, open)
        .accessibilityActions {
            if deck.dueCount > 0 { Button("Study", action: study) }
        }
    }

    private func open() { model.selectedDeckID = deck.id }

    private func study() {
        if onToday { model.studyFromToday(deck.id) } else {
            model.selectedDeckID = deck.id
            model.startStudying()
        }
    }
}

/// A deck's icon: a pie that fills as today's cards are answered, coral
/// while cards in learning are waiting. Its track is a faint neutral
/// hairline and only the filled part carries colour, so an untouched deck
/// doesn't read as an unchecked to-do.
struct DeckRing: View {
    @Environment(CollectionModel.self) private var model
    let deck: DeckNode
    var size: CGFloat = 14
    var selected = false

    var body: some View {
        // A fresh ring per deck, so one deck's pie never animates into another's.
        Ring(done: model.progress(deck), tint: tint, size: size).id(deck.id)
    }

    private var tint: Color {
        deck.learnCount > 0 ? Theme.Palette.coral : selected ? Theme.Palette.accent : Theme.Palette.secondary
    }

    /// Only the fill animates, in its own transaction: an implicit animation
    /// here would also catch the ring moving as a page lays out, and slide
    /// it. The pie fills from empty as the ring appears, then follows the
    /// day's progress.
    private struct Ring: View {
        let done: Double
        let tint: Color
        let size: CGFloat
        @State private var shown = 0.0
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                Circle().strokeBorder(Theme.Palette.selection, lineWidth: max(1.2, size / 10))
                Pie(progress: shown)
                    .fill(tint)
                    .padding(size * Theme.Layout.ringPieInset)
            }
            .frame(width: size, height: size)
            .onAppear { show(done) }
            .onChange(of: done) { _, done in show(done) }
            .accessibilityLabel("\(Int(done * 100)) percent done today")
        }

        private func show(_ value: Double) {
            if reduceMotion { shown = value } else { withAnimation(.smooth) { shown = value } }
        }
    }

    /// A wedge from twelve o'clock, clockwise, filled solid to the centre.
    private nonisolated struct Pie: Shape {
        var progress: Double
        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            var path = Path()
            guard progress > 0 else { return path }
            guard progress < 1 else { return Path(ellipseIn: rect) }
            path.move(to: center)
            path.addArc(
                center: center, radius: radius, startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * progress), clockwise: false)
            path.closeSubpath()
            return path
        }
    }
}

/// New, learning and review counts in Anki's colours.
struct DueCounts: View {
    let new: Int
    let learn: Int
    let review: Int
    var highlighted: Anki_Scheduler_QueuedCards.Queue? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            count(new, Theme.Colors.newCards, queue: .new)
            count(learn, Theme.Colors.learnCards, queue: .learning)
            count(review, Theme.Colors.reviewCards, queue: .review)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(new) new, \(learn) learning, \(review) to review")
    }

    private func count(_ value: Int, _ color: Color, queue: Anki_Scheduler_QueuedCards.Queue) -> some View {
        Text(value, format: .number)
            .foregroundStyle(value == 0 ? Theme.Colors.zeroCount : color)
            .underline(highlighted == queue)
    }
}

// MARK: - Controls

/// Anki's star: five plump, rounded points, tilted as in its logo, drawn as
/// an outline in the current foreground style.
struct AnkiStar: View {
    var size: CGFloat = 16

    var body: some View {
        StarShape()
            .stroke(style: StrokeStyle(lineWidth: size * 0.14, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(-14))
            .padding(size * 0.07)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private nonisolated struct StarShape: Shape {
        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
            let outer = min(rect.width, rect.height) / 2
            let inner = outer * 0.52
            let points: [CGPoint] = (0..<10).map { i in
                let angle = -Double.pi / 2 + Double(i) * .pi / 5
                let radius = i.isMultiple(of: 2) ? outer : inner
                return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            }
            func toward(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            // Each corner is cut short on both sides and curved through, the
            // tips more than the dips between them.
            var path = Path()
            for i in 0..<10 {
                let point = points[i]
                let rounding: CGFloat = i.isMultiple(of: 2) ? 0.32 : 0.18
                let start = toward(point, points[(i + 9) % 10], rounding)
                let end = toward(point, points[(i + 1) % 10], rounding)
                if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
                path.addQuadCurve(to: end, control: point)
            }
            path.closeSubpath()
            return path
        }
    }
}

/// Two chevrons, stacked: pointing apart to unfold everything, toward each
/// other to fold it (Obsidian's icons). Between the two they flatten and
/// turn over, so a change of meaning animates.
struct FoldAllGlyph: View {
    /// 0 points the chevrons apart, 1 toward each other.
    var folding: CGFloat

    var body: some View {
        ChevronPair(folding: folding)
            .stroke(style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
            .frame(width: 15, height: 15)
            .accessibilityHidden(true)
    }

    private nonisolated struct ChevronPair: Shape {
        var folding: CGFloat
        var animatableData: CGFloat {
            get { folding }
            set { folding = newValue }
        }

        // Drawn on a 24-point grid, as Lucide's chevrons are.
        func path(in rect: CGRect) -> Path {
            let scale = min(rect.width, rect.height) / 24
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
            }
            func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * folding }
            var path = Path()
            for (tip, arms) in [(lerp(3, 9), lerp(9, 3)), (lerp(21, 15), lerp(15, 21))] {
                path.move(to: point(6, arms))
                path.addLine(to: point(12, tip))
                path.addLine(to: point(18, arms))
            }
            return path
        }
    }
}

/// A key's name in a small rounded box, shown beside the action it does.
struct KeyCap: View {
    let key: String
    var onAccent = false
    init(_ key: String, onAccent: Bool = false) {
        self.key = key
        self.onAccent = onAccent
    }

    var body: some View {
        Text(key)
            .font(Theme.Fonts.keyCap)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 17)
            .foregroundStyle(onAccent ? Color.white.opacity(0.9) : Theme.Palette.secondary)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(onAccent ? Color.white.opacity(0.2) : Theme.Palette.hairline))
            .accessibilityHidden(true)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    init(_ symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
        }
        .buttonStyle(QuietButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Secondary text and icons that brighten on hover and dip when pressed.
/// `selected` holds the Ink and selection wash of a switch that is on.
struct QuietButtonStyle: ButtonStyle {
    var selected = false
    /// Room either side of the label; dense bars set their own size and use none.
    var inset = Theme.Spacing.xSmall

    func makeBody(configuration: Configuration) -> some View {
        QuietBody(configuration: configuration, selected: selected, inset: inset)
    }

    private struct QuietBody: View {
        let configuration: Configuration
        let selected: Bool
        let inset: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, inset)
                .foregroundStyle(selected || hovered && isEnabled ? Theme.Palette.text : Theme.Palette.secondary)
                .opacity(isEnabled ? 1 : 0.4)
                .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
                    .fill(configuration.isPressed || selected ? Theme.Palette.selection
                        : hovered && isEnabled ? Theme.Palette.hover : .clear))
                .contentShape(.rect)
                .onHover { hovered = $0 }
        }
    }
}

/// A row of quiet choices, the chosen one on the selection wash in Ink,
/// so a page of switches doesn't fill with accent blue.
struct QuietSegments<Choice: Hashable>: View {
    @Binding var selection: Choice
    let choices: [Choice]
    let title: (Choice) -> String

    var body: some View {
        HStack(spacing: Theme.Spacing.xxSmall) {
            ForEach(choices, id: \.self) { choice in
                let chosen = choice == selection
                Button(title(choice)) { selection = choice }
                    .buttonStyle(SegmentStyle(chosen: chosen))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    private struct SegmentStyle: ButtonStyle {
        let chosen: Bool

        func makeBody(configuration: Configuration) -> some View {
            SegmentBody(configuration: configuration, chosen: chosen)
        }

        private struct SegmentBody: View {
            let configuration: Configuration
            let chosen: Bool
            @State private var hovered = false

            var body: some View {
                configuration.label
                    .font(Theme.Fonts.chip)
                    .foregroundStyle(chosen || hovered ? Theme.Palette.text : Theme.Palette.secondary)
                    .padding(.horizontal, Theme.Layout.segmentPadding)
                    .frame(height: Theme.Layout.controlHeight)
                    .background(Capsule().fill(
                        chosen || configuration.isPressed ? Theme.Palette.selection : hovered ? Theme.Palette.hover : .clear))
                    .contentShape(Capsule())
                    .onHover { hovered = $0 }
            }
        }
    }
}

/// The one prominent action on a page, in the accent colour.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.button)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.Palette.accent))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(.rect)
    }
}

/// Secondary actions, as small rounded chips that brighten under the
/// pointer and dip when pressed.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration)
    }

    private struct ChipBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(Theme.Fonts.chip)
                .foregroundStyle(Theme.Palette.text)
                .padding(.horizontal, Theme.Spacing.medium)
                .frame(height: 28)
                .background {
                    // The washes sit over the chip's own fill.
                    Capsule().fill(Theme.Palette.raised)
                    Capsule().fill(configuration.isPressed ? Theme.Palette.selection
                        : hovered && isEnabled ? Theme.Palette.hover : .clear)
                }
                .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { hovered = $0 }
        }
    }
}

/// A rating: its label in its colour on a neutral wash; the colour fills in
/// only under the pointer and when pressed, so four answers at rest read as
/// one quiet row rather than four tinted blocks. It fills the width it is
/// given, so the four share a row evenly. Without `rests`, it has no wash
/// or hairline until the pointer is over it, as Show Answer does.
struct GradeButtonStyle: ButtonStyle {
    let color: Color
    let emphasised: Bool
    var rests = true

    func makeBody(configuration: Configuration) -> some View {
        GradeBody(configuration: configuration, color: color, emphasised: emphasised, rests: rests)
    }

    private struct GradeBody: View {
        let configuration: Configuration
        let color: Color
        let emphasised: Bool
        let rests: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Spacing.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 11)
                    .fill(configuration.isPressed ? color.opacity(0.22)
                        : hovered ? color.opacity(0.12) : rests ? Theme.Palette.hover : .clear))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(emphasised ? color.opacity(0.55) : rests ? Theme.Palette.hairline : .clear,
                        lineWidth: emphasised ? 1.5 : 1))
                .contentShape(.rect)
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Two-finger swipe

extension View {
    /// A sideways two-finger swipe on the trackpad: `true` when the fingers
    /// move right. One call per gesture; mostly-vertical scrolls, the
    /// momentum after lifting and mouse wheels are ignored, as are swipes
    /// in other windows than `window`.
    func onSidebarSwipe(in window: @escaping () -> NSWindow?, _ action: @escaping (Bool) -> Void) -> some View {
        modifier(SidebarSwipe(window: window, action: action))
    }
}

private struct SidebarSwipe: ViewModifier {
    let window: () -> NSWindow?
    let action: (Bool) -> Void
    @State private var tracker = SwipeTracker()

    func body(content: Content) -> some View {
        content
            .onAppear {
                tracker.window = window
                tracker.action = action
                tracker.start()
            }
            .onDisappear { tracker.stop() }
    }
}

private final class SwipeTracker {
    var window: () -> NSWindow? = { nil }
    var action: (Bool) -> Void = { _ in }
    private var monitor: Any?
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var fired = false

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.window === window(), event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        if event.phase.contains(.began) {
            dx = 0
            dy = 0
            fired = false
        }
        guard event.phase.contains(.changed), !fired else { return }
        // Follow the fingers whatever the natural-scrolling setting.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        dx += event.scrollingDeltaX * sign
        dy += event.scrollingDeltaY
        if abs(dx) > Theme.Layout.swipeDistance, abs(dx) > 2 * abs(dy) {
            fired = true
            action(dx > 0)
        }
    }
}
