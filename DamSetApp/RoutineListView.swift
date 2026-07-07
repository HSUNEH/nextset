import SwiftUI
import DamSetCore

struct RoutineListView: View {
    @State var viewModel: WorkoutViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroHeader
                    routineSection
                    if !viewModel.savedSummaries.isEmpty {
                        historySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(DamSetDesign.appGradient.ignoresSafeArea())
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
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("DamSet")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Pick a routine, then keep your phone locked while the set and rest flow stays live.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(DamSetDesign.activeGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 10) {
                MetricPill(title: "Routines", value: "\(viewModel.catalog.routines.count)", symbol: "list.bullet.rectangle")
                MetricPill(title: "Saved", value: "\(viewModel.savedSummaries.count)", symbol: "clock.arrow.circlepath")
            }
        }
        .cardSurface(cornerRadius: 32)
    }

    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Start workout", subtitle: "Apple-native controls, Lock Screen ready")
            ForEach(viewModel.catalog.routines) { routine in
                NavigationLink {
                    RoutineSetupView(routine: routine, viewModel: viewModel)
                } label: {
                    RoutineCard(routine: routine)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "History", subtitle: "Recent completed sessions")
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
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
        }
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(value).bold()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .foregroundStyle(.white)
    }
}

private struct RoutineCard: View {
    let routine: RoutineTemplate

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: DamSetDesign.routineSymbol(for: routine))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(DamSetDesign.routineTint(for: routine).gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(routine.routineName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(routineSummary(routine))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(routine.plannedSets.count) sets · \(totalRestMinutes(routine)) min rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                Text("Setup")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(DamSetDesign.routineTint(for: routine))
        }
        .cardSurface(cornerRadius: 26)
    }

    private func routineSummary(_ routine: RoutineTemplate) -> String {
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
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.routineName)
                    .font(.headline)
                Text(summary.workoutEndTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(summary.totalSets) sets")
                    .font(.subheadline.weight(.semibold))
                Text("\(summary.totalVolume.formatted()) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .cardSurface(cornerRadius: 22)
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
