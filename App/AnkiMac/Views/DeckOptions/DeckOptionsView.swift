import AnkiKit
import SwiftUI

/// Desktop's deck options page on the canvas, in its section order: a
/// band with the deck, its preset and Save, then the sections in one
/// column. Help comes from desktop's tooltips: on each title, and per
/// section from the help button beside its name.
struct DeckOptionsView: View {
    @Bindable var model: DeckOptionsModel
    let chrome: BandChrome
    let actions: DeckOptionsActions
    @State private var scrolled = false

    var body: some View {
        VStack(spacing: 0) {
            PresetBand(model: model, chrome: chrome, actions: actions)
                // Once the settings scroll under the band, a hairline
                // marks where they go out of sight.
                .overlay(alignment: .bottom) {
                    Theme.Palette.hairline.frame(height: 1).opacity(scrolled ? 1 : 0)
                }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.DeckOptions.sectionGap) {
                    DailyLimitsSection(model: model)
                    NewCardsSection(model: model)
                    LapsesSection(model: model)
                    DisplayOrderSection(model: model)
                    FsrsSection(model: model, actions: actions)
                    BurySection(model: model)
                    AudioSection(model: model)
                    TimerSection(model: model)
                    AutoAdvanceSection(model: model)
                    EasyDaysSection(model: model)
                    AdvancedSection(model: model)
                }
                .frame(maxWidth: Theme.DeckOptions.columnWidth, alignment: .leading)
                .padding(.horizontal, Theme.DeckOptions.margin)
                .padding(.top, Theme.Spacing.small)
                .padding(.bottom, Theme.Layout.pageBottomPadding)
                .frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 0 } action: {
                scrolled = $1
            }
            // Scrolls out of sight under the band, not under the lights.
            .clipped()
        }
        .background(Theme.Palette.canvas)
        .foregroundStyle(Theme.Palette.text)
        .tint(Theme.Palette.accent)
    }
}

// MARK: Bindings

extension DeckOptionsModel {
    func number<Value: BinaryInteger>(_ path: WritableKeyPath<DeckConfigInner, Value>) -> Binding<Double> {
        Binding { Double(self.config[keyPath: path]) } set: { self.config[keyPath: path] = Value($0) }
    }

    func number(_ path: WritableKeyPath<DeckConfigInner, Float>) -> Binding<Double> {
        Binding { Double(self.config[keyPath: path]) } set: { self.config[keyPath: path] = Float($0) }
    }

    func binding<Value>(_ path: WritableKeyPath<DeckConfigInner, Value>) -> Binding<Value> {
        Binding { self.config[keyPath: path] } set: { self.config[keyPath: path] = $0 }
    }

    func isDefault<Value: Equatable>(_ path: KeyPath<DeckConfigInner, Value>) -> Bool {
        config[keyPath: path] == defaults[keyPath: path]
    }

    func revert<Value>(_ path: WritableKeyPath<DeckConfigInner, Value>) -> () -> Void {
        { self.config[keyPath: path] = self.defaults[keyPath: path] }
    }
}

/// The rows most settings use, reading and writing the selected preset.
private struct ConfigNumberRow<Value: BinaryInteger>: View {
    let model: DeckOptionsModel
    let title: String
    var help = ""
    let path: WritableKeyPath<DeckConfigInner, Value>
    var range: ClosedRange<Double> = 0...9999

    var body: some View {
        OptionRow(title: title, help: help, isDefault: model.isDefault(path), revert: model.revert(path)) {
            NumberField(value: model.number(path), range: range)
        }
    }
}

private struct ConfigDecimalRow: View {
    let model: DeckOptionsModel
    let title: String
    var help = ""
    let path: WritableKeyPath<DeckConfigInner, Float>
    var range: ClosedRange<Double> = 0...9999
    var step = 0.01
    var decimals = 2
    var percent = false

    var body: some View {
        OptionRow(title: title, help: help, isDefault: model.isDefault(path), revert: model.revert(path)) {
            NumberField(value: model.number(path), range: range, step: step, decimals: decimals, percent: percent)
        }
    }
}

private struct ConfigToggleRow: View {
    let model: DeckOptionsModel
    let title: String
    var help = ""
    let path: WritableKeyPath<DeckConfigInner, Bool>

    var body: some View {
        OptionRow(title: title, help: help, isDefault: model.isDefault(path), revert: model.revert(path)) {
            SwitchControl(title: title, isOn: model.binding(path))
        }
    }
}

