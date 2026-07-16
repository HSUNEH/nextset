import SwiftUI
import DamSetCore

struct RoutineSetupView: View {
    let routine: RoutineTemplate
    @Bindable var viewModel: WorkoutViewModel
    let onChooseWorkout: (RoutineTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftEmoji: String
    @State private var draftName: String
    @State private var draftExercises: [EditableExercisePlan]
    @State private var routinePendingChooser: RoutineTemplate?
    @State private var showDeleteConfirmation = false

    init(
        routine: RoutineTemplate,
        viewModel: WorkoutViewModel,
        onChooseWorkout: @escaping (RoutineTemplate) -> Void
    ) {
        self.routine = routine
        self.viewModel = viewModel
        self.onChooseWorkout = onChooseWorkout
        _draftEmoji = State(initialValue: routine.emoji ?? "🏋️")
        _draftName = State(initialValue: routine.routineName)
        _draftExercises = State(
            initialValue: routine.plannedSets
                .groupedExercisePlans()
                .map(EditableExercisePlan.init(plan:))
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                headerCard
                exercisesEditor
                deleteRoutineButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .background(DamSetDesign.screenBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(DamSetDesign.screenBackground.opacity(0.96))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DamSetDesign.steelMuted)
                        .frame(height: 1)
                }
        }
        .navigationTitle("Setup")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Save") {
                    saveAndDismiss()
                }
                .disabled(!canStart)
                Button {
                    addExercise()
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            }
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
        .onDisappear {
            guard let routinePendingChooser else { return }
            self.routinePendingChooser = nil
            onChooseWorkout(routinePendingChooser)
        }
        .confirmationDialog("Delete routine?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) {
                guard viewModel.deleteRoutine(routine) else { return }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(routine.routineName) will be removed from your routines.")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TextField("🏋️", text: $draftEmoji)
                    .font(.system(size: 30))
                    .multilineTextAlignment(.center)
                    .frame(width: 54, height: 54)
                    .background(DamSetDesign.controlFill, in: RoundedRectangle(cornerRadius: 13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(DamSetDesign.steelMuted, lineWidth: 1)
                    }
                    .accessibilityLabel("Routine emoji")
                TextField("Routine name", text: $draftName)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .tint(DamSetDesign.accent)
            }
            Text("\(totalSetCount) sets · \(totalRestMinutes) rest")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .cardSurface(cornerRadius: 20)
    }

    private var exercisesEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Exercises", subtitle: "Weight · reps/set · sets · rest")
            ForEach($draftExercises) { $exercise in
                EditableExerciseCard(
                    exercise: $exercise,
                    showsExerciseNameError: exercise.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    canDelete: draftExercises.count > 1,
                    canMoveUp: draftExercises.first?.id != exercise.id,
                    canMoveDown: draftExercises.last?.id != exercise.id,
                    moveUp: { move(exercise, by: -1) },
                    moveDown: { move(exercise, by: 1) },
                    duplicate: { duplicate(exercise) },
                    delete: { delete(exercise) }
                )
            }
            Button {
                addExercise()
            } label: {
                Label("Add exercise", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DamSetDesign.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .background(DamSetDesign.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        DamSetDesign.steelMuted,
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            }
        }
    }

    private var deleteRoutineButton: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Delete Routine", systemImage: "trash")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .tint(DamSetDesign.accent)
    }

    private var startButton: some View {
        Button {
            saveAndStart()
        } label: {
            Text("Save & Choose Workout")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.vertical, 4)
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .disabled(!canStart)
        .accessibilityLabel("Save routine and choose today's exercises")
    }

    private var canStart: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftExercises.isEmpty &&
        draftExercises.allSatisfy {
            !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.setCount > 0
        }
    }

    private var totalSetCount: Int {
        draftExercises.reduce(0) { $0 + $1.setCount }
    }

    private var totalRestMinutes: String {
        let expandedSets = draftExercises.map(\.plan).expandedPlannedSets()
        let seconds = expandedSets.dropLast().reduce(0) { $0 + $1.restDurationSeconds }
        return "\(seconds / 60)m"
    }

    private func makeRoutine() -> RoutineTemplate? {
        guard canStart else { return nil }

        var plans = draftExercises.map(\.plan)
        for index in plans.indices {
            plans[index].exerciseName = plans[index].exerciseName
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return RoutineTemplate(
            routineId: routine.routineId,
            routineName: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            emoji: normalizedEmoji,
            plannedSets: plans.expandedPlannedSets()
        )
    }

    private var normalizedEmoji: String? {
        let trimmed = draftEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first)
    }

    private func saveAndDismiss() {
        guard let routine = makeRoutine(), viewModel.saveRoutine(routine) else { return }
        dismiss()
    }

    private func saveAndStart() {
        guard let editedRoutine = makeRoutine() else { return }
        guard viewModel.saveRoutine(editedRoutine) else { return }
        routinePendingChooser = editedRoutine
        dismiss()
    }

    private func addExercise() {
        draftExercises.append(EditableExercisePlan())
    }

    private func duplicate(_ exercise: EditableExercisePlan) {
        draftExercises.append(exercise.duplicated())
    }

    private func move(_ exercise: EditableExercisePlan, by offset: Int) {
        guard let sourceIndex = draftExercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard draftExercises.indices.contains(destinationIndex) else { return }

        withAnimation(.snappy) {
            draftExercises.swapAt(sourceIndex, destinationIndex)
        }
    }

    private func delete(_ exercise: EditableExercisePlan) {
        guard draftExercises.count > 1 else { return }
        draftExercises.removeAll { $0.id == exercise.id }
    }
}

