import SwiftUI
import DamSetCore

struct RoutineSetupView: View {
    let routine: RoutineTemplate
    @Bindable var viewModel: WorkoutViewModel
    let onChooseWorkout: (RoutineTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftEmoji: String
    @State private var draftName: String
    @State private var draftDefaultRestSeconds: Int
    @State private var draftExercises: [EditableExercisePlan]
    @State private var exerciseEditor: ExerciseEditorContext?
    @State private var routinePendingChooser: RoutineTemplate?
    @State private var showDeleteConfirmation = false
    @State private var showRoutineRestEntry = false
    @State private var routineRestDraft = ""
#if os(iOS)
    @State private var listEditMode: EditMode = .inactive
#endif

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
        _draftDefaultRestSeconds = State(initialValue: routine.defaultRestDurationSeconds)
        _draftExercises = State(
            initialValue: routine.plannedSets
                .groupedExercisePlans()
                .map(EditableExercisePlan.init(plan:))
        )
    }

    var body: some View {
        List {
            Section {
                headerCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 16, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                exercisesEditor
            } header: {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeader(
                        title: "Exercises",
                        subtitle: exercisesSubtitle
                    )
                    Spacer(minLength: 8)
                    if isReordering {
                        Button("Done") {
                            finishReordering()
                        }
                        .font(.footnote.weight(.bold))
                        .buttonStyle(.bordered)
                        .tint(DamSetDesign.moss)
                        .accessibilityLabel("Finish reordering exercises")
                    }
                }
                .textCase(nil)
            }

            Section {
                deleteRoutineButton
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .environment(\.editMode, $listEditMode)
        #endif
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
                    presentNewExerciseEditor()
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
                .accessibilityLabel("Add exercise")
            }
        }
        .sheet(item: $exerciseEditor) { context in
            ExerciseEditorSheet(
                title: context.existingExerciseID == nil ? "Add Exercise" : "Edit Exercise",
                saveTitle: context.existingExerciseID == nil ? "Add" : "Save",
                exercise: context.exercise
            ) { editedExercise in
                saveExercise(editedExercise, replacing: context.existingExerciseID)
            }
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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

            Divider()
                .overlay(DamSetDesign.steelMuted.opacity(0.7))

            routineRestControl

            Text("\(totalSetCount) sets · \(totalRestMinutes) rest")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .cardSurface(cornerRadius: 20)
    }

