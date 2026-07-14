import SwiftUI
import Combine
import DamSetCore

struct ActiveWorkoutView: View {
    @Bindable var viewModel: WorkoutViewModel
    @State private var showEndConfirmation = false
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
            .background(DamSetDesign.screenBackground.ignoresSafeArea())
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("End", role: .destructive) {
                        if viewModel.activeSession?.sessionStatus == .completed {
                            viewModel.closeWorkout()
                        } else {
                            showEndConfirmation = true
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.repeatCurrentSet()
                    } label: {
                        Label("Add Set", systemImage: "plus")
                    }
                    .disabled(viewModel.activeSession?.sessionStatus == .completed)
                }
            }
            .confirmationDialog("End workout without saving?", isPresented: $showEndConfirmation, titleVisibility: .visible) {
                Button("End Workout", role: .destructive) { viewModel.closeWorkout() }
                Button("Keep Going", role: .cancel) {}
            }
        }
        .tint(DamSetDesign.accent)
        .onReceive(restTimer) { now in
            viewModel.tick(now: now)
        }
    }

    private func workoutContent(_ session: WorkoutRoutineSession) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                workoutHeader(session)
                workoutFlowCard(session)
                targetCard(session)
                repsControl(session)

                if session.lockScreenState.phase == .performingSet {
                    weightCard(session)
                    setDoneButton
                } else if session.lockScreenState.phase == .resting || session.lockScreenState.phase == .readyForNextSet {
                    restCard(session.lockScreenState)
                } else if session.lockScreenState.phase == .completed {
                    completionCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func workoutHeader(_ session: WorkoutRoutineSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.routineName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(session.lockScreenState.exerciseName)
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
                Text("Set \(session.lockScreenState.currentSetIndex)/\(session.lockScreenState.totalPlannedSets)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DamSetDesign.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(DamSetDesign.accent)
            }

            ProgressView(value: progress(for: session))
                .tint(DamSetDesign.accent)
                .accessibilityLabel("Workout progress")
        }
        .cardSurface(cornerRadius: 20)
    }

    private func workoutFlowCard(_ session: WorkoutRoutineSession) -> some View {
        HStack(spacing: 12) {
            FlowMetric(
                title: "Completed",
                value: "\(session.completedSets.count)",
                caption: "sets",
                symbol: "checkmark.circle.fill",
                color: DamSetDesign.moss
            )

            Divider()

            FlowMetric(
                title: session.lockScreenState.phase == .resting ? "Resting" : "Now",
                value: phaseValue(for: session.lockScreenState),
                caption: phaseCaption(for: session),
                symbol: phaseSymbol(for: session.lockScreenState.phase),
                color: phaseColor(for: session.lockScreenState.phase)
            )

            Divider()

            FlowMetric(
                title: "Next",
                value: session.nextPlannedSet?.exerciseName ?? "Done",
                caption: nextSetCaption(for: session),
                symbol: "forward.fill",
                color: .secondary
            )
        }
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: 20)
    }

    private func targetCard(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 4) {
            Text("Target reps")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(session.lockScreenState.targetReps)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
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
        .cardSurface(cornerRadius: 20)
    }

    private func repsControl(_ session: WorkoutRoutineSession) -> some View {
        HStack(spacing: 20) {
            GlassCircleControl(symbol: "minus", label: "Decrease reps") {
                viewModel.adjustReps(-1)
            }
            .disabled(!session.lockScreenState.canDecrementReps)

            VStack(spacing: 2) {
                Text("Did")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(session.lockScreenState.actualReps)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Actual reps")
            }
            .frame(minWidth: 84)

            GlassCircleControl(symbol: "plus", label: "Increase reps") {
                viewModel.adjustReps(1)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: 20)
    }

    private func weightCard(_ session: WorkoutRoutineSession) -> some View {
        HStack(spacing: 12) {
            Button { viewModel.adjustWeight(-2.5) } label: {
                Text("−2.5")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 64, minHeight: 40)
            }
            .buttonStyle(.glass)
            .tint(DamSetDesign.accent)
            .disabled(viewModel.actualWeight <= 0)
            .accessibilityLabel("Decrease weight by 2.5 kilograms")

            VStack(spacing: 2) {
                Text("Actual weight")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.actualWeight.formatted()) kg")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .accessibilityLabel("Actual weight")
            }
            .frame(maxWidth: .infinity)

            Button { viewModel.adjustWeight(2.5) } label: {
                Text("+2.5")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 64, minHeight: 40)
            }
            .buttonStyle(.glass)
            .tint(DamSetDesign.accent)
            .accessibilityLabel("Increase weight by 2.5 kilograms")
        }
        .cardSurface(cornerRadius: 20)
    }

    private var setDoneButton: some View {
        Button {
            viewModel.completeSet()
        } label: {
            Text("Set Done")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.glassProminent)
        .tint(DamSetDesign.accent)
        .accessibilityLabel("Complete current set")
    }

    private func restCard(_ state: LockScreenState) -> some View {
        VStack(spacing: 14) {
            Label("Rest", systemImage: "timer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(state.restRemainingSeconds.minuteSecondText)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let resumeAt = state.resumeAt {
                Text("Auto-starts at \(resumeAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Next set starts automatically when rest ends")
                .font(.footnote.weight(.medium))
                .foregroundStyle(DamSetDesign.accent)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: 20)
    }

    private var completionCard: some View {
        VStack(spacing: 14) {
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
            Button { viewModel.closeWorkout() } label: {
                Text("Done")
                    .font(.headline)
                    .frame(minWidth: 140, minHeight: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(DamSetDesign.accent)
        }
        .frame(maxWidth: .infinity)
        .cardSurface(cornerRadius: 20)
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
            return DamSetDesign.amber
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
}

private struct FlowMetric: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
