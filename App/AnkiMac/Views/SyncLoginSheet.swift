import SwiftUI

struct SyncLoginSheet: View {
    @Environment(CollectionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Account Required").font(.headline)
                Text("A free account is required to keep your collection synchronized. Please sign up for an account, then enter your details below.")
                Link("Sign Up for an Account", destination: URL(string: "https://ankiweb.net/account/register")!)
            }
            .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(Tr.syncAnkiwebIdLabel, text: $username)
                    .textContentType(.username)
                SecureField(Tr.syncPasswordLabel, text: $password)
                    .textContentType(.password)
                    .onSubmit(submit)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(Tr.syncSignIn) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
        .onAppear { username = model.syncUsername }
    }

    private func submit() {
        Task { await model.login(username: username, password: password) }
    }
}
