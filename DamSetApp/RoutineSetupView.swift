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
            VStack(alignment: .leading, spacing: 30) {
                headerCard
                setsEditor
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
                    addSet()
                } label: {
                    Label("Add Set", systemImage: "plus")
                }
            }
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Routine name", text: $draftName)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .tint(DamSetDesign.accent)
            Text("\(draftSets.count) sets · \(totalRestMinutes) rest")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .cardSurface(cornerRadius: 20)
    }

    private var setsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sets", subtitle: "Exercise · kg · reps · rest")
            ForEach($draftSets) { $set in
                EditableSetCard(
                    set: $set,
                    canDelete: draftSets.count > 1,
                    canMoveUp: draftSets.first?.id != set.id,
                    canMoveDown: draftSets.last?.id != set.id,
                    moveUp: { move(set, by: -1) },
                    moveDown: { move(set, by: 1) },
                    duplicate: { duplicate(set) },
                    delete: { delete(set) }
                )
            }
            Button {
                addSet()
            } label: {
                Label("Add set", systemImage: "plus")
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

    private var startButton: some View {
        Button {
            saveAndStart()
        } label: {
            Text("Start Workout")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.vertical, 4)
        }
        .buttonStyle(GymPrimaryButtonStyle())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .disabled(!canStart)
        .accessibilityLabel("Start workout with edited set plan")
    }

    private var canStart: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draftSets.contains { !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var totalRestMinutes: String {
        let seconds = draftSets.dropLast().reduce(0) { $0 + $1.restSeconds }
        return "\(seconds / 60)m"
    }

    private func makeRoutine() -> RoutineTemplate {
        let validSets = draftSets
            .filter { !$0.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .map { index, set in
                PlannedSet(
                    setId: set.sourceSetId
                        ?? "\(routine.routineId)-setup-\(index + 1)-\(set.id.uuidString)",
                    exerciseName: set.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines),
                    targetWeight: set.targetWeight,
                    targetReps: set.targetReps,
                    restDurationSeconds: set.restSeconds,
                    manuallyAdded: set.manuallyAdded
                )
            }

        return RoutineTemplate(
            routineId: routine.routineId,
            routineName: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            plannedSets: validSets
        )
    }

    private func saveAndDismiss() {
        guard viewModel.saveRoutine(makeRoutine()) else { return }
        dismiss()
    }

    private func saveAndStart() {
        let editedRoutine = makeRoutine()
        guard viewModel.saveRoutine(editedRoutine) else { return }
        viewModel.start(editedRoutine)
        dismiss()
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
        copy.sourceSetId = nil
        copy.manuallyAdded = true
        draftSets.append(copy)
    }

    private func move(_ set: EditablePlannedSet, by offset: Int) {
        guard let sourceIndex = draftSets.firstIndex(where: { $0.id == set.id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard draftSets.indices.contains(destinationIndex) else { return }

        withAnimation(.snappy) {
            draftSets.swapAt(sourceIndex, destinationIndex)
        }
    }

    private func delete(_ set: EditablePlannedSet) {
        guard draftSets.count > 1 else { return }
        draftSets.removeAll { $0.id == set.id }
    }
}

private struct EditableSetCard: View {
    @Binding var set: EditablePlannedSet
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
                TextField("Exercise", text: $set.exerciseName)
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

            if dynamicTypeSize.isAccessibilitySize {
                StepperField(
                    title: "kg",
                    value: weightText,
                    decrement: { set.targetWeight = max(0, set.targetWeight - 2.5) },
                    increment: { set.targetWeight += 2.5 },
                    directEntry: updateWeight
                )
                Divider().overlay(DamSetDesign.steelMuted)
                StepperField(
                    title: "reps",
                    value: "\(set.targetReps)",
                    decrement: { set.targetReps = max(0, set.targetReps - 1) },
                    increment: { set.targetReps += 1 },
                    directEntry: updateReps
                )
                Divider().overlay(DamSetDesign.steelMuted)
                StepperField(
                    title: "rest",
                    value: set.restSeconds.minuteSecondText,
                    decrement: { set.restSeconds = max(0, set.restSeconds - 15) },
                    increment: { set.restSeconds += 15 },
                    directEntry: updateRest
                )
            } else {
                HStack(spacing: 0) {
                    StepperField(
                        title: "kg",
                        value: weightText,
                        decrement: { set.targetWeight = max(0, set.targetWeight - 2.5) },
                        increment: { set.targetWeight += 2.5 },
                        directEntry: updateWeight
                    )
                    Divider()
                        .overlay(DamSetDesign.steelMuted)
                        .frame(height: 48)
                    StepperField(
                        title: "reps",
                        value: "\(set.targetReps)",
                        decrement: { set.targetReps = max(0, set.targetReps - 1) },
                        increment: { set.targetReps += 1 },
                        directEntry: updateReps
                    )
                    Divider()
                        .overlay(DamSetDesign.steelMuted)
                        .frame(height: 48)
                    StepperField(
                        title: "rest",
                        value: set.restSeconds.minuteSecondText,
                        decrement: { set.restSeconds = max(0, set.restSeconds - 15) },
                        increment: { set.restSeconds += 15 },
                        directEntry: updateRest
                    )
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .cardSurface(cornerRadius: 20)
    }

    private var weightText: String {
        "\(set.targetWeight.formatted(.number.precision(.fractionLength(0...1))))"
    }

    private func updateWeight(_ rawValue: String) {
        guard let value = parsedWeight(rawValue), value.isFinite else { return }
        set.targetWeight = min(9_999, max(0, value))
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
        set.targetReps = min(999, max(0, value))
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
        set.restSeconds = min(86_400, max(0, seconds))
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
            Text(title == "rest" ? "Enter seconds or mm:ss." : "Enter a number.")
        }
    }

    private var isValidDraft: Bool {
        let trimmed = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch title {
        case "kg":
            let formatter = NumberFormatter()
            formatter.locale = .current
            formatter.numberStyle = .decimal
            if let value = formatter.number(from: trimmed)?.doubleValue {
                return value.isFinite && value >= 0
            }
            let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
            return Double(normalized).map { $0.isFinite && $0 >= 0 } ?? false
        case "reps":
            return Int(trimmed).map { $0 >= 0 } ?? false
        case "rest":
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

private struct EditablePlannedSet: Identifiable, Equatable {
    var id: UUID
    var sourceSetId: String?
    var exerciseName: String
    var targetWeight: Double
    var targetReps: Int
    var restSeconds: Int
    var manuallyAdded: Bool

    init(
        id: UUID = UUID(),
        sourceSetId: String? = nil,
        exerciseName: String = "New Exercise",
        targetWeight: Double = 20,
        targetReps: Int = 8,
        restSeconds: Int = 90,
        manuallyAdded: Bool = true
    ) {
        self.id = id
        self.sourceSetId = sourceSetId
        self.exerciseName = exerciseName
        self.targetWeight = max(0, targetWeight)
        self.targetReps = max(0, targetReps)
        self.restSeconds = max(0, restSeconds)
        self.manuallyAdded = manuallyAdded
    }

    init(planned: PlannedSet) {
        self.init(
            sourceSetId: planned.setId,
            exerciseName: planned.exerciseName,
            targetWeight: planned.targetWeight,
            targetReps: planned.targetReps,
            restSeconds: planned.restDurationSeconds,
            manuallyAdded: planned.manuallyAdded
        )
    }
}
