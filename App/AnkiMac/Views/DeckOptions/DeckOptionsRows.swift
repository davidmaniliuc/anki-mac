import SwiftUI

/// One setting: its title, with the explanation as a help tag, the control,
/// and, once the value differs from the default, a menu that restores it
/// (desktop's revert badge).
struct OptionRow<Control: View>: View {
    let title: String
    var help = ""
    var isDefault = true
    var revert: (() -> Void)? = nil
    /// False where settings have no defaults to go back to, as Settings',
    /// so the control keeps to the edge.
    var revertible = true
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Text(title)
                .font(Theme.DeckOptions.rowFont)
                .foregroundStyle(Theme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                // A control that can shrink does so before the title wraps.
                .layoutPriority(1)
                .help(help)
            Spacer(minLength: Theme.Spacing.small)
            HStack(spacing: Theme.Spacing.xSmall) {
                // The tooltip is out of reach without a pointer, so the
                // control speaks it as its hint.
                control
                    .environment(\.optionTitle, title)
                    .accessibilityHint(plainText(help))
                if revertible {
                    RevertMenu(hidden: isDefault, revert: revert)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension EnvironmentValues {
    /// The row's title, for VoiceOver on fields whose label is hidden.
    @Entry var optionTitle = ""
}

extension EnvironmentValues {
    /// The widest unit in the section, so its numbers line up.
    @Entry var optionUnitWidth: CGFloat = 0
}

/// The units' widths in a section, measured as they are drawn.
private struct UnitWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension ContainerValues {
    /// A line that belongs to the setting above it, a note or its actions,
    /// so no hairline divides them.
    @Entry var optionNote = false
}

extension View {
    func optionNote() -> some View { containerValue(\.optionNote, true) }
}

/// A named group of settings on the canvas: an eyebrow with the section's
/// help, then its rows under hairlines, as Statistics' graphs are. With no
/// title, the rows start under the sheet's Headline.
struct OptionSection<Content: View>: View {
    var title = ""
    var help: [(title: String, text: String)] = []
    @ViewBuilder let content: Content

    @State private var unitWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                OptionSectionHeader(title: title, help: help)
                    .padding(.bottom, Theme.Spacing.xSmall)
            }
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.containerValues.optionNote {
                        row.padding(.bottom, Theme.DeckOptions.notePadding)
                    } else {
                        Theme.Palette.hairline.frame(height: 1)
                        row
                            .padding(.vertical, Theme.DeckOptions.rowPadding)
                            .frame(minHeight: Theme.DeckOptions.rowMinHeight)
                    }
                }
            }
        }
        .environment(\.optionUnitWidth, unitWidth)
        .onPreferenceChange(UnitWidthKey.self) { unitWidth = $0 }
    }
}

/// A switch whose title is shown by its row. Hiding the label also hides it
/// from VoiceOver, so the accessible version keeps it.
struct SwitchControl: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.DeckOptions.controlTint)
            .accessibilityRepresentation { Toggle(title, isOn: $isOn) }
    }
}

/// Keeps its width when hidden, so the controls don't shift as values change.
private struct RevertMenu: View {
    let hidden: Bool
    let revert: (() -> Void)?

    var body: some View {
        Menu {
            Button(Tr.deckConfigRevertButtonTooltip) { revert?() }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(Theme.DeckOptions.revertSymbol)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(width: Theme.DeckOptions.revertSize.width, height: Theme.DeckOptions.revertSize.height)
                .modifier(MenuHover(shape: RoundedRectangle(cornerRadius: Theme.Layout.rowRadius), inset: 0))
                .accessibilityLabel(Tr.deckConfigRevertButtonTooltip)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Tr.deckConfigRevertButtonTooltip)
        .opacity(hidden || revert == nil ? 0 : 1)
        .disabled(hidden || revert == nil)
        .accessibilityHidden(hidden || revert == nil)
    }
}

/// A text field drawn as a quiet control: a Raised Oat box under a
/// hairline, deepened by the selection wash while it has focus.
private struct QuietField: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.Palette.text)
            .padding(.horizontal, Theme.DeckOptions.fieldPadding)
            .frame(height: Theme.DeckOptions.fieldHeight)
            .background(QuietFieldBox(focused: focused))
    }
}

/// The quiet box of a text field, shared with the tag field: no accent
/// ring, as the Browser's search field, since the caret already shows
/// where typing goes.
struct QuietFieldBox: View {
    let focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
        shape.fill(Theme.Palette.raised)
            .overlay { shape.fill(focused ? Theme.Palette.selection : .clear) }
            .overlay { shape.strokeBorder(Theme.Palette.hairline) }
    }
}

extension View {
    func quietField(focused: Bool) -> some View { modifier(QuietField(focused: focused)) }
}

/// A number typed or stepped, clamped to its range. Percentages are stored
/// as fractions and shown out of 100.
struct NumberField: View {
    @Environment(\.optionTitle) private var title
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...9999
    var step: Double = 1
    var decimals = 0
    var percent = false
    /// Words after the stepper, such as "mins", which VoiceOver reads with
    /// the number.
    var unit = ""
    /// Takes the focus as it appears, as the field a sheet is opened for.
    var focusOnAppear = false
    @Environment(\.optionUnitWidth) private var unitWidth
    @FocusState private var focused: Bool

