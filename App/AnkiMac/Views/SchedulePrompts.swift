import SwiftUI

// Set Due Date, Reset and Reposition, as the study screen and the Browser
// both ask them: sheets drawn as Deck Options' settings in desktop's words,
// their title as a Headline, their rows under hairlines, then Cancel and
// the action. A failure shows beside the buttons until the answer changes.

/// What a prompt's form needs from the window asking it.
struct SchedulePromptContext {
    /// The cards the answer acts on, for the title's plural.
    var cards = 1
    let error: String?
    let cancel: () -> Void
    /// The answer changed, so the last failure no longer applies.
    let edited: () -> Void
}

/// A prompt's sheet, as tall as its rows.
private struct SchedulePrompt<Content: View>: View {
    let title: String
    let action: String
    var canSubmit = true
    /// What's been answered; a change clears the failure.
    let answer: [AnyHashable]
    let context: SchedulePromptContext
    let submit: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        SettingsSheet(title: title, width: Theme.StudyPrompt.width) {
            content
        } footer: {
            if let error = context.error {
                OptionWarning(text: error, level: .danger).lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(action: action, disabled: !canSubmit, cancel: context.cancel, submit: submit)
        }
        .onChange(of: answer) { context.edited() }
    }
}

struct SetDueDatePrompt: View {
    let context: SchedulePromptContext
    let submit: (String) -> Void
    @State private var days: String

    init(days: String, context: SchedulePromptContext, submit: @escaping (String) -> Void) {
        self.context = context
        self.submit = submit
        _days = State(initialValue: days)
    }

    var body: some View {
        let title = Tr.schedulingSetDueDatePrompt(cards: context.cards)
        SchedulePrompt(
            title: title, action: Tr.actionsSetDueDate,
            canSubmit: !days.trimmingCharacters(in: .whitespaces).isEmpty, answer: [days], context: context,
            submit: { submit(days) }
        ) {
            // A row under a hairline, as the other prompts' rows are.
            OptionSection {
                OptionTextField(text: $days, prompt: "0", font: Theme.DeckOptions.figures, focusOnAppear: true)
                    .environment(\.optionTitle, title)
                    .frame(width: Theme.StudyPrompt.daysFieldWidth)
                DueDateHint().optionNote()
            }
        }
    }
}

/// Upstream's examples, "0 = today" and so on, as a small table: what to
/// type in rounded figures, what it does in Pencil.
private struct DueDateHint: View {
    private static let example = /(\S+) = (.+?)(?=\s\S+ = |$)/

    var body: some View {
        let lines = Tr.schedulingSetDueDatePromptHint.matches(of: Self.example).map { (String($0.1), String($0.2)) }
        Group {
            if lines.count > 1 {
                Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.small, verticalSpacing: Theme.Spacing.xxSmall) {
                    ForEach(lines.indices, id: \.self) { index in
                        GridRow {
                            Text(lines[index].0)
                                .font(Theme.StudyPrompt.hintFigures)
                                .foregroundStyle(Theme.Palette.text)
                                .gridColumnAlignment(.trailing)
                            Text(lines[index].1)
                        }
                    }
                }
            } else {
                Text(Tr.schedulingSetDueDatePromptHint)
            }
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(Theme.Palette.secondary)
        .accessibilityElement(children: .combine)
    }
}

struct ResetCardPrompt: View {
    let context: SchedulePromptContext
    let submit: (_ restorePosition: Bool, _ resetCounts: Bool) -> Void
    @State private var restorePosition: Bool
    @State private var resetCounts: Bool

    init(
        restorePosition: Bool, resetCounts: Bool, context: SchedulePromptContext,
        submit: @escaping (Bool, Bool) -> Void
    ) {
        self.context = context
        self.submit = submit
        _restorePosition = State(initialValue: restorePosition)
        _resetCounts = State(initialValue: resetCounts)
    }

    var body: some View {
        SchedulePrompt(
            title: Tr.actionsForgetCard, action: Tr.actionsForgetCard, answer: [restorePosition, resetCounts],
            context: context, submit: { submit(restorePosition, resetCounts) }
        ) {
            OptionSection {
                switchRow(Tr.schedulingRestorePosition, $restorePosition)
                switchRow(Tr.schedulingResetCounts, $resetCounts)
            }
        }
    }
}

struct RepositionPrompt: View {
    let queueTop: Int
    let queueBottom: Int
    let context: SchedulePromptContext
    let submit: (_ start: Int, _ step: Int, _ randomize: Bool, _ shift: Bool) -> Void
    @State private var start = 0
    @State private var step = 1
    @State private var randomize: Bool
    @State private var shift: Bool

    init(
        queueTop: Int, queueBottom: Int, randomize: Bool, shift: Bool, context: SchedulePromptContext,
        submit: @escaping (Int, Int, Bool, Bool) -> Void
    ) {
        self.queueTop = queueTop
        self.queueBottom = queueBottom
        self.context = context
        self.submit = submit
        _randomize = State(initialValue: randomize)
        _shift = State(initialValue: shift)
    }

    var body: some View {
        SchedulePrompt(
            title: Tr.browsingRepositionNewCards, action: Tr.actionsReposition,
            answer: [start, step, randomize, shift], context: context,
            submit: { submit(start, step, randomize, shift) }
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                // Where the new cards sit now, as desktop's two lines.
                Text("\(Tr.browsingQueueTop(val: String(queueTop)))  \u{00B7}  \(Tr.browsingQueueBottom(val: String(queueBottom)))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                OptionSection {
                    OptionRow(title: label(Tr.browsingStartPosition), revertible: false) {
                        NumberField(
                            value: Binding { Double(start) } set: { start = Int($0) }, range: 0...Double(Int32.max),
                            focusOnAppear: true)
                    }
                    OptionRow(title: label(Tr.browsingStep), revertible: false) {
                        NumberField(value: Binding { Double(step) } set: { step = Int($0) }, range: 1...Double(Int32.max))
                    }
                    switchRow(Tr.browsingRandomizeOrder, $randomize)
                    switchRow(Tr.browsingShiftPositionOfExistingCards, $shift)
                }
            }
        }
    }
}

private func switchRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
    OptionRow(title: title, revertible: false) {
        SwitchControl(title: title, isOn: isOn)
    }
}

/// "Start position:" as a row's title.
private func label(_ text: String) -> String {
    text.hasSuffix(":") ? String(text.dropLast()) : text
}
