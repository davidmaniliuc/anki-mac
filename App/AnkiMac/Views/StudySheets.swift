import SwiftUI

/// The sheet for the study screen's `StudySession.Prompt`, in the browser's
/// prompt layout with the same wording.
struct StudyPromptSheet: View {
    let prompt: StudySession.Prompt
    let session: StudySession

    var body: some View {
        switch prompt {
        case .setDueDate(let days):
            DueDateForm(session: session, days: days)
        case .forget(let restorePosition, let resetCounts):
            ForgetForm(session: session, restorePosition: restorePosition, resetCounts: resetCounts)
        case .reposition(let top, let bottom, let randomize, let shift):
            RepositionForm(session: session, queueTop: top, queueBottom: bottom, randomize: randomize, shift: shift)
        }
    }
}

private struct DueDateForm: View {
    let session: StudySession
    @State var days: String
    @FocusState private var focused: Bool

    init(session: StudySession, days: String) {
        self.session = session
        _days = State(initialValue: days)
    }

    var body: some View {
        PromptLayout(
            title: "Show the card in how many days?", action: Tr.actionsSetDueDate,
            canSubmit: !days.trimmingCharacters(in: .whitespaces).isEmpty,
            cancel: { session.prompt = nil }, submit: { session.setDueDate(days: days) }
        ) {
            TextField("Days", text: $days, prompt: Text("0"))
                .labelsHidden()
                .focused($focused)
                .onAppear { focused = true }
            Text("0 = today\n1! = tomorrow + change interval to 1\n3-7 = random choice of 3-7 days")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ForgetForm: View {
    let session: StudySession
    @State var restorePosition: Bool
    @State var resetCounts: Bool

    init(session: StudySession, restorePosition: Bool, resetCounts: Bool) {
        self.session = session
        _restorePosition = State(initialValue: restorePosition)
        _resetCounts = State(initialValue: resetCounts)
    }

    var body: some View {
        PromptLayout(
            title: "Reset 1 card to new?", action: "Reset", cancel: { session.prompt = nil },
            submit: { session.forget(restorePosition: restorePosition, resetCounts: resetCounts) }
        ) {
            Toggle("Restore original position where possible", isOn: $restorePosition)
            Toggle("Reset repetition and lapse counts", isOn: $resetCounts)
        }
    }
}

private struct RepositionForm: View {
    let session: StudySession
    let queueTop: Int
    let queueBottom: Int
    @State var start = 0
    @State var step = 1
    @State var randomize: Bool
    @State var shift: Bool
    @FocusState private var focused: Bool

    init(session: StudySession, queueTop: Int, queueBottom: Int, randomize: Bool, shift: Bool) {
        self.session = session
        self.queueTop = queueTop
        self.queueBottom = queueBottom
        _randomize = State(initialValue: randomize)
        _shift = State(initialValue: shift)
    }

    var body: some View {
        PromptLayout(
            title: "Reposition 1 card", action: Tr.actionsReposition, cancel: { session.prompt = nil },
            submit: { session.reposition(start: start, step: step, randomize: randomize, shift: shift) }
        ) {
            Text("The new queue runs from \(queueTop) to \(queueBottom).")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                TextField("Start position:", value: $start, format: .number)
                    .focused($focused)
                    .onAppear { focused = true }
                TextField("Step:", value: $step, format: .number)
                Toggle("Randomize order", isOn: $randomize)
                Toggle("Shift position of existing cards", isOn: $shift)
            }
            .formStyle(.columns)
        }
    }
}

/// The current note in the editor. Save (Command-Return) writes it and shows
/// the card again; Cancel (Escape) leaves it alone.
struct StudyEditSheet: View {
    @Bindable var model: StudyEditModel
    let session: StudySession

    var body: some View {
        VStack(spacing: 0) {
            NoteEditorView(editor: model.editor)
            Divider()
            TagField(tags: $model.tags, complete: model.completeTags)
                .padding(Theme.Spacing.medium)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { session.finishEditing(save: false) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { session.finishEditing(save: true) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(Theme.Spacing.medium)
        }
        .frame(width: Theme.Study.editorWidth, height: Theme.Study.editorHeight)
    }
}