    var body: some View {
        let scale = percent ? 100.0 : 1.0
        HStack(spacing: Theme.Spacing.xSmall) {
            TextField(
                value: Binding { value * scale } set: { value = clamp($0 / scale) },
                format: .number.precision(.fractionLength(decimals)).grouping(.never)
            ) {}
            .labelsHidden()
            .font(Theme.DeckOptions.figures)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .quietField(focused: focused)
            .accessibilityLabel(title)
            .accessibilityValue(spoken(value * scale))
            .frame(width: Theme.DeckOptions.numberFieldWidth)
            .onAppear { if focusOnAppear { focused = true } }
            if percent {
                Text("%").font(Theme.DeckOptions.figures).foregroundStyle(Theme.Palette.secondary)
            }
            Stepper(title, value: Binding { value } set: { value = clamp(rounded($0)) }, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityValue(spoken(value * scale))
            // Every unit in the section takes the widest one's width, so the
            // boxes start in one column and the units read as one.
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.DeckOptions.rowFont)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize()
                    .background(GeometryReader { Color.clear.preference(key: UnitWidthKey.self, value: $0.size.width) })
                    .frame(minWidth: unitWidth, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
    }

    private func spoken(_ shown: Double) -> String {
        let number = shown.formatted(.number.precision(.fractionLength(decimals)))
        return [number + (percent ? "%" : ""), unit].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func clamp(_ newValue: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, newValue))
    }

    /// Stepping 0.1 at a time drifts in binary; keep the shown precision.
    private func rounded(_ newValue: Double) -> Double {
        let places = pow(10, Double(decimals + (percent ? 2 : 0)))
        return (newValue * places).rounded() / places
    }
}

/// A text field that hands its text over when editing ends, for values
/// parsed as a whole, such as learning steps.
struct CommitField: View {
    @Environment(\.optionTitle) private var title
    let text: String
    var prompt = ""
    /// Words, such as a server's address, take the row's face instead.
    var font = Theme.DeckOptions.figures
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $draft, prompt: Text(prompt))
            .labelsHidden()
            .font(font)
            .focused($focused)
            .quietField(focused: focused)
            .onSubmit { commit(draft) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit(draft) }
            }
            .onChange(of: text, initial: true) { _, text in
                if !focused { draft = text }
            }
            // Closing the window or switching tabs while typing keeps the text.
            .onDisappear {
                if draft != text { commit(draft) }
            }
    }
}

/// A text field for words, such as a search, in the same quiet box.
struct OptionTextField: View {
    @Environment(\.optionTitle) private var title
    @Binding var text: String
    var prompt = ""
    /// Figures, such as a due date's days, take the rounded face.
    var font = Theme.DeckOptions.rowFont
    var focusOnAppear = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .labelsHidden()
            .font(font)
            .focused($focused)
            .quietField(focused: focused)
            .onAppear { if focusOnAppear { focused = true } }
    }
}

/// One of a few choices, as a whole row: its title in Ink, and at the
/// trailing edge of the chosen one its setting, or a check as a Mac
/// settings list marks it when it has none. Under the pointer a row not yet
/// chosen shows the hover wash, reaching a little past the text on both
/// sides as a list row's does.
struct ChoiceRow<Setting: View>: View {
    let title: String
    let chosen: Bool
    let choose: () -> Void
    @ViewBuilder var setting: Setting
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Button(action: choose) {
                HStack {
                    Text(title)
                        .font(Theme.DeckOptions.rowFont)
                        .foregroundStyle(Theme.Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Spacing.small)
                }
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen ? .isSelected : [])
            if chosen, Setting.self != EmptyView.self {
                setting
            } else {
                Image(systemName: "checkmark")
                    .font(Theme.DeckOptions.checkSymbol)
                    .foregroundStyle(Theme.Palette.text)
                    .opacity(chosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.small)
        .frame(minHeight: Theme.DeckOptions.rowMinHeight - 2 * Theme.DeckOptions.rowPadding)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius)
            .fill(hovered && !chosen ? Theme.Palette.hover : .clear))
        .padding(.horizontal, -Theme.Spacing.small)
        .onHover { hovered = $0 }
    }
}

extension ChoiceRow where Setting == EmptyView {
    init(title: String, chosen: Bool, choose: @escaping () -> Void) {
        self.init(title: title, chosen: chosen, choose: choose) { EmptyView() }
    }
}

