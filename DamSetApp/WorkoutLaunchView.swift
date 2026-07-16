import SwiftUI
import DamSetCore

/// Lets someone tailor a saved routine for this workout only.
///
/// Selection lives entirely in this view. Starting passes a filtered copy to
/// the caller, so the saved `RoutineTemplate` is never mutated.
struct WorkoutLaunchView: View {
    let routine: RoutineTemplate
    let onStart: (RoutineTemplate) -> Void
    let onCancel: () -> Void

    @State private var selectedExerciseNames: Set<String>

    init(
        routine: RoutineTemplate,
        onStart: @escaping (RoutineTemplate) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.routine = routine
        self.onStart = onStart
        self.onCancel = onCancel
        _selectedExerciseNames = State(initialValue: Self.allExerciseNames(in: routine))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GymScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        launchHeader
                        exercisePicker
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Today's Workout")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                startBar
            }
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onChange(of: routine) { _, updatedRoutine in
            selectedExerciseNames = Self.allExerciseNames(in: updatedRoutine)
        }
    }

    private var launchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let emoji = routine.emoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 27))
                    } else {
                        Image(systemName: DamSetDesign.routineSymbol(for: routine))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DamSetDesign.accent)
                    }
                }
                    .frame(width: 48, height: 48)
                    .background(DamSetDesign.controlFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(DamSetDesign.steel.opacity(0.55), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.routineName)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("Choose what you want to train today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            SteelBarDivider(accent: DamSetDesign.accent)

            Label("Your saved routine will not change.", systemImage: "lock.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(DamSetDesign.steel)
        }
        .gymPanel(accent: DamSetDesign.accent.opacity(0.8), cut: 12, padding: 16)
        .accessibilityElement(children: .combine)
    }

    private var exercisePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                GymSectionLabel(text: "Exercises")
                Spacer(minLength: 12)
                Text(selectionSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            ForEach(exerciseGroups) { group in
                exerciseToggle(for: group)
            }
        }
    }

    private func exerciseToggle(for group: ExerciseGroup) -> some View {
        let isSelected = selectedExerciseNames.contains(group.name)

        return Toggle(isOn: selectionBinding(for: group.name)) {
            HStack(spacing: 13) {
                Image(systemName: Self.symbol(for: group))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? DamSetDesign.accent : DamSetDesign.steelMuted)
                    .frame(width: 42, height: 42)
                    .background(DamSetDesign.controlFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.displayName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(2)

                    Text(group.trainingSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(DamSetDesign.accent)
        .cardSurface(cornerRadius: 16, accent: isSelected ? DamSetDesign.accent : nil)
        .accessibilityHint(isSelected ? "Double-tap to skip this exercise today." : "Double-tap to include this exercise today.")
    }

    private var startBar: some View {
        VStack(spacing: 8) {
            if selectedExerciseNames.isEmpty {
                Text("Select at least one exercise to start.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DamSetDesign.amber)
                    .transition(.opacity)
            }

            Button(action: startSelectedWorkout) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text(startButtonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GymPrimaryButtonStyle())
            .disabled(selectedExerciseNames.isEmpty)
            .accessibilityHint("Starts a temporary workout without editing the saved routine.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DamSetDesign.steelMuted.opacity(0.55))
                .frame(height: 0.5)
        }
        .animation(.easeOut(duration: 0.16), value: selectedExerciseNames.isEmpty)
    }

    private var exerciseGroups: [ExerciseGroup] {
        Self.groups(in: routine)
    }

    private var selectedRoutine: RoutineTemplate {
        RoutineTemplate(
            routineId: routine.routineId,
            routineName: routine.routineName,
            emoji: routine.emoji,
            defaultRestDurationSeconds: routine.defaultRestDurationSeconds,
            plannedSets: routine.plannedSets.filter {
                selectedExerciseNames.contains($0.exerciseName)
            }
        )
    }

    private var selectedSetCount: Int {
        selectedRoutine.plannedSets.count
    }

    private var selectionSummary: String {
        "\(selectedExerciseNames.count)/\(exerciseGroups.count) selected"
    }

    private var startButtonTitle: String {
        let noun = selectedSetCount == 1 ? "Set" : "Sets"
        return "Start \(selectedSetCount) \(noun)"
    }

    private func selectionBinding(for exerciseName: String) -> Binding<Bool> {
        Binding(
            get: { selectedExerciseNames.contains(exerciseName) },
            set: { isSelected in
                if isSelected {
                    selectedExerciseNames.insert(exerciseName)
                } else {
                    selectedExerciseNames.remove(exerciseName)
                }
            }
        )
    }

    private func startSelectedWorkout() {
        guard !selectedExerciseNames.isEmpty else { return }
        onStart(selectedRoutine)
    }

    private static func allExerciseNames(in routine: RoutineTemplate) -> Set<String> {
        Set(routine.plannedSets.map(\.exerciseName))
    }

    private static func groups(in routine: RoutineTemplate) -> [ExerciseGroup] {
        var orderedNames: [String] = []
        var setsByName: [String: [PlannedSet]] = [:]

        for plannedSet in routine.plannedSets {
            if setsByName[plannedSet.exerciseName] == nil {
                orderedNames.append(plannedSet.exerciseName)
            }
            setsByName[plannedSet.exerciseName, default: []].append(plannedSet)
        }

        return orderedNames.map { name in
            ExerciseGroup(name: name, sets: setsByName[name, default: []])
        }
    }

    private static func symbol(for group: ExerciseGroup) -> String {
        switch group.exerciseKind {
        case .bodyweight:
            return "figure.strengthtraining.functional"
        case .weighted:
            return "dumbbell.fill"
        }
    }
}

private struct ExerciseGroup: Identifiable {
    let name: String
    let sets: [PlannedSet]

    var id: String { name }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed Exercise" : name
    }

    var exerciseKind: ExerciseKind {
        sets.contains { $0.exerciseKind == .weighted } ? .weighted : .bodyweight
    }

    var trainingSummary: String {
        guard let first = sets.first else { return "No sets" }
        let setText = sets.count == 1 ? "1 set" : "\(sets.count) sets"
        let hasBodyweight = sets.contains { $0.exerciseKind == .bodyweight }
        let hasWeighted = sets.contains { $0.exerciseKind == .weighted }
        if hasBodyweight && hasWeighted {
            return "\(setText) · mixed bodyweight & weighted"
        }
        if exerciseKind == .bodyweight {
            let hasOneRepTarget = sets.allSatisfy { $0.targetReps == first.targetReps }
            return hasOneRepTarget
                ? "\(setText) · bodyweight × \(first.targetReps)"
                : "\(setText) · bodyweight"
        }

        let hasOneTarget = sets.allSatisfy {
            $0.exerciseKind == .weighted &&
                $0.targetWeight == first.targetWeight &&
                $0.targetReps == first.targetReps
        }

        guard hasOneTarget else {
            return "\(setText) · varied targets"
        }

        return "\(setText) · \(weightText(first.targetWeight)) kg × \(first.targetReps)"
    }

    private func weightText(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}
