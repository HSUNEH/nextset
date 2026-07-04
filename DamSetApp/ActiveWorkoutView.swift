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
            .background(DamSetDesign.appGradient.ignoresSafeArea())
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
            VStack(spacing: 12) {
                workoutHeader(session)
                workoutFlowCard(session)
                targetCard(session)
                repsControl(session)

                if session.lockScreenState.phase == .performingSet {
                    weightCard(session)
                    setDoneButton
                } else if session.lockScreenState.phase == .resting || session.lockScreenState.phase == .readyForDamSet {
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.routineName)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.62))
                    Text(session.lockScreenState.exerciseName)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
                Text("Set \(session.lockScreenState.currentSetIndex)/\(session.lockScreenState.totalPlannedSets)")
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }

            ProgressView(value: progress(for: session))
                .tint(DamSetDesign.mint)
                .accessibilityLabel("Workout progress")
        }
        .nextSetCard(cornerRadius: 30)
    }

    private func workoutFlowCard(_ session: WorkoutRoutineSession) -> some View {
        HStack(spacing: 12) {
            FlowMetric(
                title: "Completed",
                value: "\(session.completedSets.count)",
                caption: "sets",
                symbol: "checkmark.circle.fill",
                color: DamSetDesign.mint
            )

            Divider()
                .overlay(.white.opacity(0.12))

            FlowMetric(
                title: session.lockScreenState.phase == .resting ? "Resting" : "Now",
                value: phaseValue(for: session.lockScreenState),
                caption: phaseCaption(for: session),
                symbol: phaseSymbol(for: session.lockScreenState.phase),
                color: phaseColor(for: session.lockScreenState.phase)
            )

            Divider()
                .overlay(.white.opacity(0.12))

            FlowMetric(
                title: "Next",
                value: nextExerciseName(after: session) ?? "Done",
                caption: nextSetCaption(after: session),
                symbol: "forward.fill",
                color: .white.opacity(0.82)
            )
        }
        .frame(maxWidth: .infinity)
        .nextSetCard(cornerRadius: 26)
    }

    private func targetCard(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 4) {
            Text("TARGET REPS")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            Text("\(session.lockScreenState.targetReps)")
                .font(.system(size: 68, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let planned = session.currentPlannedSet {
                Text("\(planned.targetWeight.formatted()) kg × \(planned.targetReps) · \(format(seconds: planned.restDurationSeconds)) rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let last = session.completedSets.last {
                Label("Last: \(last.exerciseName) · \(last.actualWeight.formatted()) kg × \(last.actualReps)", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .nextSetCard(cornerRadius: 30)
    }

    private func repsControl(_ session: WorkoutRoutineSession) -> some View {
        HStack(spacing: 16) {
            CircleControl(symbol: "minus", label: "Decrease reps") {
                viewModel.adjustReps(-1)
            }
            .disabled(!session.lockScreenState.canDecrementReps)

            VStack(spacing: 4) {
                Text("DID")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text("\(session.lockScreenState.actualReps)")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Actual reps")
            }
            .frame(minWidth: 84)

            CircleControl(symbol: "plus", label: "Increase reps") {
                viewModel.adjustReps(1)
            }
        }
        .frame(maxWidth: .infinity)
        .nextSetCard(cornerRadius: 30)
    }

    private func weightCard(_ session: WorkoutRoutineSession) -> some View {
        HStack(spacing: 16) {
            Button { viewModel.adjustWeight(-2.5) } label: {
                Text("−2.5")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 72, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.actualWeight <= 0)
            .accessibilityLabel("Decrease weight by 2.5 kilograms")

            VStack(spacing: 3) {
                Text("ACTUAL WEIGHT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("\(viewModel.actualWeight.formatted()) kg")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .accessibilityLabel("Actual weight")
            }
            .frame(maxWidth: .infinity)

            Button { viewModel.adjustWeight(2.5) } label: {
                Text("+2.5")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 72, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Increase weight by 2.5 kilograms")
        }
        .nextSetCard(cornerRadius: 26)
    }

    private var setDoneButton: some View {
        Button("Set Done") { viewModel.completeSet() }
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 58)
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel("Complete current set")
    }

    private func restCard(_ state: LockScreenState) -> some View {
        VStack(spacing: 18) {
            Label("Rest", systemImage: "timer")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(format(seconds: state.restRemainingSeconds))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let resumeAt = state.resumeAt {
                Text("Auto-starts at \(resumeAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Next set starts automatically when rest ends")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DamSetDesign.mint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .nextSetCard(cornerRadius: 30)
    }

    private var completionCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("Workout complete")
                .font(.title2.bold())
            if let summary = viewModel.lastSummary {
                Text("\(summary.totalSets) sets · \(summary.totalVolume.formatted()) kg volume")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Done") { viewModel.closeWorkout() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .nextSetCard(cornerRadius: 30)
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
        case .resting, .readyForDamSet:
            return format(seconds: state.restRemainingSeconds)
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
        case .readyForDamSet:
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
        case .readyForDamSet:
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
            return DamSetDesign.orange
        case .readyForDamSet:
            return DamSetDesign.mint
        case .completed:
            return .green
        }
    }

    private func nextExerciseName(after session: WorkoutRoutineSession) -> String? {
        let nextIndex = session.currentSetIndex
        guard session.plannedSets.indices.contains(nextIndex) else { return nil }
        return session.plannedSets[nextIndex].exerciseName
    }

    private func nextSetCaption(after session: WorkoutRoutineSession) -> String {
        let nextIndex = session.currentSetIndex
        guard session.plannedSets.indices.contains(nextIndex) else { return "finish" }
        let next = session.plannedSets[nextIndex]
        return "\(next.targetWeight.formatted()) kg × \(next.targetReps)"
    }

    private func format(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct FlowMetric: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
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

private struct CircleControl: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title.bold())
                .frame(width: 58, height: 58)
                .background(DamSetDesign.activeGradient, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