/// A sheet drawn as Deck Options' settings: a Headline, under an eyebrow
/// when the sheet belongs to a deck, then its sections between that and
/// the foot, which holds what's happening and the dialog's buttons. The
/// sheet is as tall as its rows; past `maxHeight` they scroll on the canvas
/// with no hairline or blur at their edges, as the main window's pages.
struct SettingsSheet<Content: View, Footer: View>: View {
    var eyebrow = ""
    let title: String
    let width: CGFloat
    /// A fixed height, for a sheet whose rows arrive after it opens; nil
    /// fits the rows.
    var height: CGFloat?
    /// The most the sheet grows to as rows come and go; nil never scrolls.
    var maxHeight: CGFloat?
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @State private var rowsHeight: CGFloat?
    @State private var chromeHeight: [CGFloat] = [0, 0]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(eyebrow: eyebrow, title: title)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight[0] = $0 }
            if let limit = height ?? maxHeight {
                ScrollView {
                    rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                }
                .scrollEdgeEffectHidden(true, for: .vertical)
                .scrollBounceBehavior(.basedOnSize)
                .clipped()
                .frame(height: height == nil ? min(rowsHeight ?? .infinity, max(limit - chromeHeight.reduce(0, +), 0)) : nil)
            } else {
                rows.fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Spacing.small) { footer }
                .padding(.horizontal, Theme.DeckOptions.margin)
                .padding(.vertical, Theme.Spacing.medium)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight[1] = $0 }
        }
        .frame(width: width, height: height)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Theme.DeckOptions.sectionGap) { content }
            .padding(.horizontal, Theme.DeckOptions.margin)
            .padding(.top, Theme.Spacing.small)
            .padding(.bottom, Theme.Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A sheet's Headline at its top margins, under an eyebrow when the sheet
/// belongs to a deck; shared with the sheets that size themselves.
struct SheetHeader: View {
    var eyebrow = ""
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
            if !eyebrow.isEmpty {
                Eyebrow(eyebrow).lineLimit(1).truncationMode(.head)
            }
            Text(title)
                .font(Theme.Fonts.panelTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Theme.DeckOptions.margin)
        .padding(.top, Theme.DeckOptions.margin)
        .padding(.bottom, Theme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A choice as a quiet menu: the chosen one in Ink and a chevron.
struct OptionPicker<Value: Hashable>: View {
    @Environment(\.optionTitle) private var title
    @Binding var selection: Value
    let choices: [(Value, String)]
    var disabled: [Value] = []

    var body: some View {
        let chosen = choices.first { $0.0 == selection }?.1 ?? ""
        Menu {
            Picker(title, selection: $selection) {
                ForEach(choices, id: \.0) { value, label in
                    Text(label).tag(value).selectionDisabled(disabled.contains(value))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            QuietMenuLabel(value: chosen)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // The hover wash's room hangs past the edge, so the chevron ends
        // where a field or a switch does.
        .padding(.trailing, -Theme.Layout.menuPadding)
        .accessibilityLabel(title)
        .accessibilityValue(chosen)
    }
}

enum WarningLevel {
    case info, warning, danger

    var color: Color {
        switch self {
        case .info: Theme.DeckOptions.infoColor
        case .warning: Theme.DeckOptions.warningColor
        case .danger: Theme.DeckOptions.dangerColor
        }
    }

    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .warning, .danger: "exclamationmark.triangle.fill"
        }
    }
}

/// Desktop's coloured alerts under a setting, as a caption: the icon in
/// the alert's colour, the words in Pencil.
struct OptionWarning: View {
    let text: String
    var level = WarningLevel.warning
    /// An error's own words, a server's or the backend's, aren't Markdown.
    var verbatim = false

    var body: some View {
        if !text.isEmpty {
            Label {
                Text(verbatim ? AttributedString(text) : markdown(text)).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: level.symbol).foregroundStyle(level.color)
            }
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Palette.secondary)
            .optionNote()
        }
    }
}

/// A setting's actions, as chips under it.
struct OptionActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ActionRow { content }
            .optionNote()
    }
}

/// Section name as an eyebrow, with a help button listing what each
/// setting does, as desktop's help modal.
struct OptionSectionHeader: View {
    let title: String
    let help: [(title: String, text: String)]
    @State private var showingHelp = false

    var body: some View {
        HStack {
            Eyebrow(title)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if !help.isEmpty {
                Button {
                    showingHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(Theme.DeckOptions.helpSymbol)
                        .frame(width: Theme.DeckOptions.helpSize.width, height: Theme.DeckOptions.helpSize.height)
                        .accessibilityLabel(Tr.actionsHelp)
                }
                .buttonStyle(QuietButtonStyle(inset: 0))
                .help(Tr.actionsHelp)
                .popover(isPresented: $showingHelp, arrowEdge: .trailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                            ForEach(Array(help.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                                    Text(item.title).font(Theme.Fonts.listRow)
                                    Text(markdown(item.text))
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Palette.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(Theme.Spacing.large)
                    }
                    .frame(width: Theme.DeckOptions.helpWidth)
                    .frame(maxHeight: Theme.DeckOptions.helpMaxHeight)
                }
            }
        }
        // As tall with a help button as without one.
        .frame(height: Theme.DeckOptions.helpSize.height)
    }
}

/// Desktop writes its help in Markdown: `code` for option names, and lists.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(
        markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

/// Desktop's help without its Markdown, for VoiceOver.
func plainText(_ text: String) -> String {
    String(markdown(text).characters)
}