private struct ConfigPickerRow<Value: Hashable>: View {
    let model: DeckOptionsModel
    let title: String
    var help = ""
    let path: WritableKeyPath<DeckConfigInner, Value>
    let choices: [(Value, String)]
    var disabled: [Value] = []

    var body: some View {
        OptionRow(title: title, help: help, isDefault: model.isDefault(path), revert: model.revert(path)) {
            OptionPicker(selection: model.binding(path), choices: choices, disabled: disabled)
        }
    }
}

private struct StepsRow: View {
    let model: DeckOptionsModel
    let title: String
    let help: String
    let path: WritableKeyPath<DeckConfigInner, [Float]>

    var body: some View {
        OptionRow(title: title, help: help, isDefault: model.isDefault(path), revert: model.revert(path)) {
            CommitField(text: LearningSteps.format(model.config[keyPath: path])) { text in
                model.config[keyPath: path] = LearningSteps.parse(text)
            }
            .frame(width: Theme.DeckOptions.stepsFieldWidth)
        }
    }
}

/// A switch that applies to the whole collection, marked with a globe as
/// desktop does.
struct GlobalToggleRow: View {
    let title: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        OptionRow(title: title, help: help, isDefault: !isOn, revert: { isOn = false }) {
            HStack(spacing: Theme.Spacing.xSmall) {
                Image(systemName: "globe")
                    .font(Theme.DeckOptions.globeSymbol)
                    .foregroundStyle(Theme.DeckOptions.globeColor)
                    .help(Tr.deckConfigAffectsEntireCollection)
                    .accessibilityLabel(Tr.deckConfigAffectsEntireCollection)
                SwitchControl(title: title, isOn: $isOn)
            }
        }
    }
}

/// A limit set per preset, per deck or for today: the tabs choose which.
struct TabbedLimitRow: View {
    let model: DeckOptionsModel
    let limit: DeckOptionsModel.Limit
    let title: String
    let help: String
    let defaultValue: Double
    var range: ClosedRange<Double> = 0...9999
    var step = 1.0
    var decimals = 0
    var percent = false

    var body: some View {
        OptionRow(
            title: title, help: help, isDefault: rounded(model.value(limit)) == rounded(defaultValue),
            revert: { model.setValue(limit, defaultValue) }
        ) {
            NumberField(
                value: Binding { model.value(limit) } set: { model.setValue(limit, $0) },
                range: range, step: step, decimals: decimals, percent: percent)
        }
        // Under the title, pulled out by their padding so the first word
        // lines up with it, as Statistics' switches.
        QuietSegments(
            selection: Binding { model.scope(limit) } set: { model.setScope(limit, $0) },
            choices: limit.scopes, title: \.title
        )
        .padding(.leading, -Theme.Layout.segmentPadding)
        .help(Tr.deckConfigTabDescription)
        .accessibilityLabel(title)
        .optionNote()
    }

    /// Desktop compares to two decimals, so an f32 retention matches its default.
    private func rounded(_ value: Double) -> Double { (value * 100).rounded() }
}

// MARK: Sections

private struct DailyLimitsSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let extra = "\n\n" + Tr.deckConfigLimitDeckV3 + "\n\n" + Tr.deckConfigTabDescription
        let newHelp = Tr.deckConfigNewLimitTooltip + extra
        let reviewHelp = Tr.deckConfigReviewLimitTooltip + "\n\n" + Tr.deckConfigLimitInterdayBoundByReviews + extra
        let ignoreHelp = Tr.deckConfigAffectsEntireCollection + "\n\n" + Tr.deckConfigNewCardsIgnoreReviewLimitTooltip
        let parentHelp = Tr.deckConfigAffectsEntireCollection + "\n\n" + Tr.deckConfigApplyAllParentLimitsTooltip
        let newValue = Int(model.value(.new))
        let expected = min(9999, newValue * 10)
        OptionSection(
            title: Tr.deckConfigDailyLimits,
            help: [
                (Tr.schedulingNewCardsday, newHelp), (Tr.schedulingMaximumReviewsday, reviewHelp),
                (Tr.deckConfigNewCardsIgnoreReviewLimit, ignoreHelp),
                (Tr.deckConfigApplyAllParentLimits, parentHelp),
            ]) {
            TabbedLimitRow(
                model: model, limit: .new, title: Tr.schedulingNewCardsday, help: newHelp,
                defaultValue: Double(model.defaults.newPerDay))
            TabbedLimitRow(
                model: model, limit: .review, title: Tr.schedulingMaximumReviewsday, help: reviewHelp,
                defaultValue: Double(model.defaults.reviewsPerDay))
            if expected > Int(model.value(.review)) {
                OptionWarning(text: Tr.deckConfigReviewsTooLow(cards: newValue, expected: String(expected)))
            }
            GlobalToggleRow(
                title: Tr.deckConfigNewCardsIgnoreReviewLimit, help: ignoreHelp,
                isOn: Bindable(model).newCardsIgnoreReviewLimit)
            GlobalToggleRow(
                title: Tr.deckConfigApplyAllParentLimits, help: parentHelp, isOn: Bindable(model).applyAllParentLimits)
        }
    }
}

