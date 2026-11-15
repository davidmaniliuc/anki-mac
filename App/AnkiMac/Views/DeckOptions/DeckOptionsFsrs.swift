import AnkiKit
import SwiftUI

/// The FSRS section: the switch, desired retention, the parameters and the
/// optimizer, as desktop's FsrsOptionsOuter and FsrsOptions.
struct FsrsSection: View {
    @Bindable var model: DeckOptionsModel
    let actions: DeckOptionsActions
    /// FSRS was off at some point since the window opened: desktop then
    /// explains what the retention means for the workload.
    @State private var newlyEnabled = false
    @State private var workloadNote = ""
    @State private var editingParams = false
    @State private var message: String?
    @State private var confirmingOptimizeAll = false
    @State private var simulator: FsrsSimulator?
    /// The simulator reads the saved parameters, so it waits for a save
    /// after they change.
    @State private var initialParams: [Float]?

    private var help: [(String, String)] {
        [
            ("FSRS", Tr.deckConfigFsrsTooltip),
            (Tr.deckConfigDesiredRetention,
             Tr.deckConfigDesiredRetentionTooltip + "\n\n" + Tr.deckConfigDesiredRetentionTooltip2),
            (Tr.deckConfigWeights, Tr.deckConfigWeightsTooltip2 + "\n\n" + Tr.deckConfigComputeOptimalWeightsTooltip2),
            (Tr.deckConfigRescheduleCardsOnChange, Tr.deckConfigRescheduleCardsOnChangeTooltip),
            (Tr.deckConfigHealthCheck,
             Tr.deckConfigAffectsEntireCollection + "\n\n" + Tr.deckConfigHealthCheckTooltip1 + "\n\n"
                + Tr.deckConfigHealthCheckTooltip2),
        ]
    }

