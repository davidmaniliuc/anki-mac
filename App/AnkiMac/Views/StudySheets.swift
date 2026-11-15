import SwiftUI

/// The sheet for the study screen's `StudySession.Prompt`, asked about the
/// card on screen (see SchedulePrompts).
struct StudyPromptSheet: View {
    let prompt: StudySession.Prompt
    let session: StudySession

    var body: some View {
        let context = SchedulePromptContext(
            error: session.promptError, cancel: { session.prompt = nil }, edited: { session.promptError = nil })
        switch prompt {
        case .setDueDate(let days):
            SetDueDatePrompt(days: days, context: context) { session.setDueDate(days: $0) }
        case .forget(let restorePosition, let resetCounts):
            ResetCardPrompt(restorePosition: restorePosition, resetCounts: resetCounts, context: context) {
                session.forget(restorePosition: $0, resetCounts: $1)
            }
        case .reposition(let top, let bottom, let randomize, let shift):
            RepositionPrompt(queueTop: top, queueBottom: bottom, randomize: randomize, shift: shift, context: context) {
                session.reposition(start: $0, step: $1, randomize: $2, shift: $3)
            }
        }
    }
}

/// The current note in the editor. Save (Command-Return) writes it and shows
/// the card again; Cancel (Escape) leaves it alone.
struct StudyEditSheet: View {
    @Bindable var model: StudyEditModel
    let session: StudySession
    @Environment(CollectionModel.self) private var collection

    var body: some View {
        // As Add's window: the editor on the canvas, a hairline, the tags,
        // then the dialog's buttons with no hairline over them.
        VStack(spacing: 0) {
            NoteEditorView(editor: model.editor) {
                CardTemplatesWindowController.show(
                    collection: collection, note: model.currentNote,
                    ord: Int(session.card?.queued.card.templateIdx ?? 0))
            }
            Theme.Palette.hairline.frame(height: 1)
            TagRow(tags: $model.tags, complete: model.completeTags)
                .padding(Theme.Spacing.medium)
            HStack {
                Spacer()
                // Return starts a new line in a field, so Save takes Command-Return.
                DialogButtons(
                    action: Tr.actionsSave, key: "\u{2318}\u{21A9}",
                    shortcut: KeyboardShortcut(.return, modifiers: .command),
                    cancel: { session.finishEditing(save: false) }, submit: { session.finishEditing(save: true) })
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.bottom, Theme.Spacing.medium)
        }
        .frame(width: Theme.Study.editorWidth, height: Theme.Study.editorHeight)
        .background(Theme.Palette.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
    }
}