private struct NewCardsSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let config = model.config
        let lastStepDays = Double(config.learnSteps.last ?? 0) / 60 / 24
        OptionSection(
            title: Tr.schedulingNewCards,
            help: [
                (Tr.deckConfigLearningSteps, Tr.deckConfigLearningStepsTooltip),
                (Tr.schedulingGraduatingInterval, Tr.deckConfigGraduatingIntervalTooltip),
                (Tr.schedulingEasyInterval, Tr.deckConfigEasyIntervalTooltip),
                (Tr.deckConfigNewInsertionOrder, Tr.deckConfigNewInsertionOrderTooltip),
            ]) {
            StepsRow(
                model: model, title: Tr.deckConfigLearningSteps, help: Tr.deckConfigLearningStepsTooltip,
                path: \.learnSteps)
            if model.fsrs && lastStepDays >= 1 {
                OptionWarning(text: Tr.deckConfigStepsTooLargeForFsrs)
            }
            if !model.fsrs {
                ConfigNumberRow(
                    model: model, title: Tr.schedulingGraduatingInterval,
                    help: Tr.deckConfigGraduatingIntervalTooltip, path: \.graduatingIntervalGood)
                if lastStepDays > Double(config.graduatingIntervalGood) {
                    OptionWarning(text: Tr.deckConfigLearningStepAboveGraduatingInterval)
                }
                ConfigNumberRow(
                    model: model, title: Tr.schedulingEasyInterval, help: Tr.deckConfigEasyIntervalTooltip,
                    path: \.graduatingIntervalEasy)
                if config.graduatingIntervalGood > config.graduatingIntervalEasy {
                    OptionWarning(text: Tr.deckConfigGoodAboveEasy)
                }
            }
            ConfigPickerRow(
                model: model, title: Tr.deckConfigNewInsertionOrder, help: Tr.deckConfigNewInsertionOrderTooltip,
                path: \.newCardInsertOrder,
                choices: [
                    (.due, Tr.deckConfigNewInsertionOrderSequential), (.random, Tr.deckConfigNewInsertionOrderRandom),
                ])
            if config.newCardInsertOrder == .random {
                OptionWarning(text: Tr.deckConfigNewInsertionOrderRandomWithV3)
            }
        }
    }
}

private struct LapsesSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let config = model.config
        let lastStepDays = Double(config.relearnSteps.last ?? 0) / 60 / 24
        OptionSection(
            title: Tr.schedulingLapses,
            help: [
                (Tr.deckConfigRelearningSteps, Tr.deckConfigRelearningStepsTooltip),
                (Tr.schedulingMinimumInterval, Tr.deckConfigMinimumIntervalTooltip),
                (Tr.schedulingLeechThreshold, Tr.deckConfigLeechThresholdTooltip),
                (Tr.schedulingLeechAction, Tr.deckConfigLeechActionTooltip),
            ]) {
            StepsRow(
                model: model, title: Tr.deckConfigRelearningSteps, help: Tr.deckConfigRelearningStepsTooltip,
                path: \.relearnSteps)
            if model.fsrs && lastStepDays >= 1 {
                OptionWarning(text: Tr.deckConfigStepsTooLargeForFsrs)
            }
            if !model.fsrs {
                ConfigNumberRow(
                    model: model, title: Tr.schedulingMinimumInterval, help: Tr.deckConfigMinimumIntervalTooltip,
                    path: \.minimumLapseInterval, range: 1...9999)
                if lastStepDays > Double(config.minimumLapseInterval) {
                    OptionWarning(text: Tr.deckConfigRelearningStepsAboveMinimumInterval)
                }
            }
            ConfigNumberRow(
                model: model, title: Tr.schedulingLeechThreshold, help: Tr.deckConfigLeechThresholdTooltip,
                path: \.leechThreshold, range: 1...9999)
            ConfigPickerRow(
                model: model, title: Tr.schedulingLeechAction, help: Tr.deckConfigLeechActionTooltip,
                path: \.leechAction,
                choices: [(.suspend, Tr.actionsSuspendCard), (.tagOnly, Tr.schedulingTagOnly)])
        }
    }
}