    var body: some View {
        OptionSection(title: "FSRS", help: help) {
            GlobalToggleRow(title: "FSRS", help: help[0].1, isOn: $model.fsrs)
            if model.fsrs {
                retention
                parameters
                optimizer
            }
        }
        .onChange(of: model.fsrs, initial: true) { _, enabled in
            if !enabled { newlyEnabled = true }
        }
        .onAppear { if initialParams == nil { initialParams = model.config.fsrsParams } }
        .sheet(item: $simulator) { simulator in
            FsrsSimulatorView(simulator: simulator) { self.simulator = nil }
        }
        .alert(
            message ?? "", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }
        ) {
            Button("OK") {}
        }
    }

    // MARK: Desired retention

    @ViewBuilder private var retention: some View {
        let value = model.value(.retention)
        let percent = (value * 100).rounded() / 100
        TabbedLimitRow(
            model: model, limit: .retention, title: help[1].0, help: help[1].1,
            defaultValue: Double(model.defaults.desiredRetention), range: 0.7...0.99, step: 0.01, decimals: 0,
            percent: true)
        let showNote = newlyEnabled || model.optimizedParams || abs(value - model.startingRetention) >= 0.005
        OptionActions {
            Button(Tr.deckConfigFsrsDesiredRetentionHelpMeDecideExperimental + "…") { openSimulator(workload: true) }
        }
        .task(id: WorkloadKey(retention: percent, params: model.config.fsrsParams, shown: showNote)) {
            guard showNote else { return }
            workloadNote = await model.workloadNote(retention: percent)
        }
        if showNote && !workloadNote.isEmpty {
            OptionWarning(text: workloadNote, level: .info)
        }
        if percent < 0.8 {
            OptionWarning(text: Tr.deckConfigDesiredRetentionTooLow, level: percent < 0.7 ? .danger : .warning)
        } else if percent > 0.95 {
            OptionWarning(text: Tr.deckConfigDesiredRetentionTooHigh, level: percent > 0.97 ? .danger : .warning)
        }
    }

    private struct WorkloadKey: Equatable {
        let retention: Double
        let params: [Float]
        let shown: Bool
    }

    // MARK: Parameters

    @ViewBuilder private var parameters: some View {
        let params = model.config.fsrsParams6
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text(help[2].0).font(Theme.DeckOptions.rowFont).help(help[2].1)
                Spacer()
                Button(editingParams ? "Done" : "Edit…") { editingParams.toggle() }
                    .font(Theme.Fonts.chip)
                    .frame(height: Theme.DeckOptions.fieldHeight)
                    .buttonStyle(QuietButtonStyle())
                    .help("Edit the parameters by hand")
            }
            if editingParams {
                CommitField(text: Self.format(params), prompt: Tr.deckConfigPlaceholderParameters) { text in
                    setParams(text)
                }
                OptionWarning(text: Tr.deckConfigManualParameterEditWarning)
            } else {
                Text(params.isEmpty ? Tr.deckConfigPlaceholderParameters : Self.format(params))
                    .font(Theme.DeckOptions.figures)
                    .foregroundStyle(Theme.Palette.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        OptionRow(title: "Search", help: "The cards FSRS optimizes from") {
            OptionTextField(text: $model.config.paramSearch, prompt: model.presetSearch)
                .frame(width: Theme.DeckOptions.searchFieldWidth)
        }
        GlobalToggleRow(title: help[3].0, help: help[3].1, isOn: $model.fsrsReschedule)
        if model.fsrsReschedule {
            OptionWarning(text: Tr.deckConfigRescheduleCardsWarning)
        }
        GlobalToggleRow(
            title: Tr.deckConfigSlowSuffix(text: help[4].0), help: help[4].1, isOn: $model.fsrsHealthCheck)
    }

    private static func format(_ params: [Float]) -> String {
        params.map { String(format: "%.4f", $0) }.joined(separator: ", ")
    }

    /// Desktop accepts no parameters (the defaults) or a full set.
    private func setParams(_ text: String) {
        let values = text.replacing(" ", with: "").split(separator: ",").compactMap { Float($0) }
        let pieces = text.replacing(" ", with: "").split(separator: ",").count
        guard values.count == pieces, [0, 17, 19, 21].contains(values.count) else {
            message = Tr.deckConfigInvalidParameters
            return
        }
        model.config.fsrsParams6 = values
    }

    // MARK: Optimizer

    @ViewBuilder private var optimizer: some View {
        let job = model.fsrsJob
        HStack {
            ActionRow {
                Button(job == .optimizing ? Tr.actionsCancel : Tr.deckConfigOptimizeButton) {
                    job == .optimizing ? model.cancelFsrsJob() : run(failing: "Couldn’t optimize the FSRS parameters", model.optimize)
                }
                .disabled(job != nil && job != .optimizing)
                if model.legacyEvaluate {
                    Button(job == .evaluating ? Tr.actionsCancel : Tr.deckConfigEvaluateButton) {
                        job == .evaluating ? model.cancelFsrsJob() : run(failing: "Couldn’t evaluate the FSRS parameters", model.evaluate)
                    }
                    .disabled(job != nil && job != .evaluating)
                }
            }
            Spacer()
            if job != nil {
                ProgressView().controlSize(.small)
            }
        }
        if job != nil {
            if let progress = model.fsrsProgress, progress.total > 0 {
                ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                    Text(model.progressText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .tint(Theme.DeckOptions.controlTint)
                .optionNote()
            }
        } else if let reviews = model.lastReviewCount {
            Text(Tr.statisticsReviews(reviews: Int(reviews)))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .optionNote()
        }
        if model.daysSinceLastOptimization > 30 {
            OptionWarning(text: Tr.deckConfigTimeToOptimize)
        }
        ActionRow {
            Button(job == .optimizingAll ? Tr.actionsCancel : Tr.deckConfigSaveAndOptimize + "…") {
                if job == .optimizingAll { model.cancelFsrsJob() } else { confirmingOptimizeAll = true }
            }
            .disabled(job != nil && job != .optimizingAll)
            .help(Tr.deckConfigOptimizeAllTip)
            Button(Tr.deckConfigFsrsSimulatorExperimental + "…") { openSimulator(workload: false) }
        }
        .alert(Tr.deckConfigFsrsConfirmSaveAndOptimize, isPresented: $confirmingOptimizeAll) {
            Button("Cancel", role: .cancel) {}
            Button(Tr.deckConfigSaveAndOptimize) { optimizeAll() }
        }
    }

    private func openSimulator(workload: Bool) {
        guard model.config.fsrsParams == initialParams else {
            message = Tr.deckConfigFsrsSimulateSavePreset
            return
        }
        simulator = FsrsSimulator(options: model, workload: workload)
    }

    private func run(failing title: String, _ job: @escaping () async throws -> String?) {
        if model.presetAssignmentsChanged {
            message = Tr.deckConfigPleaseSaveYourChangesFirst
            return
        }
        Task {
            do {
                message = try await job()
            } catch {
                actions.showError(ActionFailure(title, error: error))
            }
        }
    }

    private func optimizeAll() {
        Task {
            do {
                if try await model.saveAndOptimizeAll() { actions.close() }
            } catch {
                actions.showError(ActionFailure("Couldn’t optimize all presets", error: error))
            }
        }
    }
}