private struct EditableExerciseCard: View {
    @Binding var exercise: EditableExercisePlan
    let showsExerciseNameError: Bool
    let canDelete: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Exercise", text: $exercise.exerciseName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .tint(DamSetDesign.accent)
                Spacer()
                Menu {
                    Section {
                        Button("Move Up", systemImage: "arrow.up") { moveUp() }
                            .disabled(!canMoveUp)
                        Button("Move Down", systemImage: "arrow.down") { moveDown() }
                            .disabled(!canMoveDown)
                    }
                    Section {
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete() }
                            .disabled(!canDelete)
                    }
                } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DamSetDesign.steel)
                            .frame(width: 44, height: 44)
                            .background(DamSetDesign.controlFill, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(DamSetDesign.steelMuted, lineWidth: 1)
                            }
                }
            }

            if showsExerciseNameError {
                Label("Exercise name is required", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DamSetDesign.amber)
                    .accessibilityLabel("Error: Exercise name is required")
            }

            Picker("Exercise type", selection: $exercise.exerciseKind) {
                Label("Bodyweight", systemImage: "figure.strengthtraining.functional")
                    .tag(ExerciseKind.bodyweight)
                Label("Weighted", systemImage: "dumbbell.fill")
                    .tag(ExerciseKind.weighted)
            }
            .pickerStyle(.segmented)

            if dynamicTypeSize.isAccessibilitySize {
                if exercise.exerciseKind == .weighted {
                    weightField
                    Divider().overlay(DamSetDesign.steelMuted)
                }
                repsField
                Divider().overlay(DamSetDesign.steelMuted)
                setsField
                Divider().overlay(DamSetDesign.steelMuted)
                restField
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 96), spacing: 12),
                        GridItem(.flexible(minimum: 96), spacing: 12)
                    ],
                    spacing: 16
                ) {
                    if exercise.exerciseKind == .weighted {
                        weightField
                    }
                    repsField
                    setsField
                    restField
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .cardSurface(
            cornerRadius: 20,
            accent: showsExerciseNameError ? DamSetDesign.amber : nil
        )
    }

    private var weightField: some View {
        StepperField(
            title: "Weight (kg)",
            value: weightText,
            decrement: { exercise.targetWeight = max(0, exercise.targetWeight - 2.5) },
            increment: { exercise.targetWeight = min(9_999, exercise.targetWeight + 2.5) },
            directEntry: updateWeight
        )
    }

    private var repsField: some View {
        StepperField(
            title: "Reps / set",
            value: "\(exercise.targetReps)",
            decrement: { exercise.targetReps = max(0, exercise.targetReps - 1) },
            increment: { exercise.targetReps = min(999, exercise.targetReps + 1) },
            directEntry: updateReps
        )
    }

    private var setsField: some View {
        StepperField(
            title: "Sets",
            value: "\(exercise.setCount)",
            decrement: { exercise.setCount = max(1, exercise.setCount - 1) },
            increment: { exercise.setCount = min(99, exercise.setCount + 1) },
            directEntry: updateSets
        )
    }

    private var restField: some View {
        StepperField(
            title: "Rest after set",
            value: exercise.restSeconds.minuteSecondText,
            decrement: { exercise.restSeconds = max(0, exercise.restSeconds - 15) },
            increment: { exercise.restSeconds = min(86_400, exercise.restSeconds + 15) },
            directEntry: updateRest
        )
    }

    private var weightText: String {
        "\(exercise.targetWeight.formatted(.number.precision(.fractionLength(0...1))))"
    }

    private func updateWeight(_ rawValue: String) {
        guard let value = parsedWeight(rawValue), value.isFinite else { return }
        exercise.targetWeight = min(9_999, max(0, value))
    }

    private func parsedWeight(_ rawValue: String) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func updateReps(_ rawValue: String) {
        guard let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        exercise.targetReps = min(999, max(0, value))
    }

    private func updateSets(_ rawValue: String) {
        guard let value = Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        exercise.setCount = min(99, max(1, value))
    }

    private func updateRest(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        let seconds: Int?
        if parts.count == 2, let minutes = Int(parts[0]), let remainder = Int(parts[1]) {
            seconds = min(max(0, minutes), 1_440) * 60 + min(max(0, remainder), 59)
        } else {
            seconds = Int(trimmed)
        }
        guard let seconds else { return }
        exercise.restSeconds = min(86_400, max(0, seconds))
    }
}

