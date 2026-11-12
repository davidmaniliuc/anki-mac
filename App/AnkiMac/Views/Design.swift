import AnkiKit
import AppKit
import SwiftUI

// The main window's building blocks: its frame (title bar, top strip,
// sidebar state), the shared page layout, and the custom controls. Values
// come from Theme.

// MARK: - Window layout

/// Whether the sidebar shows, and how: beside the content, or floating over
/// it in a small window, where it closes once something is picked.
@Observable final class WindowLayout {
    var sidebarVisible = true
    var sidebarFloats = false

    func toggleSidebar(_ visible: Bool? = nil) {
        withAnimation(.smooth(duration: 0.28)) { sidebarVisible = visible ?? !sidebarVisible }
    }

    /// After picking something in a floating sidebar.
    func picked() {
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
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
        }
        // The page scrolls out of sight below the title bar, not under the
        // window's buttons and the toolbar.
        .clipped()
    }
}

/// A small heading over a large title with its icon, as Things titles a list.
struct PageTitle<Icon: View>: View {
    @Environment(\.compact) private var compact
    let eyebrow: String
    let title: String
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !eyebrow.isEmpty {
                Eyebrow(eyebrow)
            }
            HStack(spacing: Theme.Spacing.medium) {
                icon
                Text(title)
                    .font(compact ? Theme.Fonts.compactTitle : Theme.Fonts.title)
                    .lineLimit(2)
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

/// A deck in a page's list: its dot, name and path, its counts, and a
/// Study button that shows on hover (Return in the overview does the same).
struct DeckListRow: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.compact) private var compact
    let deck: DeckNode
    var path = ""
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            DeckRing(deck: deck, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(deck.name).font(Theme.Fonts.listRow).lineLimit(1)
                if !path.isEmpty {
                    Text(path).font(Theme.Fonts.caption).foregroundStyle(Theme.Palette.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.small)
            if compact {
                Text(deck.dueCount, format: .number).font(Theme.Fonts.sidebarCount)
                    .foregroundStyle(Theme.Palette.secondary)
            } else {
                DueCounts(new: deck.newCount, learn: deck.learnCount, review: deck.reviewCount)
                    .font(Theme.Fonts.studyCounts)
            }
            Button {
                model.selectedDeckID = deck.id
                model.startStudying()
            } label: {
                Image(systemName: "play.fill").font(.system(size: 10))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.Palette.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .opacity(hovered && deck.dueCount > 0 ? 1 : 0)
            .disabled(deck.dueCount == 0)
            .help("Study \(deck.name)")
            .accessibilityLabel("Study \(deck.name)")
        }
        .padding(.horizontal, Theme.Layout.washOutset)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? Theme.Palette.hover : .clear))
        .padding(.horizontal, -Theme.Layout.washOutset)
        .contentShape(.rect)
        .onHover { hovered = $0 }
        .onTapGesture { model.selectedDeckID = deck.id }
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
        let tint = deck.learnCount > 0 ? Theme.Palette.coral : selected ? Theme.Palette.accent : Theme.Palette.secondary
        let done = model.progress(deck)
        ZStack {
            Circle().strokeBorder(Theme.Palette.selection, lineWidth: max(1.2, size / 10))
            Circle()
                .trim(from: 0, to: done)
                .stroke(tint, style: StrokeStyle(lineWidth: size / 2.6))
                .rotationEffect(.degrees(-90))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: done)
        .accessibilityLabel("\(Int(done * 100)) percent done today")
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
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietBody(configuration: configuration)
    }

    private struct QuietBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .padding(.horizontal, Theme.Spacing.xSmall)
                .foregroundStyle(hovered && isEnabled ? Theme.Palette.text : Theme.Palette.secondary)
                .opacity(isEnabled ? 1 : 0.4)
                .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
                    .fill(configuration.isPressed ? Theme.Palette.selection : hovered && isEnabled ? Theme.Palette.hover : .clear))
                .contentShape(.rect)
                .onHover { hovered = $0 }
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
/// given, so the four share a row evenly.
struct GradeButtonStyle: ButtonStyle {
    let color: Color
    let emphasised: Bool

    func makeBody(configuration: Configuration) -> some View {
        GradeBody(configuration: configuration, color: color, emphasised: emphasised)
    }

    private struct GradeBody: View {
        let configuration: Configuration
        let color: Color
        let emphasised: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(color)
                .padding(.horizontal, Theme.Spacing.medium)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 11)
                    .fill(configuration.isPressed ? color.opacity(0.22)
                        : hovered ? color.opacity(0.12) : Theme.Palette.hover))
                .overlay(RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(emphasised ? color.opacity(0.55) : Theme.Palette.hairline, lineWidth: emphasised ? 1.5 : 1))
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
