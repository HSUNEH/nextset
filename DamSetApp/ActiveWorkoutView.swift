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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    workoutStack(session, compact: false)
                }
            } else {
                ViewThatFits(in: .vertical) {
                    workoutStack(session, compact: true)

                    ScrollView {
                        workoutStack(session, compact: false)
                    }
                }
            }
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

    @ViewBuilder
    private func workoutStack(_ session: WorkoutRoutineSession, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            workoutHeader(session, compact: compact)
            restAlertStatusBanner

            if session.lockScreenState.phase != .completed {
                workoutJourney(session)
            }

            switch session.lockScreenState.phase {
            case .performingSet:
                if compact {
                    compactPerformingCard(session)
                } else {
                    targetCard(session)
                    progressControl(session)
                    if session.lockScreenState.exerciseKind == .weighted {
                        weightCard(session)
                    }
                }
            case .resting, .readyForNextSet:
                restCard(session, compact: compact)
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
        .padding(.vertical, compact ? 8 : 12)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var restAlertStatusBanner: some View {
        switch viewModel.restAlertDeliveryStatus {
        case .checking, .enabled:
            EmptyView()
        case .disabled(let canRequestFallback):
            restAlertBanner(
                message: "Lock Screen 3 · 2 · 1 sound is off",
                actionTitle: canRequestFallback ? "Enable sounds" : "Settings",
                action: canRequestFallback ? viewModel.enableRestCueNotifications : openAppSettings
            )
        }
    }

    private func restAlertBanner(
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    restAlertMessage(message)
                    restAlertAction(actionTitle, action: action)
                }
            } else {
                HStack(spacing: 10) {
                    restAlertMessage(message)
                    Spacer(minLength: 4)
                    restAlertAction(actionTitle, action: action)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DamSetDesign.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(DamSetDesign.amber.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func restAlertMessage(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(DamSetDesign.amber)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func restAlertAction(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.bold))
            .foregroundStyle(DamSetDesign.amber)
            .frame(minHeight: 44)
            .accessibilityHint("Changes how rest completion is delivered while the phone is locked")
    }

    private func openAppSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func workoutHeader(_ session: WorkoutRoutineSession, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 12) {
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

            HStack(spacing: 10) {
                ProgressView(value: progress(for: session))
                    .tint(DamSetDesign.accent)
                    .accessibilityLabel("Workout progress")
                Text("\(session.completedSets.count) done · \(setsRemaining(in: session)) left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, compact ? 3 : 8)
    }

    private func workoutIdentity(_ session: WorkoutRoutineSession) -> some View {
        let isResting = session.lockScreenState.phase == .resting
            || session.lockScreenState.phase == .readyForNextSet
        let displayedExercise = isResting
            ? session.nextPlannedSet?.exerciseName ?? "Workout complete"
            : session.lockScreenState.exerciseName

        return VStack(alignment: .leading, spacing: 4) {
            Text(isResting ? "\(session.routineName) · Up next" : session.routineName)
                .font(.caption.weight(.semibold))
                .fontWidth(.condensed)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(DamSetDesign.steel.opacity(0.76))
            Text(displayedExercise)
                .font(.system(size: min(exerciseTitleSize, 44), weight: .black, design: .default))
                .fontWidth(.condensed)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func setBadge(_ session: WorkoutRoutineSession) -> some View {
        let displayedIndex = min(
            session.lockScreenState.phase == .resting
                || session.lockScreenState.phase == .readyForNextSet
                ? session.currentSetIndex + 1
                : session.currentSetIndex,
            session.lockScreenState.totalPlannedSets
        )

        return Text("Set \(displayedIndex)/\(session.lockScreenState.totalPlannedSets)")
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

    private func workoutJourney(_ session: WorkoutRoutineSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(session.plannedSets.enumerated()), id: \.element.setId) { index, planned in
                        JourneySetPill(
                            setNumber: index + 1,
                            exerciseName: planned.exerciseName,
                            detail: journeyDetail(planned),
                            state: journeyState(at: index, in: session)
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(journeyFocusIndex(in: session), anchor: .center)
            }
            .onChange(of: journeyFocusIndex(in: session)) { _, newIndex in
                withAnimation(.snappy) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .accessibilityLabel(
            "Workout journey. \(session.completedSets.count) sets complete, \(setsRemaining(in: session)) remaining."
        )
    }

    private func compactPerformingCard(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    GymSectionLabel(
                        text: session.lockScreenState.trackingMode == .duration ? "Target time" : "Target reps",
                        color: DamSetDesign.steel
                    )
                    Text(targetValue(for: session.lockScreenState))
                        .font(.system(size: 42, weight: .black))
                        .fontWidth(.condensed)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                if let planned = session.currentPlannedSet {
                    Text(targetDescription(planned))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }

            Divider().overlay(DamSetDesign.steelMuted.opacity(0.7))
            progressEditor(session)

            if session.lockScreenState.exerciseKind == .weighted {
                Divider().overlay(DamSetDesign.steelMuted.opacity(0.7))
                weightEditor(session)
            }
        }
        .frame(maxWidth: .infinity)
        .gymPanel(accent: DamSetDesign.accent.opacity(0.78), cut: 16, padding: 14)
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

            GymSectionLabel(
                text: session.lockScreenState.trackingMode == .duration ? "Target time" : "Target reps",
                color: DamSetDesign.steel
            )
            Text(targetValue(for: session.lockScreenState))
                .font(.system(size: min(targetNumberSize, 72), weight: .black, design: .default))
                .fontWidth(.condensed)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let planned = session.currentPlannedSet {
                Text(targetDescription(planned))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let last = session.completedSets.last {
                Label("Last: \(last.exerciseName) · \(completedSetDescription(last))", systemImage: "clock.arrow.circlepath")
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

    private func progressControl(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 14) {
            SteelBarDivider(accent: DamSetDesign.accent)
            progressEditor(session)
        }
        .frame(maxWidth: .infinity)
        .gymPanel(accent: DamSetDesign.accent.opacity(0.78), cut: 16)
    }

    @ViewBuilder
    private func progressEditor(_ session: WorkoutRoutineSession) -> some View {
        if session.lockScreenState.trackingMode == .duration {
            durationEditor(session)
        } else {
            repsEditor(session)
        }
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

    @ViewBuilder
    private func durationEditor(_ session: WorkoutRoutineSession) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                durationValue(session)
                HStack {
                    durationButton(
                        symbol: "minus",
                        label: "Decrease time by 5 seconds",
                        delta: -5,
                        disabled: !session.lockScreenState.canDecrementDuration
                    )
                    Spacer()
                    durationButton(
                        symbol: "plus",
                        label: "Increase time by 5 seconds",
                        delta: 5
                    )
                }
            }
        } else {
            HStack(spacing: 20) {
                durationButton(
                    symbol: "minus",
                    label: "Decrease time by 5 seconds",
                    delta: -5,
                    disabled: !session.lockScreenState.canDecrementDuration
                )
                durationValue(session)
                durationButton(
                    symbol: "plus",
                    label: "Increase time by 5 seconds",
                    delta: 5
                )
            }
        }
    }

    private func restCorrectionPanel(_ session: WorkoutRoutineSession) -> some View {
        DisclosureGroup(isExpanded: $showRestCorrection) {
            VStack(spacing: 16) {
                progressEditor(session)
                if session.lockScreenState.exerciseKind == .weighted {
                    Divider()
                        .overlay(DamSetDesign.steelMuted.opacity(0.7))
                    weightEditor(session)
                }
                Divider()
                    .overlay(DamSetDesign.steelMuted.opacity(0.7))
                undoSetButton
            }
            .padding(.top, 14)
        } label: {
            HStack {
                Label("Correct last set", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DamSetDesign.accent)
                Spacer()
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
        .gymPanel(accent: DamSetDesign.accent.opacity(0.48), cut: 14, padding: 12)
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

    private func durationValue(_ session: WorkoutRoutineSession) -> some View {
        Button {
            beginProgressEntry(
                .duration,
                value: session.lockScreenState.actualDurationSeconds.minuteSecondText
            )
        } label: {
            VStack(spacing: 2) {
                Text(session.lockScreenState.phase == .performingSet ? "Actual time" : "Last set time")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(DamSetDesign.accent)
                Text(session.lockScreenState.actualDurationSeconds.minuteSecondText)
                    .font(.system(size: min(actualNumberSize, 52), weight: .black, design: .default))
                    .fontWidth(.condensed)
                    .foregroundStyle(DamSetDesign.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(minWidth: 112)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Actual time, \(session.lockScreenState.actualDurationSeconds) seconds")
        .accessibilityHint("Enter actual time directly")
    }

    private func durationButton(
        symbol: String,
        label: String,
        delta: Int,
        disabled: Bool = false
    ) -> some View {
        GlassCircleControl(symbol: symbol, label: label) {
            viewModel.adjustDuration(delta)
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

    private func restCard(_ session: WorkoutRoutineSession, compact: Bool) -> some View {
        let state = session.lockScreenState
        let stateColor = state.phase == .readyForNextSet ? DamSetDesign.moss : DamSetDesign.accent

        return VStack(spacing: compact ? 10 : 14) {
            SteelBarDivider(accent: stateColor)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    GymSectionLabel(
                        text: state.phase == .readyForNextSet ? "Rest complete" : "Rest",
                        color: stateColor
                    )
                    Text(state.restRemainingSeconds.minuteSecondText)
                        .font(.system(
                            size: compact ? 54 : min(restTimerSize, 80),
                            weight: .black,
                            design: .default
                        ))
                        .fontWidth(.condensed)
                        .foregroundStyle(stateColor)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 4)

                if let next = session.nextPlannedSet {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("UP NEXT")
                            .font(.caption2.weight(.bold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(next.exerciseName)
                            .font(.headline.weight(.bold))
                            .fontWidth(.condensed)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                        Text(journeyDetail(next))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

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
        .gymPanel(accent: stateColor.opacity(0.80), cut: 18, padding: compact ? 14 : 18)
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
                Text("\(summary.totalSets) sets · \(summary.compactTrainingLoadText)")
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

    private func setsRemaining(in session: WorkoutRoutineSession) -> Int {
        max(0, session.plannedSets.count - session.completedSets.count)
    }

    private func journeyFocusIndex(in session: WorkoutRoutineSession) -> Int {
        let zeroBasedCurrent = max(0, session.currentSetIndex - 1)
        let isResting = session.lockScreenState.phase == .resting
            || session.lockScreenState.phase == .readyForNextSet
        return min(
            isResting ? zeroBasedCurrent + 1 : zeroBasedCurrent,
            max(0, session.plannedSets.count - 1)
        )
    }

    private func journeyState(
        at index: Int,
        in session: WorkoutRoutineSession
    ) -> JourneySetState {
        if index < session.completedSets.count {
            return .completed
        }
        if index == journeyFocusIndex(in: session) {
            return .current
        }
        return .upcoming
    }

    private func journeyDetail(_ planned: PlannedSet) -> String {
        let goal = planned.trackingMode == .duration
            ? planned.targetDurationSeconds.minuteSecondText
            : "\(planned.targetReps) reps"
        guard planned.exerciseKind == .weighted else { return goal }
        return "\(planned.targetWeight.formatted()) kg · \(goal)"
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
        if next.trackingMode == .duration {
            let load = next.exerciseKind == .bodyweight
                ? "bodyweight"
                : "\(next.targetWeight.formatted()) kg"
            return "\(load) · \(next.targetDurationSeconds.minuteSecondText)"
        }
        return next.exerciseKind == .bodyweight
            ? "bodyweight × \(next.targetReps)"
            : "\(next.targetWeight.formatted()) kg × \(next.targetReps)"
    }

    private func targetDescription(_ planned: PlannedSet) -> String {
        if planned.trackingMode == .duration {
            let load = planned.exerciseKind == .bodyweight
                ? "Bodyweight"
                : "\(planned.targetWeight.formatted()) kg"
            return "\(load) · \(planned.targetDurationSeconds.minuteSecondText) · \(planned.restDurationSeconds.minuteSecondText) rest"
        }
        let load = planned.exerciseKind == .bodyweight
            ? "Bodyweight × \(planned.targetReps)"
            : "\(planned.targetWeight.formatted()) kg × \(planned.targetReps)"
        return "\(load) · \(planned.restDurationSeconds.minuteSecondText) rest"
    }

    private func completedSetDescription(_ set: CompletedSet) -> String {
        if set.trackingMode == .duration {
            let load = set.exerciseKind == .bodyweight
                ? "bodyweight"
                : "\(set.actualWeight.formatted()) kg"
            return "\(load) · \(set.actualDurationSeconds.minuteSecondText)"
        }
        return set.exerciseKind == .bodyweight
            ? "bodyweight × \(set.actualReps)"
            : "\(set.actualWeight.formatted()) kg × \(set.actualReps)"
    }

    private func targetValue(for state: LockScreenState) -> String {
        state.trackingMode == .duration
            ? state.targetDurationSeconds.minuteSecondText
            : "\(state.targetReps)"
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
        case .duration:
            guard let value = parsedDurationSeconds(rawValue) else { return }
            viewModel.setDuration(value)
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
        case .duration:
            return parsedDurationSeconds(rawValue) != nil
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
    case duration
    case weight

    var title: String {
        switch self {
        case .reps: "Edit reps"
        case .duration: "Edit time"
        case .weight: "Edit weight"
        }
    }

    var placeholder: String {
        switch self {
        case .reps: "Reps"
        case .duration: "mm:ss"
        case .weight: "Kilograms"
        }
    }

    var message: String {
        switch self {
        case .reps: "Enter the reps completed."
        case .duration: "Enter seconds or mm:ss."
        case .weight: "Enter the weight in kilograms."
        }
    }
}

private func parsedDurationSeconds(_ rawValue: String) -> Int? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
    let seconds: Int?
    if parts.count == 2,
       let minutes = Int(parts[0]),
       let remainder = Int(parts[1]),
       minutes >= 0,
       (0...59).contains(remainder) {
        seconds = minutes * 60 + remainder
    } else {
        seconds = Int(trimmed)
    }
    guard let seconds else { return nil }
    return min(86_400, max(0, seconds))
}

private enum JourneySetState {
    case completed
    case current
    case upcoming
}

private struct JourneySetPill: View {
    let setNumber: Int
    let exerciseName: String
    let detail: String
    let state: JourneySetState

    private var accent: Color {
        switch state {
        case .completed:
            return DamSetDesign.moss
        case .current:
            return DamSetDesign.accent
        case .upcoming:
            return DamSetDesign.steelMuted
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if state == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(accent)
            } else {
                Text("\(setNumber)")
                    .font(.caption2.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(state == .current ? .white : accent)
                    .frame(width: 21, height: 21)
                    .background(state == .current ? accent : .clear, in: Circle())
                    .overlay {
                        Circle().stroke(accent, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(exerciseName)
                    .font(.caption.weight(.bold))
                    .fontWidth(.condensed)
                    .foregroundStyle(state == .upcoming ? .secondary : .primary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minWidth: 126, alignment: .leading)
        .background(
            state == .current ? accent.opacity(0.14) : DamSetDesign.surface.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(state == .upcoming ? 0.35 : 0.85), lineWidth: state == .current ? 1.5 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Set \(setNumber), \(exerciseName), \(detail), \(accessibilityState)"
        )
    }

    private var accessibilityState: String {
        switch state {
        case .completed: "completed"
        case .current: "current"
        case .upcoming: "upcoming"
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