private struct DisplayOrderSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let currentDeck = "\n\n" + Tr.deckConfigDisplayOrderWillUseCurrentDeck
        let help: [(String, String)] = [
            (Tr.deckConfigNewGatherPriority, Tr.deckConfigNewGatherPriorityTooltip2 + currentDeck),
            (Tr.deckConfigNewCardSortOrder, Tr.deckConfigNewCardSortOrderTooltip2 + currentDeck),
            (Tr.deckConfigNewReviewPriority, Tr.deckConfigNewReviewPriorityTooltip + currentDeck),
            (Tr.deckConfigInterdayStepPriority, Tr.deckConfigInterdayStepPriorityTooltip + currentDeck),
            (Tr.deckConfigReviewSortOrder, Tr.deckConfigReviewSortOrderTooltip + currentDeck),
        ]
        let mixes: [(DeckConfigInner.ReviewMix, String)] = [
            (.mixWithReviews, Tr.deckConfigReviewMixMixWithReviews),
            (.afterReviews, Tr.deckConfigReviewMixShowAfterReviews),
            (.beforeReviews, Tr.deckConfigReviewMixShowBeforeReviews),
        ]
        OptionSection(title: Tr.deckConfigOrderingTitle, help: help) {
            ConfigPickerRow(
                model: model, title: help[0].0, help: help[0].1,
                path: \.newCardGatherPriority,
                choices: [
                    (.deck, Tr.deckConfigNewGatherPriorityDeck),
                    (.deckThenRandomNotes, Tr.deckConfigNewGatherPriorityDeckThenRandomNotes),
                    (.lowestPosition, Tr.deckConfigNewGatherPriorityPositionLowestFirst),
                    (.highestPosition, Tr.deckConfigNewGatherPriorityPositionHighestFirst),
                    (.randomNotes, Tr.deckConfigNewGatherPriorityRandomNotes),
                    (.randomCards, Tr.deckConfigNewGatherPriorityRandomCards),
                ])
            .onChange(of: model.config.newCardGatherPriority) { _, gather in
                // A sort order that repeats another one goes back to the default.
                if DeckOptionsModel.disabledSortOrders(for: gather).contains(model.config.newCardSortOrder) {
                    model.config.newCardSortOrder = .template
                }
            }
            ConfigPickerRow(
                model: model, title: help[1].0, help: help[1].1, path: \.newCardSortOrder,
                choices: [
                    (.template, Tr.deckConfigSortOrderTemplateThenGather),
                    (.noSort, Tr.deckConfigSortOrderGather),
                    (.templateThenRandom, Tr.deckConfigSortOrderCardTemplateThenRandom),
                    (.randomNoteThenTemplate, Tr.deckConfigSortOrderRandomNoteThenTemplate),
                    (.randomCard, Tr.deckConfigSortOrderRandom),
                ],
                disabled: DeckOptionsModel.disabledSortOrders(for: model.config.newCardGatherPriority))
            ConfigPickerRow(model: model, title: help[2].0, help: help[2].1, path: \.newMix, choices: mixes)
            ConfigPickerRow(
                model: model, title: help[3].0, help: help[3].1, path: \.interdayLearningMix, choices: mixes)
            ConfigPickerRow(
                model: model, title: help[4].0, help: help[4].1, path: \.reviewOrder,
                choices: reviewOrderChoices(fsrs: model.fsrs))
        }
    }
}

/// Review orders in desktop's order; FSRS speaks of difficulty rather than
/// ease, and adds retrievability.
func reviewOrderChoices(fsrs: Bool) -> [(DeckConfigInner.ReviewCardOrder, String)] {
        var difficulty: [(DeckConfigInner.ReviewCardOrder, String)] = [
            (.easeAscending, fsrs ? Tr.deckConfigSortOrderDescendingDifficulty : Tr.deckConfigSortOrderAscendingEase),
            (.easeDescending, fsrs ? Tr.deckConfigSortOrderAscendingDifficulty : Tr.deckConfigSortOrderDescendingEase),
        ]
        if fsrs { difficulty.reverse() }
        let retrievability: [(DeckConfigInner.ReviewCardOrder, String)] = fsrs ? [
            (.retrievabilityAscending, Tr.deckConfigSortOrderRetrievabilityAscending),
            (.retrievabilityDescending, Tr.deckConfigSortOrderRetrievabilityDescending),
        ] : []
        return [
            (.day, Tr.deckConfigSortOrderDueDateThenRandom),
            (.dayThenDeck, Tr.deckConfigSortOrderDueDateThenDeck),
            (.deckThenDay, Tr.deckConfigSortOrderDeckThenDueDate),
            (.intervalsAscending, Tr.deckConfigSortOrderAscendingIntervals),
            (.intervalsDescending, Tr.deckConfigSortOrderDescendingIntervals),
        ] + difficulty + retrievability + [
            (.relativeOverdueness, Tr.decksRelativeOverdueness),
            (.random, Tr.deckConfigSortOrderRandom),
            (.added, Tr.decksOrderAdded),
            (.reverseAdded, Tr.decksLatestAddedFirst),
        ]
}

