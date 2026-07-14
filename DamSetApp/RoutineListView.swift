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
    }
}

private struct RoutineRow: View {
    let routine: RoutineTemplate

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: DamSetDesign.routineSymbol(for: routine))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DamSetDesign.routineTint(for: routine))
                .frame(width: 44, height: 44)
                .background(DamSetDesign.routineTint(for: routine).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.routineName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(exerciseSummary(routine))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("\(routine.plannedSets.count) sets · \(totalRestMinutes(routine)) min rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .cardSurface()
    }

    private func exerciseSummary(_ routine: RoutineTemplate) -> String {
        let names = Array(Set(routine.plannedSets.map(\.exerciseName))).sorted()
        return names.prefix(2).joined(separator: " · ")
    }

    private func totalRestMinutes(_ routine: RoutineTemplate) -> Int {
        routine.plannedSets.reduce(0) { $0 + $1.restDurationSeconds } / 60
    }
}

private struct HistoryRow: View {
    let summary: WorkoutSummary

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DamSetDesign.moss)
                .frame(width: 44, height: 44)
                .background(DamSetDesign.moss.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.routineName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(summary.workoutEndTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(summary.totalSets) sets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(summary.totalVolume.formatted()) kg")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .cardSurface()
    }
}

struct WorkoutSummaryDetailView: View {
    let summary: WorkoutSummary

    var body: some View {
        List {
            Section("Sets") {
                ForEach(Array(summary.completedSets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.exerciseName)
                            Text("Set \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(set.actualWeight.formatted()) kg × \(set.actualReps)")
                            .monospacedDigit()
                    }
                }
            }
            Section("Totals") {
                LabeledContent("Total sets", value: "\(summary.totalSets)")
                LabeledContent("Total volume", value: "\(summary.totalVolume.formatted()) kg")
                LabeledContent("Started", value: summary.workoutStartTime.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Ended", value: summary.workoutEndTime.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(summary.routineName)
        .inlineNavigationTitle()
    }
}
