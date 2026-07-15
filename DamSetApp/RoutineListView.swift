import SwiftUI
import DamSetCore

struct RoutineListView: View {
    @State var viewModel: WorkoutViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchRoutine: RoutineTemplate?
    @State private var routinePendingStart: RoutineTemplate?
    @State private var routinePendingChooser: RoutineTemplate?
    @State private var newRoutine: RoutineTemplate?
    @State private var routinePendingDeletion: RoutineTemplate?

    var body: some View {
        TabView {
            routinesNavigation
                .tabItem {
                    Label("Routines", systemImage: "list.bullet.rectangle")
                }

            NavigationStack {
                WorkoutHistoryCalendarView(
                    summaries: viewModel.savedSummaries,
                    onUpdate: viewModel.updateWorkoutSummary,
                    onDelete: viewModel.deleteWorkoutSummary
                )
            }
            .gymNavigationChrome()
            .tabItem {
                Label("History", systemImage: "calendar")
            }
        }
        .background(DamSetDesign.screenBackground.ignoresSafeArea())
        .workoutSessionCover(item: Binding(get: { viewModel.activeSession }, set: { viewModel.activeSession = $0 })) { _ in
            ActiveWorkoutView(viewModel: viewModel)
        }
        .sheet(item: $launchRoutine, onDismiss: startPendingRoutine) { routine in
            WorkoutLaunchView(
                routine: routine,
                onStart: { selectedRoutine in
                    routinePendingStart = selectedRoutine
                    launchRoutine = nil
                },
                onCancel: { launchRoutine = nil }
            )
        }
        .sheet(item: $newRoutine, onDismiss: presentPendingSetupChooser) { routine in
            NavigationStack {
                RoutineSetupView(
                    routine: routine,
                    viewModel: viewModel,
                    // This setup is itself a sheet. Queue the chooser and let
                    // the sheet's onDismiss present it after the transition.
                    onChooseWorkout: { routinePendingChooser = $0 }
                )
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.refreshFromSharedStore()
            }
        }
        .confirmationDialog(
            "Delete routine?",
            isPresented: Binding(
                get: { routinePendingDeletion != nil },
                set: { if !$0 { routinePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Routine", role: .destructive) {
                if let routinePendingDeletion {
                    _ = viewModel.deleteRoutine(routinePendingDeletion)
                }
                routinePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { routinePendingDeletion = nil }
        } message: {
            Text(routinePendingDeletion?.routineName ?? "This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
    }

    private var routinesNavigation: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    routineSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(DamSetDesign.screenBackground.ignoresSafeArea())
            .navigationTitle("Routines")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newRoutine = makeNewRoutine()
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Create routine")
                }
            }
        }
        .gymNavigationChrome()
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "My Routines",
                subtitle: "Edit the template here. Choose today's exercises when you start."
            )
            if viewModel.catalog.routines.isEmpty {
                ContentUnavailableView {
                    Label("No routines", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Build a routine with your own name, emoji, and exercises.")
                } actions: {
                    Button("Create Routine") { newRoutine = makeNewRoutine() }
                        .buttonStyle(GymPrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, minHeight: 260)
                .cardSurface()
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.catalog.routines) { routine in
                        HStack(spacing: 8) {
                            NavigationLink {
                                RoutineSetupView(
                                    routine: routine,
                                    viewModel: viewModel,
                                    onChooseWorkout: queueSetupChooser
                                )
                            } label: {
                                RoutineRow(routine: routine)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button {
                                launchRoutine = routine
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(DamSetDesign.accent)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(GymMetalControlButtonStyle(shape: .circle))
                            .accessibilityLabel("Choose today's exercises for \(routine.routineName)")
                            .disabled(viewModel.activeSession != nil || viewModel.isBusy)

                        }
                        .cardSurface()
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                routinePendingDeletion = routine
                            }
                        }
                    }
                }
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && viewModel.activeSession == nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }

    private func makeNewRoutine() -> RoutineTemplate {
        RoutineTemplate(
            routineId: "custom-\(UUID().uuidString)",
            routineName: "New Routine",
            emoji: "🔥",
            plannedSets: [
                PlannedSet(
                    setId: "custom-set-\(UUID().uuidString)",
                    exerciseName: "New Exercise",
                    exerciseKind: .weighted,
                    targetWeight: 20,
                    targetReps: 8,
                    restDurationSeconds: 90,
                    manuallyAdded: true
                )
            ]
        )
    }

    /// Start only after the exercise chooser has finished dismissing. This
    /// avoids asking SwiftUI to dismiss a sheet and present the workout cover
    /// in the same presentation transaction.
    private func startPendingRoutine() {
        guard let routinePendingStart else { return }
        self.routinePendingStart = nil
        viewModel.start(routinePendingStart)
    }

    private func queueSetupChooser(_ routine: RoutineTemplate) {
        routinePendingChooser = routine
        guard newRoutine == nil else { return }
        Task { @MainActor in
            await Task.yield()
            presentPendingSetupChooser()
        }
    }

    private func presentPendingSetupChooser() {
        guard launchRoutine == nil, let routinePendingChooser else { return }
        self.routinePendingChooser = nil
        launchRoutine = routinePendingChooser
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct RoutineRow: View {
    let routine: RoutineTemplate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        routineIcon
                        Spacer(minLength: 8)
                        chevron
                    }
                    Text(routine.routineName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    routineDetails
                }
            } else {
                HStack(spacing: 14) {
                    routineIcon
                    VStack(alignment: .leading, spacing: 3) {
                        Text(routine.routineName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        routineDetails
                    }
                    Spacer(minLength: 8)
                    chevron
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var routineIcon: some View {
        Group {
            if let emoji = routine.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 23))
            } else {
                Image(systemName: DamSetDesign.routineSymbol(for: routine))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(DamSetDesign.accent)
            }
        }
            .frame(width: 44, height: 44)
            .background(DamSetDesign.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DamSetDesign.steelMuted, lineWidth: 1)
            }
    }