private struct BurySection: View {
    let model: DeckOptionsModel

    var body: some View {
        let priority = "\n\n" + Tr.deckConfigBuryPriorityTooltip
        let help: [(String, String)] = [
            (Tr.deckConfigBuryNewSiblings, Tr.deckConfigBuryNewTooltip + priority),
            (Tr.deckConfigBuryReviewSiblings, Tr.deckConfigBuryReviewTooltip + priority),
            (Tr.deckConfigBuryInterdayLearningSiblings, Tr.deckConfigBuryInterdayLearningTooltip + priority),
        ]
        OptionSection(title: Tr.deckConfigBuryTitle, help: help) {
            ConfigToggleRow(model: model, title: help[0].0, help: help[0].1, path: \.buryNew)
            ConfigToggleRow(model: model, title: help[1].0, help: help[1].1, path: \.buryReviews)
            ConfigToggleRow(model: model, title: help[2].0, help: help[2].1, path: \.buryInterdayLearning)
        }
    }
}

private struct AudioSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let help: [(String, String)] = [
            (Tr.deckConfigDisableAutoplay, Tr.deckConfigDisableAutoplayTooltip),
            (Tr.deckConfigSkipQuestionWhenReplaying, Tr.deckConfigAlwaysIncludeQuestionAudioTooltip),
        ]
        OptionSection(title: Tr.deckConfigAudioTitle, help: help) {
            ConfigToggleRow(model: model, title: help[0].0, help: help[0].1, path: \.disableAutoplay)
            ConfigToggleRow(
                model: model, title: help[1].0, help: help[1].1, path: \.skipQuestionWhenReplayingAnswer)
        }
    }
}

private struct TimerSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let help: [(String, String)] = [
            (Tr.deckConfigMaximumAnswerSecs, Tr.deckConfigMaximumAnswerSecsTooltip),
            (Tr.schedulingShowAnswerTimer, Tr.deckConfigShowAnswerTimerTooltip),
            (Tr.deckConfigStopTimerOnAnswer, Tr.deckConfigStopTimerOnAnswerTooltip),
        ]
        OptionSection(title: Tr.deckConfigTimerTitle, help: help) {
            ConfigNumberRow(
                model: model, title: help[0].0, help: help[0].1, path: \.capAnswerTimeToSecs, range: 1...7200)
            if model.config.capAnswerTimeToSecs > 600 {
                OptionWarning(text: Tr.deckConfigMaximumAnswerSecsAboveRecommended)
            }
            ConfigToggleRow(model: model, title: help[1].0, help: help[1].1, path: \.showTimer)
            ConfigToggleRow(model: model, title: help[2].0, help: help[2].1, path: \.stopTimerOnAnswer)
        }
    }
}

private struct AutoAdvanceSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let help: [(String, String)] = [
            (Tr.deckConfigSecondsToShowQuestion, Tr.deckConfigSecondsToShowQuestionTooltip3),
            (Tr.deckConfigSecondsToShowAnswer, Tr.deckConfigSecondsToShowAnswerTooltip2),
            (Tr.deckConfigWaitForAudio, Tr.deckConfigWaitForAudioTooltip2),
            (Tr.deckConfigQuestionAction, Tr.deckConfigQuestionActionToolTip),
            (Tr.deckConfigAnswerAction, Tr.deckConfigAnswerActionTooltip2),
        ]
        OptionSection(title: Tr.actionsAutoAdvance, help: help) {
            ConfigDecimalRow(
                model: model, title: help[0].0, help: help[0].1, path: \.secondsToShowQuestion,
                step: 0.1, decimals: 1)
            ConfigDecimalRow(
                model: model, title: help[1].0, help: help[1].1, path: \.secondsToShowAnswer, step: 0.1, decimals: 1)
            ConfigToggleRow(model: model, title: help[2].0, help: help[2].1, path: \.waitForAudio)
            ConfigPickerRow(
                model: model, title: help[3].0, help: help[3].1, path: \.questionAction,
                choices: [
                    (.showAnswer, Tr.deckConfigQuestionActionShowAnswer),
                    (.showReminder, Tr.deckConfigQuestionActionShowReminder),
                ])
            ConfigPickerRow(
                model: model, title: help[4].0, help: help[4].1, path: \.answerAction,
                choices: [
                    (.buryCard, Tr.studyingBuryCard), (.answerAgain, Tr.deckConfigAnswerAgain),
                    (.answerGood, Tr.deckConfigAnswerGood), (.answerHard, Tr.deckConfigAnswerHard),
                    (.showReminder, Tr.deckConfigShowReminder),
                ])
        }
    }
}

