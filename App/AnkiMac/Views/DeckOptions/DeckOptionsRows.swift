import SwiftUI

/// One setting: its title, with the explanation as a help tag, the control,
/// and, once the value differs from the default, a menu that restores it
/// (desktop's revert badge).
struct OptionRow<Control: View>: View {
    let title: String
    var help = ""
    var isDefault = true
    var revert: (() -> Void)? = nil
    @ViewBuilder let control: Control
    @Namespace private var pair

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.xSmall) {
                control.accessibilityLabeledPair(role: .content, id: 0, in: pair)
                RevertMenu(hidden: isDefault, revert: revert)
            }
        } label: {
            Text(title).help(help).accessibilityLabeledPair(role: .label, id: 0, in: pair)
        }
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
            Image(systemName: "arrow.uturn.backward.circle")
                .accessibilityLabel("Restore Default")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Restore Default")
        .opacity(hidden || revert == nil ? 0 : 1)
        .disabled(hidden || revert == nil)
        .accessibilityHidden(hidden || revert == nil)
    }
}

/// A number typed or stepped, clamped to its range. Percentages are stored
/// as fractions and shown out of 100.
struct NumberField: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...9999
    var step: Double = 1
    var decimals = 0
    var percent = false

    var body: some View {
        let scale = percent ? 100.0 : 1.0
        HStack(spacing: Theme.Spacing.xSmall) {
            TextField(
                value: Binding { value * scale } set: { value = clamp($0 / scale) },
                format: .number.precision(.fractionLength(decimals)).grouping(.never)
            ) {}
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: Theme.DeckOptions.numberFieldWidth)
            if percent { Text("%").foregroundStyle(.secondary) }
            Stepper("", value: Binding { value } set: { value = clamp(rounded($0)) }, in: range, step: step)
                .labelsHidden()
        }
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
    let text: String
    var prompt = ""
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { commit(draft) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit(draft) }
            }
            .onChange(of: text, initial: true) { _, text in
                if !focused { draft = text }
            }
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
        case .warning, .danger: "exclamationmark.triangle"
        }
    }
}

/// Desktop's coloured alerts under a setting, as a callout line.
struct OptionWarning: View {
    let text: String
    var level = WarningLevel.warning

    var body: some View {
        if !text.isEmpty {
            Label {
                Text(markdown(text)).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: level.symbol).foregroundStyle(level.color)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

/// Section title with a help button listing what each setting does, as
/// desktop's help modal.
struct OptionSectionHeader: View {
    let title: String
    let help: [(title: String, text: String)]
    @State private var showingHelp = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if !help.isEmpty {
                Button {
                    showingHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .accessibilityLabel("Help for \(title)")
                }
                .buttonStyle(.borderless)
                .help("Help for \(title)")
                .popover(isPresented: $showingHelp, arrowEdge: .trailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                            ForEach(Array(help.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
                                    Text(item.title).font(.headline)
                                    Text(markdown(item.text))
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
    }
}

/// Desktop writes its help in Markdown: `code` for option names, and lists.
func markdown(_ text: String) -> AttributedString {
    (try? AttributedString(
        markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}
