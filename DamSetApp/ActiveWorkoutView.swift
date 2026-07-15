import SwiftUI
import Combine
import DamSetCore
#if os(iOS)
import UIKit
#endif

struct ActiveWorkoutView: View {
    @Bindable var viewModel: WorkoutViewModel
    @State private var showEndConfirmation = false
    @State private var showRestCorrection = false
    @State private var progressEntryField: ProgressEntryField?
    @State private var progressEntryDraft = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var exerciseTitleSize: CGFloat = 38
    @ScaledMetric(relativeTo: .largeTitle) private var targetNumberSize: CGFloat = 64
    @ScaledMetric(relativeTo: .title) private var actualNumberSize: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle) private var restTimerSize: CGFloat = 72
    private let restTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if let session = viewModel.activeSession {
                    workoutContent(session)
                } else {
                    ContentUnavailableView("No active workout", systemImage: "figure.strengthtraining.traditional")
                }
            }
            .background(GymScreenBackground())
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        if viewModel.activeSession?.sessionStatus == .completed {
                            viewModel.closeWorkout()
                        } else {
                            showEndConfirmation = true
                        }
                    } label: {
                        Text("End")
                            .font(.subheadline.weight(.bold))
                            .fontWidth(.condensed)
                            .foregroundStyle(DamSetDesign.accent)
                            .frame(minWidth: 52, minHeight: 44)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                    .buttonStyle(GymMetalControlButtonStyle())
                    .disabled(viewModel.isBusy)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.repeatCurrentSet()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(DamSetDesign.accent)
                            .frame(width: 44, height: 44)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                    .buttonStyle(GymMetalControlButtonStyle(shape: .circle))
                    .accessibilityLabel("Repeat current set next")
                    .disabled(
                        viewModel.activeSession?.sessionStatus == .completed
                            || viewModel.isBusy
                    )
                }
            }
            .confirmationDialog("Finish workout?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
                if !(viewModel.activeSession?.completedSets.isEmpty ?? true) {
                    Button("Save Completed Sets") { viewModel.finishAndSaveWorkout() }
                }
                Button("Discard Workout", role: .destructive) { viewModel.closeWorkout() }
                Button("Keep Going", role: .cancel) {}
            } message: {
                let count = viewModel.activeSession?.completedSets.count ?? 0
                Text(count == 0 ? "No sets have been completed." : "\(count) completed sets can be saved to History.")
            }
        }
        .tint(DamSetDesign.accent)
        .onReceive(restTimer) { now in
            viewModel.tick(now: now)
        }
        .onAppear { updateIdleTimer() }
        .onChange(of: scenePhase) { _, _ in updateIdleTimer() }
        .onChange(of: viewModel.activeSession?.sessionStatus) { _, _ in updateIdleTimer() }
        .onDisappear { setIdleTimerDisabled(false) }
        .alert(progressEntryField?.title ?? "Edit value", isPresented: progressEntryIsPresented) {
            TextField(progressEntryField?.placeholder ?? "", text: $progressEntryDraft)
            Button("Save") { commitProgressEntry() }
                .disabled(!progressEntryIsValid)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(progressEntryField?.message ?? "Enter a number.")
        }
        .alert("Something went wrong", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func workoutContent(_ session: WorkoutRoutineSession) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                workoutHeader(session)

                if !dynamicTypeSize.isAccessibilitySize {
                    workoutFlowCard(session)
                }

                switch session.lockScreenState.phase {
                case .performingSet:
                    targetCard(session)
                    repsControl(session)
                    weightCard(session)
                case .resting, .readyForNextSet:
                    restCard(session.lockScreenState)
                    restCorrectionPanel(session)
                case .completed:
                    completionCard
                }

                if dynamicTypeSize.isAccessibilitySize,
                   session.lockScreenState.phase != .completed {
                    workoutFlowCard(session)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .safeAreaInset(edge: .bottom) {
            if session.lockScreenState.phase != .completed {
                primaryWorkoutAction(session)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .background {
                        DamSetDesign.chromeBackground
                            .ignoresSafeArea(edges: .bottom)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(DamSetDesign.steelGradient)
                                    .frame(height: 1)
                                    .opacity(0.5)
                            }
                    }
            }
        }
    }

    private func workoutHeader(_ session: WorkoutRoutineSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    workoutIdentity(session)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    setBadge(session)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            } else {
                HStack(alignment: .top) {
                    workoutIdentity(session)
                    Spacer()
                    setBadge(session)
                }
            }

            SteelBarDivider(accent: DamSetDesign.accent)

            ProgressView(value: progress(for: session))
                .tint(DamSetDesign.accent)
                .accessibilityLabel("Workout progress")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func workoutIdentity(_ session: WorkoutRoutineSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.routineName)
                .font(.caption.weight(.semibold))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(DamSetDesign.steel.opacity(0.76))
            Text(session.lockScreenState.exerciseName)
                .font(.system(size: min(exerciseTitleSize, 44), weight: .black, design: .default))
                .fontWidth(.condensed)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setBadge(_ session: WorkoutRoutineSession) -> some View {
        Text("Set \(session.lockScreenState.currentSetIndex)/\(session.lockScreenState.totalPlannedSets)")
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                ChamferedRectangle(cut: 8)
                    .fill(DamSetDesign.surface)
                    .overlay {
                        ChamferedRectangle(cut: 8)
                            .stroke(DamSetDesign.accent.opacity(0.85), lineWidth: 1)
                    }
            }
            .foregroundStyle(DamSetDesign.accent)
    }

    private func workoutFlowCard(_ session: WorkoutRoutineSession) -> some View {
        let metrics = flowMetrics(for: session)
        let statusAccent = phaseColor(for: session.lockScreenState.phase)

        return VStack(spacing: 14) {
            SteelBarDivider(accent: statusAccent)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    flowMetricsVertical(metrics)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                                FlowMetric(metric: metric)
                                if index < metrics.count - 1 {
                                    Divider()
                                        .overlay(DamSetDesign.steelMuted.opacity(0.6))
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)

                        flowMetricsVertical(metrics)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .gymPanel(accent: statusAccent.opacity(0.52), cut: 16)
    }

    private func flowMetricsVertical(_ metrics: [FlowMetricData]) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                FlowMetricRow(metric: metric)
                if index < metrics.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func flowMetrics(for session: WorkoutRoutineSession) -> [FlowMetricData] {
        [
            FlowMetricData(
                title: "Completed",
                value: "\(session.completedSets.count)",
                caption: "sets",
                symbol: "checkmark.circle.fill",
                color: DamSetDesign.moss
            ),
            FlowMetricData(
                title: session.lockScreenState.phase == .resting ? "Resting" : "Now",
                value: phaseValue(for: session.lockScreenState),
                caption: phaseCaption(for: session),
                symbol: phaseSymbol(for: session.lockScreenState.phase),
                color: phaseColor(for: session.lockScreenState.phase)
            ),
            FlowMetricData(
                title: "Next",
                value: session.nextPlannedSet?.exerciseName ?? "Done",
                caption: nextSetCaption(for: session),
                symbol: "forward.fill",
                color: .secondary
            )
        ]
    }

    private func targetCard(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 8) {
            SteelBarDivider()

            GymSectionLabel(text: "Target reps", color: DamSetDesign.steel)
            Text("\(session.lockScreenState.targetReps)")
                .font(.system(size: min(targetNumberSize, 72), weight: .black, design: .default))
                .fontWidth(.condensed)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let planned = session.currentPlannedSet {
                Text("\(planned.targetWeight.formatted()) kg × \(planned.targetReps) · \(planned.restDurationSeconds.minuteSecondText) rest")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let last = session.completedSets.last {
                Label("Last: \(last.exerciseName) · \(last.actualWeight.formatted()) kg × \(last.actualReps)", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .gymPanel(cut: 16)
    }

    private func repsControl(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 14) {
            SteelBarDivider(accent: DamSetDesign.accent)
            repsEditor(session)
        }
        .frame(maxWidth: .infinity)
        .gymPanel(accent: DamSetDesign.accent.opacity(0.78), cut: 16)
    }

    @ViewBuilder
    private func repsEditor(_ session: WorkoutRoutineSession) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                repsValue(session)
                HStack {
                    repsButton(
                        symbol: "minus",
                        label: "Decrease reps",
                        delta: -1,
                        disabled: !session.lockScreenState.canDecrementReps
                    )
                    Spacer()
                    repsButton(symbol: "plus", label: "Increase reps", delta: 1)
                }
            }
        } else {
            HStack(spacing: 20) {
                repsButton(
                    symbol: "minus",
                    label: "Decrease reps",
                    delta: -1,
                    disabled: !session.lockScreenState.canDecrementReps
                )
                repsValue(session)
                repsButton(symbol: "plus", label: "Increase reps", delta: 1)
            }
        }
    }

    private func restCorrectionPanel(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                DisclosureGroup(isExpanded: $showRestCorrection) {
                    VStack(spacing: 18) {
                        repsEditor(session)
                        Divider()
                            .overlay(DamSetDesign.steelMuted.opacity(0.7))
                        weightEditor(session)
                    }
                    .padding(.top, 16)
                } label: {
                    Label("Correct last set", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(DamSetDesign.accent)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } else {
                VStack(spacing: 16) {
                    GymSectionLabel(text: "Correct last set")
                    repsEditor(session)
                    Divider()
                        .overlay(DamSetDesign.steelMuted.opacity(0.7))
                    weightEditor(session)
                }
            }

            Divider()
                .overlay(DamSetDesign.steelMuted.opacity(0.7))
            undoSetButton
        }
        .gymPanel(accent: DamSetDesign.accent.opacity(0.76), cut: 16)
    }

    private func weightCard(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 14) {
            SteelBarDivider()
            weightEditor(session)
        }
        .gymPanel(cut: 16)
    }

    @ViewBuilder
    private func weightEditor(_ session: WorkoutRoutineSession) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                weightValue(session)
                HStack(spacing: 12) {
                    weightButton(delta: -2.5, disabled: session.lockScreenState.actualWeight <= 0)
                    weightButton(delta: 2.5)
                }
            }
        } else {
            HStack(spacing: 12) {
                weightButton(delta: -2.5, disabled: session.lockScreenState.actualWeight <= 0)
                weightValue(session)
                weightButton(delta: 2.5)
            }
        }
    }

    private func repsValue(_ session: WorkoutRoutineSession) -> some View {
        Button {
            beginProgressEntry(.reps, value: String(session.lockScreenState.actualReps))
        } label: {
            VStack(spacing: 2) {
                Text(session.lockScreenState.phase == .performingSet ? "Actual reps" : "Last set reps")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(DamSetDesign.accent)
                Text("\(session.lockScreenState.actualReps)")
                    .font(.system(size: min(actualNumberSize, 52), weight: .black, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(DamSetDesign.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(minWidth: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Actual reps, \(session.lockScreenState.actualReps)")
        .accessibilityHint("Enter actual reps directly")
    }

    private func repsButton(
        symbol: String,
        label: String,
        delta: Int,
        disabled: Bool = false
    ) -> some View {
        GlassCircleControl(symbol: symbol, label: label) {
            viewModel.adjustReps(delta)
        }
        .buttonRepeatBehavior(.enabled)
        .disabled(disabled || viewModel.isBusy)
    }

    private func weightValue(_ session: WorkoutRoutineSession) -> some View {
        Button {
            beginProgressEntry(
                .weight,
                value: String(session.lockScreenState.actualWeight)
            )
        } label: {
            VStack(spacing: 2) {
                Text(session.lockScreenState.phase == .performingSet ? "Actual weight" : "Last set weight")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text("\(session.lockScreenState.actualWeight.formatted()) kg")
                    .font(.title3.weight(.semibold))
                    .fontWidth(.condensed)
                    .foregroundStyle(DamSetDesign.steel)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Actual weight, \(session.lockScreenState.actualWeight.formatted()) kilograms")
        .accessibilityHint("Enter actual weight directly")
    }

    private func weightButton(delta: Double, disabled: Bool = false) -> some View {
        Button {
            viewModel.adjustWeight(delta)
        } label: {
            Text(delta < 0 ? "−2.5" : "+2.5")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(minWidth: 64, minHeight: 48)
        }
        .buttonStyle(GymMetalControlButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        .disabled(disabled || viewModel.isBusy)
        .accessibilityLabel(
            delta < 0
                ? "Decrease weight by 2.5 kilograms"
                : "Increase weight by 2.5 kilograms"
        )
    }

    private var setDoneButton: some View {
        Button {
            viewModel.completeSet()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isCompletingSet {
                    ProgressView()
                }
                Text(viewModel.isCompletingSet ? "Saving…" : "Set Done")
                    .font(.headline)
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Complete current set")
    }

    @ViewBuilder
    private func primaryWorkoutAction(_ session: WorkoutRoutineSession) -> some View {
        switch session.lockScreenState.phase {
        case .performingSet:
            setDoneButton
        case .resting, .readyForNextSet:
            Button {
                viewModel.advanceToNextSet()
            } label: {
                Text(session.lockScreenState.phase == .readyForNextSet ? "Start Next Set" : "Skip Rest")
                    .font(.headline)
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .tracking(1)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(viewModel.isBusy)
            .accessibilityHint(
                session.lockScreenState.phase == .readyForNextSet
                    ? "Begins the next planned set"
                    : "Ends the timer and begins the next planned set"
            )
        case .completed:
            EmptyView()
        }
    }

    private func restCard(_ state: LockScreenState) -> some View {
        let stateColor = state.phase == .readyForNextSet ? DamSetDesign.moss : DamSetDesign.accent

        return VStack(spacing: 14) {
            SteelBarDivider(accent: stateColor)

            GymSectionLabel(
                text: state.phase == .readyForNextSet ? "Rest complete" : "Rest",
                color: stateColor
            )
            Text(state.restRemainingSeconds.minuteSecondText)
                .font(.system(size: min(restTimerSize, 80), weight: .black, design: .default))
                .fontWidth(.condensed)
                .foregroundStyle(stateColor)
                .monospacedDigit()
                .contentTransition(.numericText())

            HStack(spacing: 12) {
                restAdjustmentButton(seconds: -30, disabled: state.restRemainingSeconds == 0)
                restAdjustmentButton(seconds: 30)
            }

            if let resumeAt = state.resumeAt, state.phase == .resting {
                Text("Ready at \(resumeAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(state.phase == .readyForNextSet ? "Ready for the next set" : "You can skip when ready")
                .font(.footnote.weight(.medium))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(stateColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .gymPanel(accent: stateColor.opacity(0.80), cut: 18, padding: 18)
    }

    private var completionCard: some View {
        VStack(spacing: 14) {
            SteelBarDivider(accent: DamSetDesign.moss)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DamSetDesign.moss)
            Text("Workout complete")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            if let summary = viewModel.lastSummary {
                Text("\(summary.totalSets) sets · \(summary.totalVolume.formatted()) kg volume")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            undoSetButton
            Button { viewModel.closeWorkout() } label: {
                Text("Done")
                    .font(.headline)
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .tracking(1)
                    .frame(minWidth: 140, minHeight: 36)
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(viewModel.isBusy)
        }
        .frame(maxWidth: .infinity)
        .gymPanel(accent: DamSetDesign.moss.opacity(0.70), cut: 16)
    }

    private func progress(for session: WorkoutRoutineSession) -> Double {
        let total = max(session.lockScreenState.totalPlannedSets, 1)
        let completed = min(session.completedSets.count, total)
        return Double(completed) / Double(total)
    }

    private func phaseValue(for state: LockScreenState) -> String {
        switch state.phase {
        case .performingSet:
            return "Set \(state.currentSetIndex)"
        case .resting, .readyForNextSet:
            return state.restRemainingSeconds.minuteSecondText
        case .completed:
            return "Done"
        }
    }

    private func phaseCaption(for session: WorkoutRoutineSession) -> String {
        switch session.lockScreenState.phase {
        case .performingSet:
            return "working"
        case .resting:
            return "left"
        case .readyForNextSet:
            return "ready"
        case .completed:
            return "saved"
        }
    }

    private func phaseSymbol(for phase: LockScreenPhase) -> String {
        switch phase {
        case .performingSet:
            return "figure.strengthtraining.traditional"
        case .resting:
            return "timer"
        case .readyForNextSet:
            return "bell.and.waves.left.and.right.fill"
        case .completed:
            return "checkmark.seal.fill"
        }
    }

    private func phaseColor(for phase: LockScreenPhase) -> Color {
        switch phase {
        case .performingSet:
            return DamSetDesign.accent
        case .resting:
            return DamSetDesign.accent
        case .readyForNextSet:
            return DamSetDesign.moss
        case .completed:
            return DamSetDesign.moss
        }
    }

    private func nextSetCaption(for session: WorkoutRoutineSession) -> String {
        guard let next = session.nextPlannedSet else { return "finish" }
        return "\(next.targetWeight.formatted()) kg × \(next.targetReps)"
    }

    private var progressEntryIsPresented: Binding<Bool> {
        Binding(
            get: { progressEntryField != nil },
            set: { isPresented in
                if !isPresented {
                    progressEntryField = nil
                }
            }
        )
    }

    private func beginProgressEntry(_ field: ProgressEntryField, value: String) {
        progressEntryDraft = value
        progressEntryField = field
    }

    private func commitProgressEntry() {
        let rawValue = progressEntryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch progressEntryField {
        case .reps:
            guard let value = Int(rawValue), value >= 0 else { return }
            viewModel.setReps(min(value, 999))
        case .weight:
            let normalized = rawValue.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized), value.isFinite, value >= 0 else { return }
            viewModel.setWeight(min(value, 9_999))
        case nil:
            return
        }
        progressEntryField = nil
    }

    private var progressEntryIsValid: Bool {
        let rawValue = progressEntryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch progressEntryField {
        case .reps:
            return Int(rawValue).map { $0 >= 0 } ?? false
        case .weight:
            let normalized = rawValue.replacingOccurrences(of: ",", with: ".")
            return Double(normalized).map { $0.isFinite && $0 >= 0 } ?? false
        case nil:
            return false
        }
    }

    private func restAdjustmentButton(seconds: Int, disabled: Bool = false) -> some View {
        Button {
            viewModel.adjustRest(seconds)
        } label: {
            Text(seconds < 0 ? "−30 sec" : "+30 sec")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 86, minHeight: 44)
        }
        .buttonStyle(GymMetalControlButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(disabled || viewModel.isBusy)
        .accessibilityLabel(seconds < 0 ? "Reduce rest by 30 seconds" : "Add 30 seconds to rest")
    }

    private var undoSetButton: some View {
        Button {
            viewModel.undoLastCompletedSet()
        } label: {
            Label("Undo Set Done", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(GymMetalControlButtonStyle())
        .disabled(viewModel.isBusy)
        .accessibilityHint("Restores the last completed set with its reps and weight")
    }

    private func updateIdleTimer() {
        let status = viewModel.activeSession?.sessionStatus
        let shouldDisable = scenePhase == ScenePhase.active
            && (status == .active || status == .resting)
        setIdleTimerDisabled(shouldDisable)
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

private enum ProgressEntryField {
    case reps
    case weight

    var title: String {
        switch self {
        case .reps: "Edit reps"
        case .weight: "Edit weight"
        }
    }

    var placeholder: String {
        switch self {
        case .reps: "Reps"
        case .weight: "Kilograms"
        }
    }

    var message: String {
        switch self {
        case .reps: "Enter the reps completed."
        case .weight: "Enter the weight in kilograms."
        }
    }
}

private struct FlowMetricData {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let color: Color
}

private struct FlowMetric: View {
    let metric: FlowMetricData

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: metric.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.color)
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.subheadline.weight(.bold))
                .fontWidth(.condensed)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
            Text(metric.caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct FlowMetricRow: View {
    let metric: FlowMetricData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(metric.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: metric.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(metric.color)
            }

            Text("\(metric.value) · \(metric.caption)")
                .font(.headline.weight(.semibold))
                .fontWidth(.condensed)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