private struct EasyDaysSection: View {
    let model: DeckOptionsModel
    /// Desktop warns once the days differ from when the window opened.
    @State private var initial: [Float]?

    var body: some View {
        let values = model.config.easyDaysPercentages
        OptionSection(title: Tr.deckConfigEasyDaysTitle) {
            EasyDaysSliders(values: Binding { model.config.easyDaysPercentages } set: {
                model.config.easyDaysPercentages = $0
            })
            if !values.contains(1) {
                OptionWarning(text: Tr.deckConfigEasyDaysNoNormalDays)
            }
            if let initial, values != initial, !(model.fsrs && model.fsrsReschedule) {
                OptionWarning(text: Tr.deckConfigEasyDaysChange)
            }
        }
        .onAppear { if initial == nil { initial = values } }
    }
}

/// A row per weekday, its slider from minimum through reduced to a normal
/// workload, under a scale that names the three stops.
struct EasyDaysSliders: View {
    @Binding var values: [Float]
    /// False in the simulator, whose values aren't the preset's.
    var revertible = true

    private static let days = [
        Tr.deckConfigEasyDaysMonday, Tr.deckConfigEasyDaysTuesday, Tr.deckConfigEasyDaysWednesday,
        Tr.deckConfigEasyDaysThursday, Tr.deckConfigEasyDaysFriday, Tr.deckConfigEasyDaysSaturday,
        Tr.deckConfigEasyDaysSunday,
    ]

    private static let stops = [
        Tr.deckConfigEasyDaysMinimum, Tr.deckConfigEasyDaysReduced, Tr.deckConfigEasyDaysNormal,
    ]

    var body: some View {
        // Over the sliders' column, as a table's column title; each slider
        // reads its stop out instead.
        OptionRow(title: "", revertible: revertible) {
            HStack {
                Text(Self.stops[0])
                Spacer()
                Text(Self.stops[1])
                Spacer()
                Text(Self.stops[2])
            }
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Palette.secondary)
            .frame(width: Theme.DeckOptions.sliderWidth)
        }
        .accessibilityHidden(true)
        .optionNote()
        ForEach(Self.days.indices, id: \.self) { index in
            let value = values[safe: index] ?? 1
            OptionRow(title: Self.days[index], isDefault: value == 1, revert: { set(index, 1) }, revertible: revertible) {
                Slider(value: Binding { Double(value) } set: { set(index, Float($0)) }, in: 0...1, step: 0.5) {
                    Text(Self.days[index])
                }
                .labelsHidden()
                .controlSize(.small)
                .tint(Theme.DeckOptions.controlTint)
                .frame(width: Theme.DeckOptions.sliderWidth)
                .accessibilityValue(Self.stops[min(2, Int((value * 2).rounded()))])
            }
        }
    }

    private func set(_ index: Int, _ value: Float) {
        guard values.indices.contains(index) else { return }
        values[index] = value
    }
}

private struct AdvancedSection: View {
    let model: DeckOptionsModel