private struct StepperField: View {
    let title: String
    let value: String
    let decrement: () -> Void
    let increment: () -> Void
    let directEntry: (String) -> Void
    @State private var showsDirectEntry = false
    @State private var draftValue = ""

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button {
                draftValue = value
                showsDirectEntry = true
            } label: {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(minHeight: 30)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("\(title) \(value)")
            .accessibilityHint("Enter a value directly")
            HStack(spacing: 0) {
                stepButton(symbol: "minus", action: decrement)
                stepButton(symbol: "plus", action: increment)
            }
        }
        .frame(maxWidth: .infinity)
        .alert("Edit \(title)", isPresented: $showsDirectEntry) {
            TextField(value, text: $draftValue)
            Button("Save") { directEntry(draftValue) }
                .disabled(!isValidDraft)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(title == "Rest after set" ? "Enter seconds or mm:ss." : "Enter a number.")
        }
    }

    private var isValidDraft: Bool {
        let trimmed = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch title {
        case "Weight (kg)":
            let formatter = NumberFormatter()
            formatter.locale = .current
            formatter.numberStyle = .decimal
            if let value = formatter.number(from: trimmed)?.doubleValue {
                return value.isFinite && value >= 0
            }
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
            return Double(normalized).map { $0.isFinite && $0 >= 0 } ?? false
        case "Reps / set":
            return Int(trimmed).map { $0 >= 0 } ?? false
        case "Sets":
            return Int(trimmed).map { $0 >= 1 } ?? false
        case "Rest after set":
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count == 2,
               let minutes = Int(parts[0]),
               let seconds = Int(parts[1]) {
                return minutes >= 0 && (0...59).contains(seconds)
            }
            return Int(trimmed).map { $0 >= 0 } ?? false
        default:
            return false
        }
    }

    private func stepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DamSetDesign.accent)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(GymCompactStepperButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel("\(symbol == "minus" ? "Decrease" : "Increase") \(title)")
    }
}

private struct EditableExercisePlan: Identifiable, Equatable {
    var plan: RoutineExercisePlan
    private var lastWeightedTargetWeight: Double

    var id: String { plan.id }

    var exerciseName: String {
        get { plan.exerciseName }
        set { plan.exerciseName = newValue }
    }

    var exerciseKind: ExerciseKind {
        get { plan.exerciseKind }
        set {
            guard newValue != plan.exerciseKind else { return }
            if newValue == .bodyweight {
                lastWeightedTargetWeight = plan.targetWeight
                plan.exerciseKind = .bodyweight
            } else {
                plan.exerciseKind = .weighted
                plan.targetWeight = lastWeightedTargetWeight
            }
        }
    }

    var targetWeight: Double {
        get { plan.targetWeight }
        set {
            let finiteWeight = newValue.isFinite ? newValue : 0
            plan.targetWeight = min(9_999, max(0, finiteWeight))
            if plan.exerciseKind == .weighted {
                lastWeightedTargetWeight = plan.targetWeight
            }
        }
    }

    var targetReps: Int {
        get { plan.targetReps }
        set { plan.targetReps = min(999, max(0, newValue)) }
    }

    var setCount: Int {
        get { plan.setCount }
        set { plan.setCount = min(99, max(1, newValue)) }
    }

    var restSeconds: Int {
        get { plan.restDurationSeconds }
        set { plan.restDurationSeconds = min(86_400, max(0, newValue)) }
    }

    init(
        exerciseName: String = "New Exercise",
        exerciseKind: ExerciseKind = .weighted,
        targetWeight: Double = 20,
        targetReps: Int = 8,
        setCount: Int = 3,
        restSeconds: Int = 90,
        manuallyAdded: Bool = true
    ) {
        let normalizedWeight = min(9_999, max(0, targetWeight.isFinite ? targetWeight : 0))
        self.plan = RoutineExercisePlan(
            exerciseName: exerciseName,
            exerciseKind: exerciseKind,
            targetWeight: normalizedWeight,
            targetReps: targetReps,
            setCount: setCount,
            restDurationSeconds: restSeconds,
            manuallyAdded: manuallyAdded
        )
        self.lastWeightedTargetWeight = exerciseKind == .weighted ? normalizedWeight : 20
    }

    init(plan: RoutineExercisePlan) {
        self.plan = plan
        self.lastWeightedTargetWeight = plan.exerciseKind == .weighted ? plan.targetWeight : 20
    }

    func duplicated() -> EditableExercisePlan {
        var copy = EditableExercisePlan(
            exerciseName: exerciseName,
            exerciseKind: exerciseKind,
            targetWeight: targetWeight,
            targetReps: targetReps,
            setCount: setCount,
            restSeconds: restSeconds,
            manuallyAdded: true
        )
        copy.lastWeightedTargetWeight = lastWeightedTargetWeight
        return copy
    }
}
