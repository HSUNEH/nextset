import SwiftUI
import DamSetCore

struct RoutineSetupView: View {
    let routine: RoutineTemplate
    @Bindable var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    @State private var draftSets: [EditablePlannedSet]

    init(routine: RoutineTemplate, viewModel: WorkoutViewModel) {
        self.routine = routine
        self.viewModel = viewModel
        _draftName = State(initialValue: routine.routineName)
        _draftSets = State(initialValue: routine.plannedSets.map(EditablePlannedSet.init(planned:)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                setsEditor
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 108)
        }
        .background(DamSetDesign.appGradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
        }
        .navigationTitle("Setup")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addSet()
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
            }
        }
        .tint(DamSetDesign.accent)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S PLAN")
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.64))
            TextField("Routine name", text: $draftName)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                MetricPill(title: "Sets", value: "\(draftSets.count)", symbol: "list.number")
                MetricPill(title: "Rest", value: "\(totalRestMinutes)", symbol: "timer")
            }
            Text("Edit the set list first. Start only when today's workout matches what you want to do.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface(cornerRadius: 32)
    }

    private var setsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sets", subtitle: "Exercise · kg · reps · rest")
            ForEach($draftSets) { $set in
                EditableSetCard(
                    set: $set,
                    canDelete: draftSets.count > 1,
                    duplicate: { duplicate(set) },
                    delete: { delete(set) }
                )
            }
            Button {
                addSet()
            } label: {
                Label("Add another set", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            .cardSurface(cornerRadius: 22)
        }
    }

    private var startButton: some View {
        Button {
            viewModel.start(makeRoutine())
            dismiss()
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Start Workout")
            }
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canStart)
        .accessibilityLabel("Start workout with edited set plan")
    }

    private var canStart: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draftSets.contains { !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var totalRestMinutes: String {
        let seconds = draftSets.reduce(0) { $0 + $1.restSeconds }
        return "\(seconds / 60)m"
    }

    private func makeRoutine() -> RoutineTemplate {
        let validSets = draftSets
            .filter { !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { index, set in
                PlannedSet(
                    setId: "\(routine.routineId)-setup-\(index + 1)-\(set.id.uuidString)",
                    exerciseName: set.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines),
                    targetWeight: set.targetWeight,
                    targetReps: set.targetReps,
                    restDurationSeconds: set.restSeconds,
                    manuallyAdded: set.manuallyAdded
                )
            }

        return RoutineTemplate(
            routineId: "\(routine.routineId)-custom-\(UUID().uuidString)",
            routineName: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            plannedSets: validSets
        )
    }

    private func addSet() {
        if let last = draftSets.last {
            duplicate(last)
        } else {
            draftSets.append(EditablePlannedSet())
        }
    }

    private func duplicate(_ set: EditablePlannedSet) {
        var copy = set
        copy.id = UUID()
        copy.manuallyAdded = true
        draftSets.append(copy)
    }

    private func delete(_ set: EditablePlannedSet) {
        guard draftSets.count > 1 else { return }
        draftSets.removeAll { $0.id == set.id }
    }
}

private struct EditableSetCard: View {
    @Binding var set: EditablePlannedSet
    let canDelete: Bool
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Exercise", text: $set.exerciseName)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                    Button("Delete", systemImage: "trash", role: .destructive) { delete() }
                        .disabled(!canDelete)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                }
            }

            HStack(spacing: 10) {
                StepperField(
                    title: "kg",
                    value: weightText,
                    decrement: { set.targetWeight = max(0, set.targetWeight - 2.5) },
                    increment: { set.targetWeight += 2.5 }
                )
                StepperField(
                    title: "reps",
                    value: "\(set.targetReps)",
                    decrement: { set.targetReps = max(0, set.targetReps - 1) },
                    increment: { set.targetReps += 1 }
                )
                StepperField(
                    title: "rest",
                    value: restText,
                    decrement: { set.restSeconds = max(0, set.restSeconds - 15) },
                    increment: { set.restSeconds += 15 }
                )
            }
        }
        .cardSurface(cornerRadius: 24)
    }

    private var weightText: String {
        "\(set.targetWeight.formatted(.number.precision(.fractionLength(0...1))))"
    }

    private var restText: String {
        let minutes = set.restSeconds / 60
        let seconds = set.restSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct StepperField: View {
    let title: String
    let value: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                Button(action: decrement) {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                }
                Button(action: increment) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct EditablePlannedSet: Identifiable, Equatable {
    var id: UUID
    var exerciseName: String
    var targetWeight: Double
    var targetReps: Int
    var restSeconds: Int
    var manuallyAdded: Bool

    init(
        id: UUID = UUID(),
        exerciseName: String = "New Exercise",
        targetWeight: Double = 20,
        targetReps: Int = 8,
        restSeconds: Int = 90,
        manuallyAdded: Bool = true
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.targetWeight = max(0, targetWeight)
        self.targetReps = max(0, targetReps)
        self.restSeconds = max(0, restSeconds)
        self.manuallyAdded = manuallyAdded
    }

    init(planned: PlannedSet) {
        self.init(
            exerciseName: planned.exerciseName,
            targetWeight: planned.targetWeight,
            targetReps: planned.targetReps,
            restSeconds: planned.restDurationSeconds,
            manuallyAdded: planned.manuallyAdded
        )
    }
}
