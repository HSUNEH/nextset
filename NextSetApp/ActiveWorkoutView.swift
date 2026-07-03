import SwiftUI
import Combine
import NextSetCore

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
        .onReceive(restTimer) { now in
            viewModel.tick(now: now)
        }
    }

    private func workoutContent(_ session: WorkoutRoutineSession) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(session.lockScreenState.exerciseName)
                    .font(.title.bold())
                Text("Set \(session.lockScreenState.currentSetIndex) / \(session.lockScreenState.totalPlannedSets)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("Target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(session.lockScreenState.targetReps)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let planned = session.currentPlannedSet {
                    Text("\(planned.targetWeight.formatted()) kg × \(planned.targetReps)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 40) {
                Button { viewModel.adjustReps(-1) } label: {
                    Image(systemName: "minus")
                        .font(.title.bold())
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.lockScreenState.canDecrementReps)
                .accessibilityLabel("Decrease reps")

                Text("\(session.lockScreenState.actualReps)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("Actual reps")

                Button { viewModel.adjustReps(1) } label: {
                    Image(systemName: "plus")
                        .font(.title.bold())
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Increase reps")
            }

            if session.lockScreenState.phase == .performingSet {
                HStack(spacing: 24) {
                    Button { viewModel.adjustWeight(-2.5) } label: {
                        Text("−2.5")
                            .frame(minWidth: 64, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.actualWeight <= 0)
                    .accessibilityLabel("Decrease weight by 2.5 kilograms")

                    VStack(spacing: 2) {
                        Text("Weight")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.actualWeight.formatted()) kg")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .accessibilityLabel("Actual weight")
                    }

                    Button { viewModel.adjustWeight(2.5) } label: {
                        Text("+2.5")
                            .frame(minWidth: 64, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Increase weight by 2.5 kilograms")
                }
            }

            if session.lockScreenState.phase == .resting || session.lockScreenState.phase == .readyForNextSet {
                RestStatusView(state: session.lockScreenState)
                Button("Next Set") { viewModel.advanceToNextSet() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else if session.lockScreenState.phase == .completed {
                VStack(spacing: 12) {
                    Label("Workout complete", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    if let summary = viewModel.lastSummary {
                        Text("\(summary.totalSets) sets · \(summary.totalVolume.formatted()) kg volume")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Done") { viewModel.closeWorkout() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            } else {
                Button("Set Done") { viewModel.completeSet() }
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

private struct RestStatusView: View {
    let state: LockScreenState

    var body: some View {
        VStack(spacing: 6) {
            Text("Rest")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(format(seconds: state.restRemainingSeconds))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let resumeAt = state.resumeAt {
                Text("Ready at \(resumeAt.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