    private var routineRestControl: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Rest between sets", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(routineRestSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            routineRestStepButton(symbol: "minus") {
                applyRoutineRest(routineRestControlSeconds - 15)
            }

            Button {
                routineRestDraft = routineRestControlSeconds.minuteSecondText
                showRoutineRestEntry = true
            } label: {
                Text(routineRestLabel)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: 56, minHeight: 42)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(GymCompactStepperButtonStyle())
            .accessibilityLabel("Rest between sets \(routineRestAccessibilityValue)")
            .accessibilityHint("Double-tap to enter a rest time for every exercise")

            routineRestStepButton(symbol: "plus") {
                applyRoutineRest(routineRestControlSeconds + 15)
            }
        }
        .alert("Rest between sets", isPresented: $showRoutineRestEntry) {
            TextField("mm:ss", text: $routineRestDraft)
            Button("Apply") {
                guard let seconds = parsedRestSeconds(routineRestDraft) else { return }
                applyRoutineRest(seconds)
            }
            .disabled(parsedRestSeconds(routineRestDraft) == nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter seconds or mm:ss. This changes every exercise in this routine.")
        }
    }

    private func routineRestStepButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(DamSetDesign.accent)
                .frame(width: 42, height: 42)
        }
        .buttonStyle(GymCompactStepperButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel("\(symbol == "minus" ? "Decrease" : "Increase") rest between sets")
    }

    private var exercisesEditor: some View {
        Group {
            if draftExercises.isEmpty {
                ContentUnavailableView {
                    Label("No exercises", systemImage: "dumbbell")
                } description: {
                    Text("Use the + button above to add an exercise.")
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .cardSurface(accent: DamSetDesign.steelMuted.opacity(0.65))
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(draftExercises) { exercise in
                    let index = draftExercises.firstIndex(where: { $0.id == exercise.id }) ?? 0
                    CompactExerciseRow(
                        exercise: exercise,
                        order: index + 1,
                        canReorder: draftExercises.count > 1,
                        isReordering: isReordering,
                        edit: { presentExerciseEditor(for: exercise) },
                        beginReordering: beginReordering
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(exercise)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") {
                            presentExerciseEditor(for: exercise)
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            duplicate(exercise)
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            delete(exercise)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .onMove(perform: moveExercises)
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

    private var exercisesSubtitle: String {
        if isReordering {
            return "Drag ≡ to reorder, then tap Done."
        }
        return "Tap a name to edit · swipe ← to delete · tap ≡ to reorder"
    }

    private var isReordering: Bool {
        #if os(iOS)
        listEditMode.isEditing
        #else
        false
        #endif
    }

    private var totalSetCount: Int {
        draftExercises.reduce(0) { $0 + $1.setCount }
    }

    private var totalRestMinutes: String {
        let expandedSets = draftExercises.map(\.plan).expandedPlannedSets()
        let seconds = expandedSets.dropLast().reduce(0) { $0 + $1.restDurationSeconds }
        return "\(seconds / 60)m"
    }

    private var hasRestOverrides: Bool {
        draftExercises.contains { $0.restSeconds != draftDefaultRestSeconds }
    }

    /// This is persisted separately from each exercise so a user can keep an
    /// intentional per-exercise override while new exercises inherit the
    /// routine-wide interval.
    private var routineRestControlSeconds: Int {
        draftDefaultRestSeconds
    }

    private var routineRestLabel: String {
        hasRestOverrides ? "Mixed" : routineRestControlSeconds.minuteSecondText
    }

    private var routineRestSubtitle: String {
        if draftExercises.isEmpty {
            return "Default for new exercises"
        }
        return hasRestOverrides
            ? "Default \(routineRestControlSeconds.minuteSecondText) · some exercises override"
            : "Applies to every exercise"
    }

    private var routineRestAccessibilityValue: String {
        if hasRestOverrides {
            return "mixed. Default \(routineRestControlSeconds.minuteSecondText)"
        }
        return routineRestControlSeconds == 0 ? "no rest" : routineRestControlSeconds.minuteSecondText
    }

    private func applyRoutineRest(_ seconds: Int) {
        let normalizedSeconds = min(86_400, max(0, seconds))
        withAnimation(.snappy) {
            draftDefaultRestSeconds = normalizedSeconds
            for index in draftExercises.indices {
                draftExercises[index].restSeconds = normalizedSeconds
            }
        }
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
            defaultRestDurationSeconds: draftDefaultRestSeconds,
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

    private func presentNewExerciseEditor() {
        exerciseEditor = ExerciseEditorContext(
            existingExerciseID: nil,
            exercise: EditableExercisePlan(
                exerciseName: "",
                restSeconds: routineRestControlSeconds
            )
        )
    }

    private func presentExerciseEditor(for exercise: EditableExercisePlan) {
        exerciseEditor = ExerciseEditorContext(
            existingExerciseID: exercise.id,
            exercise: exercise
        )
    }

    private func saveExercise(
        _ editedExercise: EditableExercisePlan,
        replacing existingExerciseID: String?
    ) {
        guard !editedExercise.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let existingExerciseID,
           let index = draftExercises.firstIndex(where: { $0.id == existingExerciseID }) {
            draftExercises[index] = editedExercise
        } else {
            draftExercises.append(editedExercise)
        }
    }

    private func duplicate(_ exercise: EditableExercisePlan) {
        guard let index = draftExercises.firstIndex(where: { $0.id == exercise.id }) else { return }
        draftExercises.insert(exercise.duplicated(), at: index + 1)
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        withAnimation(.snappy) {
            draftExercises.move(fromOffsets: source, toOffset: destination)
        }
    }

    private func beginReordering() {
        #if os(iOS)
        guard draftExercises.count > 1 else { return }
        withAnimation(.snappy) {
            listEditMode = .active
        }
        #endif
    }

    private func finishReordering() {
        #if os(iOS)
        withAnimation(.snappy) {
            listEditMode = .inactive
        }
        #endif
    }

    private func delete(_ exercise: EditableExercisePlan) {
        draftExercises.removeAll { $0.id == exercise.id }
    }
}

private struct ExerciseEditorContext: Identifiable {
    let id = UUID()
    let existingExerciseID: String?
    let exercise: EditableExercisePlan
}

private struct CompactExerciseRow: View {
    let exercise: EditableExercisePlan
    let order: Int
    let canReorder: Bool
    let isReordering: Bool
    let edit: () -> Void
    let beginReordering: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 8) {
            if isReordering {
                rowContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button(action: edit) {
                    rowContent
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Edit \(exercise.exerciseName)")
                .accessibilityValue(accessibilitySummary)
                .accessibilityHint("Double-tap to change this exercise.")
            }

            if canReorder && !isReordering {
                Button(action: beginReordering) {
                    Image(systemName: "line.3.horizontal")
                        .font(.body.weight(.bold))
                        .foregroundStyle(DamSetDesign.steel)
                        .frame(width: 42, height: 42)
                        .background(DamSetDesign.controlFill, in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(DamSetDesign.steelMuted, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reorder exercises")
                .accessibilityHint("Shows drag handles to change the exercise order.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .cardSurface(cornerRadius: 16)
    }

    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                titleRow
                summary
            }
        } else {
            HStack(spacing: 12) {
                orderBadge
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    summary
                }
                Spacer(minLength: 8)
                if !isReordering {
                    Image(systemName: "pencil")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DamSetDesign.steel)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            orderBadge
            Text(exercise.exerciseName)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !isReordering {
                Image(systemName: "pencil")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DamSetDesign.steel)
                    .accessibilityHidden(true)
            }
        }
    }

    private var orderBadge: some View {
        Text("\(order)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(DamSetDesign.accent)
            .frame(width: 28, height: 28)
            .background(DamSetDesign.accent.opacity(0.14), in: Circle())
            .overlay {
                Circle()
                    .stroke(DamSetDesign.accent.opacity(0.55), lineWidth: 1)
            }
    }

    private var summary: some View {
        Text(summaryText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            .multilineTextAlignment(.leading)
    }

    private var summaryText: String {
        let load = exercise.exerciseKind == .bodyweight
            ? "Bodyweight"
            : "\(exercise.targetWeight.formatted(.number.precision(.fractionLength(0...1)))) kg"
        let rest = exercise.restSeconds == 0 ? "No rest" : "Rest \(exercise.restSeconds.minuteSecondText)"
        return "\(load) · \(exercise.targetReps) reps × \(exercise.setCount) sets · \(rest)"
    }

    private var accessibilitySummary: String {
        let load = exercise.exerciseKind == .bodyweight
            ? "Bodyweight"
            : "\(exercise.targetWeight.formatted()) kilograms"
        let rest = exercise.restSeconds == 0 ? "No rest" : "\(exercise.restSeconds) seconds rest"
        return "Position \(order). \(load), \(exercise.targetReps) reps for \(exercise.setCount) sets, \(rest)."
    }
}

private func parsedRestSeconds(_ rawValue: String) -> Int? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
    let seconds: Int?
    if parts.count == 2,
       let minutes = Int(parts[0]),
       let remainder = Int(parts[1]) {
        seconds = min(max(0, minutes), 1_440) * 60 + min(max(0, remainder), 59)
    } else {
        seconds = Int(trimmed)
    }
    return seconds.map { min(86_400, max(0, $0)) }
}

private struct EditableExerciseCard: View {
    @Binding var exercise: EditableExercisePlan
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Exercise name", text: $exercise.exerciseName)
                .font(.headline)
                .foregroundStyle(.primary)
                .tint(DamSetDesign.accent)

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
        .cardSurface(cornerRadius: 20)
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
        guard let seconds = parsedRestSeconds(rawValue) else { return }
        exercise.restSeconds = seconds
    }
}

private struct ExerciseEditorSheet: View {
    let title: String
    let saveTitle: String
    let onSave: (EditableExercisePlan) -> Void
    @State private var draft: EditableExercisePlan
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        saveTitle: String,
        exercise: EditableExercisePlan,
        onSave: @escaping (EditableExercisePlan) -> Void
    ) {
        self.title = title
        self.saveTitle = saveTitle
        self.onSave = onSave
        _draft = State(initialValue: exercise)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                EditableExerciseCard(
                    exercise: $draft
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(DamSetDesign.screenBackground.ignoresSafeArea())
            .navigationTitle(title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .gymNavigationChrome()
    }

    private var canSave: Bool {
        !draft.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.setCount > 0
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
