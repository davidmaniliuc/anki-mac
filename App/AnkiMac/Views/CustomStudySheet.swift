import SwiftUI

/// Desktop's Custom Study dialog as a sheet on the main window, with its
/// Selective Study tag lists folded in under "Study by card state or tag".
struct CustomStudySheet: View {
    @Bindable var study: CustomStudyModel
    let cancel: () -> Void
    let done: (Int64) -> Void
    @FocusState private var valueFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(Tr.actionsCustomStudy, selection: $study.option) {
                        ForEach(CustomStudyModel.Option.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Section {
                    LabeledContent(study.valueLabels.before) {
                        HStack(spacing: Theme.Spacing.xSmall) {
                            TextField(study.valueLabels.before, value: $study.value, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: Theme.CustomStudy.valueWidth)
                                .focused($valueFocused)
                            Stepper(study.valueLabels.before, value: $study.value, in: study.option.range)
                                .labelsHidden()
                            Text(study.valueLabels.after).foregroundStyle(.secondary)
                        }
                    }
                    if study.option == .cram {
                        Picker(Tr.customStudyStudyByCardStateOrTag, selection: $study.cramKind) {
                            ForEach(CustomStudyModel.CramKind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                } footer: {
                    if let available = study.available {
                        Text(available).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if study.option == .cram, !study.tags.isEmpty {
                    tagSection
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(isLimit ? "Apply" : "Study") {
                    Task { if let deckID = await study.run() { done(deckID) } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!study.canRun)
            }
            .padding(Theme.Spacing.large)
        }
        .frame(width: Theme.CustomStudy.sheetWidth, height: Theme.CustomStudy.sheetHeight)
        .onAppear { valueFocused = true }
        .alert(
            study.error ?? "", isPresented: Binding { study.error != nil } set: { if !$0 { study.error = nil } }
        ) {
            Button("OK") {}
        }
    }

    private var isLimit: Bool {
        study.option == .newLimit || study.option == .reviewLimit
    }

    /// Desktop's Selective Study window: tags a card must have one of, and
    /// tags it must not have.
    private var tagSection: some View {
        Section {
            Toggle(sentence(Tr.customStudyRequireOneOrMoreOfThese), isOn: $study.requireTags)
            ForEach($study.tags) { $tag in
                LabeledContent(tag.name.replacingOccurrences(of: "_", with: " ")) {
                    HStack(spacing: Theme.Spacing.large) {
                        Toggle("Require", isOn: $tag.include)
                            .disabled(!study.requireTags)
                        Toggle("Exclude", isOn: $tag.exclude)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } header: {
            Text(Tr.customStudySelectiveStudy)
        }
    }

    /// "Require one or more of these tags:" as a label.
    private func sentence(_ text: String) -> String {
        text.hasSuffix(":") ? String(text.dropLast()) : text
    }
}