    var body: some View {
        let config = model.config
        let help: [(String, String)] = [
            (Tr.schedulingMaximumInterval, Tr.deckConfigMaximumIntervalTooltip),
            (Tr.deckConfigHistoricalRetention, Tr.deckConfigHistoricalRetentionTooltip),
            (Tr.deckConfigIgnoreBefore, Tr.deckConfigIgnoreBeforeTooltip2),
            (Tr.schedulingStartingEase, Tr.deckConfigStartingEaseTooltip),
            (Tr.schedulingEasyBonus, Tr.deckConfigEasyBonusTooltip),
            (Tr.schedulingIntervalModifier, Tr.deckConfigIntervalModifierTooltip),
            (Tr.schedulingHardInterval, Tr.deckConfigHardIntervalTooltip),
            (Tr.schedulingNewInterval, Tr.deckConfigNewIntervalTooltip),
            (Tr.deckConfigCustomScheduling, Tr.deckConfigCustomSchedulingTooltip),
        ]
        OptionSection(title: Tr.deckConfigAdvancedTitle, help: help) {
            ConfigNumberRow(
                model: model, title: help[0].0, help: help[0].1, path: \.maximumReviewInterval, range: 1...36500)
            if config.maximumReviewInterval < 180 {
                OptionWarning(
                    text: Tr.deckConfigTooShortMaximumInterval,
                    level: config.maximumReviewInterval < 50 ? .danger : .warning)
            }
            if !model.fsrs {
                ConfigDecimalRow(
                    model: model, title: help[3].0, help: help[3].1, path: \.initialEase, range: 1.31...5)
                ConfigDecimalRow(
                    model: model, title: help[4].0, help: help[4].1, path: \.easyMultiplier, range: 1...5)
                ConfigDecimalRow(
                    model: model, title: help[5].0, help: help[5].1, path: \.intervalMultiplier, range: 0.5...2)
                ConfigDecimalRow(
                    model: model, title: help[6].0, help: help[6].1, path: \.hardMultiplier, range: 0.5...1.3)
                ConfigDecimalRow(
                    model: model, title: help[7].0, help: help[7].1, path: \.lapseMultiplier, range: 0...1)
            } else {
                ConfigDecimalRow(
                    model: model, title: help[1].0, help: help[1].1, path: \.historicalRetention, range: 0.5...1)
                IgnoreBeforeRow(model: model, title: help[2].0, help: help[2].1)
            }
            CustomSchedulingRow(model: model, title: help[8].0, help: help[8].1)
        }
    }
}

/// "Ignore cards reviewed before", with desktop's count of the cards that
/// will still be used, checked a second after the date stops changing.
private struct IgnoreBeforeRow: View {
    let model: DeckOptionsModel
    let title: String
    let help: String
    @State private var counts: Anki_DeckConfig_GetIgnoredBeforeCountResponse?

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        let text = model.config.ignoreRevlogsBeforeDate
        OptionRow(title: title, help: help, isDefault: text == "1970-01-01", revert: {
            model.config.ignoreRevlogsBeforeDate = "1970-01-01"
        }) {
            DatePicker(
                title,
                selection: Binding {
                    Self.formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
                } set: {
                    model.config.ignoreRevlogsBeforeDate = Self.formatter.string(from: $0)
                },
                in: ...Date(), displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
        }
        .task(id: text) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            counts = await model.ignoredBeforeCount(date: text)
        }
        if let counts {
            let included = Double(counts.included)
            let total = Double(counts.total)
            OptionWarning(
                text: Tr.deckConfigIgnoreBeforeInfo(included: String(counts.included), totalCards: String(counts.total)),
                level: included / total < 0.1 ? .danger : included != total ? .warning : .info)
        }
    }
}

private struct CustomSchedulingRow: View {
    @Bindable var model: DeckOptionsModel
    let title: String
    let help: String

    /// Desktop's manual chapter on what the code can change.
    private static let manual = "https://faqs.ankiweb.net/the-2021-scheduler.html#add-ons-and-custom-scheduling"

    /// Shown faded while the box is empty, so it's clear the box takes
    /// JavaScript and what it works on.
    private static let sample = """
        if (states.good.normal?.review) {
          states.good.normal.review.scheduledDays =
            Math.min(states.good.normal.review.scheduledDays, 30);
        }
        """

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                // Code as an unboxed block, as the editor's HTML source.
                TextEditor(text: $model.cardStateCustomizer)
                    .font(Theme.DeckOptions.codeFont)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if model.cardStateCustomizer.isEmpty {
                            Text(Self.sample)
                                .font(Theme.DeckOptions.codeFont)
                                .foregroundStyle(Theme.Palette.tertiary)
                                .padding(.leading, Theme.DeckOptions.codeLineInset)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(Theme.DeckOptions.fieldPadding)
                    .frame(height: Theme.DeckOptions.customSchedulingHeight)
                    .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius).fill(Theme.Palette.hover))
                OptionWarning(text: help + " " + Tr.helpForMoreInfo(link: "[\(title)](\(Self.manual))"))
            }
            .padding(.top, Theme.Spacing.small)
        } label: {
            HStack(spacing: Theme.Spacing.xSmall) {
                Text(title).font(Theme.DeckOptions.rowFont).help(help)
                    .accessibilityHint(plainText(help))
                Image(systemName: "globe")
                    .font(Theme.DeckOptions.globeSymbol)
                    .foregroundStyle(Theme.DeckOptions.globeColor)
                    .help(Tr.deckConfigAffectsEntireCollection)
            }
        }
    }
}

