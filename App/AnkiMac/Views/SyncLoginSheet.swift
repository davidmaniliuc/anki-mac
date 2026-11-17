import SwiftUI

/// Desktop's AnkiWeb sign-in, drawn as the study prompts: upstream's
/// "Account Required" as the Headline with its sentence and sign-up link
/// under it, Email and Password as rows with quiet boxes, and at the foot
/// a spinner while it signs in or why it couldn't, beside Cancel and Sign in.
struct SyncLoginSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var signingIn = false
    @State private var failure: String?
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        let intro = Self.intro
        SettingsSheet(title: intro.title, width: Theme.SyncLogin.width) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                Text(intro.body)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                OptionSection {
                    OptionRow(title: rowTitle(Tr.syncAnkiwebIdLabel), revertible: false) {
                        // The row names the box, so it holds no placeholder.
                        TextField(rowTitle(Tr.syncAnkiwebIdLabel), text: $username, prompt: Text(""))
                            .textContentType(.username)
                            .focused($focus, equals: .username)
                            .onSubmit { focus = .password }
                            .quietLoginField(focused: focus == .username)
                    }
                    OptionRow(title: rowTitle(Tr.syncPasswordLabel), revertible: false) {
                        SecureField(rowTitle(Tr.syncPasswordLabel), text: $password, prompt: Text(""))
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .onSubmit(submit)
                            .quietLoginField(focused: focus == .password)
                    }
                }
                .disabled(signingIn)
            }
        } footer: {
            if signingIn {
                ProgressView().controlSize(.small).accessibilityLabel(Tr.actionsProcessing)
            } else if let failure {
                OptionWarning(text: failure, level: .danger, verbatim: true).lineLimit(3)
            }
            Spacer(minLength: Theme.Spacing.small)
            DialogButtons(
                action: Tr.syncSignIn, disabled: !canSubmit, cancelDisabled: signingIn,
                cancel: { dismiss() }, submit: submit)
        }
        .onAppear {
            username = model.syncUsername
            focus = username.isEmpty ? .username : .password
        }
        // A failure is about what was typed; changing it clears the failure.
        .onChange(of: username) { failure = nil }
        .onChange(of: password) { failure = nil }
        // The boxes are off while it signs in, which takes the focus from
        // them; a failure hands it back to the password, and VoiceOver
        // hears what the foot shows.
        .onChange(of: signingIn) { _, signingIn in
            if signingIn {
                AccessibilityNotification.Announcement(Tr.actionsProcessing).post()
            } else if let failure {
                focus = .password
                AccessibilityNotification.Announcement(failure).post()
            }
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !signingIn
    }

    private func submit() {
        guard canSubmit else { return }
        signingIn = true
        Task {
            failure = await model.login(username: username, password: password)
            signingIn = false
        }
    }

    /// Upstream's sentence is HTML: an `<h1>` title, then text with a
    /// sign-up link, which becomes a Markdown link in the accent.
    private static var intro: (title: String, body: AttributedString) {
        let html = Tr.syncAccountRequired(link: "https://ankiweb.net/account/register")
        let title = html.firstMatch(of: /<h1>(.*?)<\/h1>/)?.output.1 ?? ""
        let text = html.replacing(/<h1>.*?<\/h1>/, with: "")
            .replacing(/<a href="([^"]*)">(.*?)<\/a>/) { "[\($0.output.2)](\($0.output.1))" }
            .replacing(/<[^>]+>/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (String(title), markdown(text))
    }
}

private extension View {
    func quietLoginField(focused: Bool) -> some View {
        labelsHidden()
            .font(Theme.DeckOptions.rowFont)
            .quietField(focused: focused)
            .frame(width: Theme.SyncLogin.fieldWidth)
    }
}
