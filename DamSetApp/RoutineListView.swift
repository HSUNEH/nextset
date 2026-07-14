import SwiftUI
import DamSetCore

struct RoutineListView: View {
    @State var viewModel: WorkoutViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    routineSection
                    if !viewModel.savedSummaries.isEmpty {
                        historySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(DamSetDesign.screenBackground.ignoresSafeArea())
            .navigationTitle("DamSet")
            .inlineNavigationTitle()
            .workoutSessionCover(item: Binding(get: { viewModel.activeSession }, set: { viewModel.activeSession = $0 })) { _ in
                ActiveWorkoutView(viewModel: viewModel)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    viewModel.refreshFromSharedStore()
                }
            }
        }
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Routines")
            VStack(spacing: 10) {
                ForEach(viewModel.catalog.routines) { routine in
                    NavigationLink {
                        RoutineSetupView(routine: routine, viewModel: viewModel)
                    } label: {
                        RoutineRow(routine: routine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "History")
            VStack(spacing: 10) {
                ForEach(viewModel.savedSummaries) { summary in
                    NavigationLink {
                        WorkoutSummaryDetailView(summary: summary)
                    } label: {
                        HistoryRow(summary: summary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
        .cardSurface()
    }

    private var routineIcon: some View {
        Image(systemName: DamSetDesign.routineSymbol(for: routine))
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(DamSetDesign.accent)
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
            Text("\(summary.totalVolume.formatted()) kg")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct WorkoutSummaryDetailView: View {
    let summary: WorkoutSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        List {
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
                LabeledContent("Total volume", value: "\(summary.totalVolume.formatted()) kg")
                LabeledContent("Started", value: summary.workoutStartTime.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Ended", value: summary.workoutEndTime.formatted(date: .abbreviated, time: .shortened))
            }
            .listRowBackground(DamSetDesign.surface)
        }
        .scrollContentBackground(.hidden)
        .background(DamSetDesign.screenBackground)
        .listSectionSeparatorTint(DamSetDesign.steelMuted)
        .navigationTitle(summary.routineName)
        .inlineNavigationTitle()
        .tint(DamSetDesign.accent)
        .preferredColorScheme(.dark)
        .gymNavigationChrome()
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
        Text("\(set.actualWeight.formatted()) kg × \(set.actualReps)")
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
