import SwiftUI
import DamSetCore

struct WorkoutRecordEditView: View {
    let original: WorkoutSummary
    let onSave: (WorkoutSummary) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var workoutEndTime: Date
    @State private var sets: [EditableCompletedSet]
    @State private var showsSaveFailure = false

    init(summary: WorkoutSummary, onSave: @escaping (WorkoutSummary) -> Bool) {
        original = summary
        self.onSave = onSave
        _workoutEndTime = State(initialValue: summary.workoutEndTime)
        _sets = State(initialValue: summary.completedSets.map(EditableCompletedSet.init))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Routine", value: original.routineName)
                    DatePicker(
                        "Workout date",
                        selection: $workoutEndTime,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Workout")
                } footer: {
                    Text("Changing the date moves this record on the calendar while keeping its original duration.")
                }

                Section {
                    ForEach($sets) { $set in
                        CompletedSetEditorCard(
                            set: $set,
                            canDelete: sets.count > 1,
                            onDelete: { delete(set.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                } header: {
                    Text("Completed Sets")
                } footer: {
                    Text("Edit load or reps. Saving recalculates total sets, volume, and every progress graph.")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(DamSetDesign.screenBackground)
            .navigationTitle("Edit Workout")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .alert("Couldn’t save changes", isPresented: $showsSaveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your draft is still here. Please try again.")
        }
    }

    private var canSave: Bool {
        !sets.isEmpty &&
        sets.allSatisfy {
            $0.actualWeight.isFinite &&
            (0...EditableCompletedSet.maximumWeight).contains($0.actualWeight) &&
            (0...EditableCompletedSet.maximumReps).contains($0.actualReps)
        }
    }

    private func delete(_ id: UUID) {
        guard sets.count > 1 else { return }
        withAnimation(.snappy) {
            sets.removeAll { $0.id == id }
        }
    }

    private func save() {
        guard canSave else { return }
        let timeShift = workoutEndTime.timeIntervalSince(original.workoutEndTime)
        let completedSets = sets.map { draft in
            CompletedSet(
                setId: draft.sourceSetId,
                exerciseName: draft.exerciseName,
                exerciseKind: draft.exerciseKind,
                actualWeight: draft.actualWeight,
                actualReps: draft.actualReps,
                completedAt: draft.completedAt.addingTimeInterval(timeShift)
            )
        }

        var updated = original.replacingCompletedSets(completedSets)
        updated.workoutStartTime = original.workoutStartTime.addingTimeInterval(timeShift)
        updated.workoutEndTime = workoutEndTime

        guard onSave(updated) else {
            showsSaveFailure = true
            return
        }
        dismiss()
    }
}

private struct CompletedSetEditorCard: View {
    @Binding var set: EditableCompletedSet
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(set.exerciseKind == .bodyweight ? "Bodyweight" : "Weighted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
                .accessibilityLabel("Delete completed set")
                .accessibilityHint(canDelete ? "Removes this set from the workout record" : "Delete the workout to remove its final set")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    loadField
                    repsField
                }
                VStack(spacing: 12) {
                    loadField
                    repsField
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var loadField: some View {
        if set.exerciseKind == .weighted {
            VStack(alignment: .leading, spacing: 5) {
                Text("KG")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                TextField(
                    "KG",
                    value: $set.actualWeight,
                    format: .number.precision(.fractionLength(0...1))
                )
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(minHeight: 44)
                .decimalInputKeyboard()
                .onChange(of: set.actualWeight) { _, value in
                    let finiteValue = value.isFinite ? value : 0
                    set.actualWeight = min(
                        max(0, finiteValue),
                        EditableCompletedSet.maximumWeight
                    )
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text("LOAD")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("Bodyweight")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    private var repsField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("REPS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            TextField("REPS", value: $set.actualReps, format: .number)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(minHeight: 44)
                .integerInputKeyboard()
                .onChange(of: set.actualReps) { _, value in
                    set.actualReps = min(
                        max(0, value),
                        EditableCompletedSet.maximumReps
                    )
                }
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func decimalInputKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder
    func integerInputKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}

private struct EditableCompletedSet: Identifiable {
    static let maximumWeight = 2_000.0
    static let maximumReps = 9_999

    var id = UUID()
    var sourceSetId: String
    var exerciseName: String
    var exerciseKind: ExerciseKind
    var actualWeight: Double
    var actualReps: Int
    var completedAt: Date

    init(_ set: CompletedSet) {
        sourceSetId = set.setId
        exerciseName = set.exerciseName
        exerciseKind = set.exerciseKind
        actualWeight = set.actualWeight
        actualReps = set.actualReps
        completedAt = set.completedAt
    }
}
