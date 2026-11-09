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
        Section {
            GlobalToggleRow(title: "FSRS", help: help[0].1, isOn: $model.fsrs)
            if model.fsrs {
                retention
                parameters
                optimizer
            }
        } header: {
            OptionSectionHeader(title: "FSRS", help: help)
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
        HStack {
            Button(Tr.deckConfigFsrsDesiredRetentionHelpMeDecideExperimental + "…") { openSimulator(workload: true) }
            Spacer()
        }
        let showNote = newlyEnabled || model.optimizedParams || abs(value - model.startingRetention) >= 0.005
        if showNote && !workloadNote.isEmpty {
            OptionWarning(text: workloadNote, level: .info)
        }
        if percent < 0.8 {
            OptionWarning(text: Tr.deckConfigDesiredRetentionTooLow, level: percent < 0.7 ? .danger : .warning)
        } else if percent > 0.95 {
            OptionWarning(text: Tr.deckConfigDesiredRetentionTooHigh, level: percent > 0.97 ? .danger : .warning)
        }
        Color.clear.frame(height: 0)
            .task(id: WorkloadKey(retention: percent, params: model.config.fsrsParams, shown: showNote)) {
                guard showNote else { return }
                workloadNote = await model.workloadNote(retention: percent)
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
                Text(help[2].0).help(help[2].1)
                Spacer()
                Button(editingParams ? "Done" : "Edit…") { editingParams.toggle() }
                    .buttonStyle(.borderless)
                    .help("Edit the parameters by hand")
            }
            if editingParams {
                CommitField(text: Self.format(params), prompt: Tr.deckConfigPlaceholderParameters) { text in
                    setParams(text)
                }
                OptionWarning(text: Tr.deckConfigManualParameterEditWarning)
            } else {
                Text(params.isEmpty ? Tr.deckConfigPlaceholderParameters : Self.format(params))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        OptionRow(title: "Search", help: "The cards FSRS optimizes from") {
            TextField("Search", text: $model.config.paramSearch, prompt: Text(model.presetSearch))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
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
            Button(job == .optimizing ? Tr.actionsCancel : Tr.deckConfigOptimizeButton) {
                job == .optimizing ? model.cancelFsrsJob() : run(model.optimize)
            }
            .disabled(job != nil && job != .optimizing)
            if model.legacyEvaluate {
                Button(job == .evaluating ? Tr.actionsCancel : Tr.deckConfigEvaluateButton) {
                    job == .evaluating ? model.cancelFsrsJob() : run(model.evaluate)
                }
                .disabled(job != nil && job != .evaluating)
            }
            Spacer()
            if job != nil {
                ProgressView().controlSize(.small)
            }
        }
        if job != nil {
            if let progress = model.fsrsProgress, progress.total > 0 {
                ProgressView(value: Double(progress.current), total: Double(progress.total)) {
                    Text(model.progressText).font(.callout)
                }
            }
        } else if let reviews = model.lastReviewCount {
            Text(Tr.statisticsReviews(reviews: Int(reviews))).font(.callout).foregroundStyle(.secondary)
        }
        if model.daysSinceLastOptimization > 30 {
            OptionWarning(text: Tr.deckConfigTimeToOptimize)
        }
        HStack {
            Button(job == .optimizingAll ? Tr.actionsCancel : Tr.deckConfigSaveAndOptimize + "…") {
                if job == .optimizingAll { model.cancelFsrsJob() } else { confirmingOptimizeAll = true }
            }
            .disabled(job != nil && job != .optimizingAll)
            .help(Tr.deckConfigOptimizeAllTip)
            Spacer()
        }
        .alert(Tr.deckConfigFsrsConfirmSaveAndOptimize, isPresented: $confirmingOptimizeAll) {
            Button("Cancel", role: .cancel) {}
            Button(Tr.deckConfigSaveAndOptimize) { optimizeAll() }
        }
        HStack {
            Button(Tr.deckConfigFsrsSimulatorExperimental + "…") { openSimulator(workload: false) }
            Spacer()
        }
    }

    private func openSimulator(workload: Bool) {
        guard model.config.fsrsParams == initialParams else {
            message = Tr.deckConfigFsrsSimulateSavePreset
            return
        }
        simulator = FsrsSimulator(options: model, workload: workload)
    }

    private func run(_ job: @escaping () async throws -> String?) {
        if model.presetAssignmentsChanged {
            message = Tr.deckConfigPleaseSaveYourChangesFirst
            return
        }
        Task {
            do {
                message = try await job()
            } catch {
                actions.showError(String(describing: error))
            }
        }
    }

    private func optimizeAll() {
        Task {
            do {
                if try await model.saveAndOptimizeAll() { actions.close() }
            } catch {
                actions.showError(String(describing: error))
            }
        }
    }
}