    private var routineDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exerciseSummary(routine))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text("\(routine.plannedSets.count) sets · \(totalRestMinutes(routine)) min rest")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DamSetDesign.steel)
    }

    private func exerciseSummary(_ routine: RoutineTemplate) -> String {
        let names = Array(Set(routine.plannedSets.map(\.exerciseName))).sorted()
        return names.prefix(2).joined(separator: " · ")
    }

    private func totalRestMinutes(_ routine: RoutineTemplate) -> Int {
        routine.plannedSets.dropLast().reduce(0) { $0 + $1.restDurationSeconds } / 60
    }
}

private struct HistoryRow: View {
    let summary: WorkoutSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    historyIcon
                    historyIdentity
                    historyMetrics
                }
            } else {
                HStack(spacing: 14) {
                    historyIcon
                    historyIdentity
                    Spacer(minLength: 8)
                    historyMetrics
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .cardSurface()
    }

    private var historyIcon: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(DamSetDesign.accent)
            .frame(width: 44, height: 44)
            .background(DamSetDesign.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DamSetDesign.steelMuted, lineWidth: 1)
            }
    }

    private var historyIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.routineName)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(summary.workoutEndTime.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var historyMetrics: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            Text("\(summary.totalSets) sets")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(summary.compactTrainingLoadText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct WorkoutSummaryDetailView: View {
    @State private var summary: WorkoutSummary
    let allSummaries: [WorkoutSummary]
    let onUpdate: (WorkoutSummary) -> Bool
    let onDelete: (WorkoutSummary) -> Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @State private var showsEditor = false
    @State private var showsDeleteConfirmation = false

    init(
        summary: WorkoutSummary,
        allSummaries: [WorkoutSummary] = [],
        onUpdate: @escaping (WorkoutSummary) -> Bool = { _ in false },
        onDelete: @escaping (WorkoutSummary) -> Bool = { _ in false }
    ) {
        _summary = State(initialValue: summary)
        self.allSummaries = allSummaries
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }

    var body: some View {
        List {
            if !summary.completedSets.isEmpty {
                Section("Progress") {
                    WorkoutProgressChartView(
                        selectedSummary: summary,
                        allSummaries: chartSummaries
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            Section("Sets") {
                ForEach(Array(summary.completedSets.enumerated()), id: \.offset) { index, set in
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                completedSetIdentity(index: index, set: set)
                                completedSetValue(set)
                            }
                        } else {
                            HStack {
                                completedSetIdentity(index: index, set: set)
                                Spacer()
                                completedSetValue(set)
                            }
                        }
                    }
                    .listRowBackground(DamSetDesign.surface)
                }
            }
            Section("Totals") {
                LabeledContent("Total sets", value: "\(summary.totalSets)")
                if summary.hasWeightedSets {
                    LabeledContent("Total volume", value: "\(summary.totalVolume.formatted()) kg")
                }
                if summary.hasBodyweightSets {
                    LabeledContent("Training", value: "Bodyweight")
                }
                LabeledContent("Started", value: summary.workoutStartTime.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Ended", value: summary.workoutEndTime.formatted(date: .abbreviated, time: .shortened))
            }
            .listRowBackground(DamSetDesign.surface)

            Section {
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Workout", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .listRowBackground(DamSetDesign.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DamSetDesign.screenBackground)
        .listSectionSeparatorTint(DamSetDesign.steelMuted)
        .navigationTitle(summary.routineName)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsEditor = true
                } label: {
                    Label("Edit Record", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showsEditor) {
            WorkoutRecordEditView(summary: summary) { updatedSummary in
                guard onUpdate(updatedSummary) else { return false }
                summary = updatedSummary
                return true
            }
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) {
                guard onDelete(summary) else { return }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "\(summary.routineName) · \(summary.workoutEndTime.formatted(date: .abbreviated, time: .shortened)) · \(summary.totalSets) sets. Its progress points will also be removed."
            )
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
    }

    private var chartSummaries: [WorkoutSummary] {
        allSummaries.filter { $0.sessionId != summary.sessionId } + [summary]
    }

    private func completedSetIdentity(index: Int, set: CompletedSet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.exerciseName)
                .foregroundStyle(.primary)
            Text("Set \(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func completedSetValue(_ set: CompletedSet) -> some View {
        Text(
            set.exerciseKind == .bodyweight
                ? "Bodyweight × \(set.actualReps)"
                : "\(set.actualWeight.formatted()) kg × \(set.actualReps)"
        )
            .monospacedDigit()
            .foregroundStyle(.primary)
    }
}

extension View {
    @ViewBuilder
    func gymNavigationChrome() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(DamSetDesign.chromeBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #else
        self
        #endif
    }
}