// MARK: Band

/// Under the traffic lights, as Add's: the deck the options are for, the
/// preset it uses as a quiet menu that also holds desktop's preset
/// commands, then Save, the window's one prominent action.
private struct PresetBand: View {
    let model: DeckOptionsModel
    let chrome: BandChrome
    let actions: DeckOptionsActions
    @State private var naming: PresetNaming?
    @State private var name = ""
    @State private var confirmingRemove = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Text(model.deckName.replacingOccurrences(of: "::", with: " \u{203A} "))
                .font(Theme.Band.titleFont)
                .lineLimit(1)
                .truncationMode(.head)
                .help(Tr.actionsOptionsFor(val: model.deckName))
                .layoutPriority(-1)
            Spacer(minLength: Theme.Spacing.small)
            presetMenu
            Button { actions.save(.normal) } label: {
                HStack(spacing: Theme.Layout.keyCapGap) {
                    Text(Tr.deckConfigSaveButton)
                    KeyCap("\u{2318}S", onAccent: true)
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            // File › Save holds ⌘S, for this window while it is key.
            .padding(.leading, Theme.Spacing.xSmall)
        }
        // Clear of the traffic lights, which in full screen come down over
        // the band in a pill of their own.
        .padding(.leading, chrome.fullScreen ? Theme.Spacing.medium : Theme.Band.leading)
        .padding(.trailing, Theme.Spacing.medium)
        .frame(height: Theme.Band.height)
        .titleBarBand()
        .alert(naming?.title ?? "", isPresented: Binding { naming != nil } set: { if !$0 { naming = nil } }) {
            TextField(Tr.deckConfigNamePrompt, text: $name)
            Button(Tr.actionsCancel, role: .cancel) {}
            Button(naming?.title ?? "") {
                guard let naming else { return }
                switch naming {
                case .add: model.addPreset(named: name, cloning: false)
                case .clone: model.addPreset(named: name, cloning: true)
                case .rename: model.rename(to: name)
                }
            }
        }
        .alert(Tr.deckConfigConfirmRemoveName(name: model.preset.name), isPresented: $confirmingRemove) {
            Button(Tr.actionsCancel, role: .cancel) {}
            Button(Tr.deckConfigRemoveGroup, role: .destructive) { model.removePreset() }
        } message: {
            if model.removalForcesOneWaySync { Text(Tr.deckConfigWillRequireFullSync) }
        }
    }

    /// The presets with how many decks use each, then what can be done
    /// with them, as desktop's dropdown and its gear menu.
    private var presetMenu: some View {
        Menu {
            Picker(Tr.deckConfigSharedPreset, selection: Binding { model.selectedIndex } set: { model.select($0) }) {
                ForEach(model.presets.indices, id: \.self) { index in
                    Text(model.presets[index].config.name
                        + " (" + Tr.deckConfigUsedByDecks(decks: model.useCount(at: index)) + ")")
                        .tag(index)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button(Tr.deckConfigAddGroup + "…") { ask(.add, "") }
            Button(Tr.deckConfigCloneGroup + "…") { ask(.clone, model.preset.name) }
            Button(Tr.deckConfigRenameGroup + "…") { ask(.rename, model.preset.name) }
            Button(Tr.deckConfigRemoveGroup + "…", role: .destructive) {
                if model.isDefaultPresetSelected {
                    actions.showError(
                        ActionFailure(Tr.schedulingTheDefaultConfigurationCantBeRemoved, detail: ""))
                } else {
                    confirmingRemove = true
                }
            }
            Divider()
            Button(Tr.deckConfigSaveToAllSubdecks) { actions.save(.applyToChildren) }
        } label: {
            QuietMenuLabel(title: Tr.deckConfigSharedPreset, value: model.preset.name)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .layoutPriority(-0.5)
        .accessibilityLabel(Tr.deckConfigSharedPreset)
        .accessibilityValue(model.preset.name)
    }

    private func ask(_ kind: PresetNaming, _ initial: String) {
        name = initial
        naming = kind
    }
}

enum PresetNaming {
    case add, clone, rename

    var title: String {
        switch self {
        case .add: Tr.deckConfigAddGroup
        case .clone: Tr.deckConfigCloneGroup
        case .rename: Tr.deckConfigRenameGroup
        }
    }
}
