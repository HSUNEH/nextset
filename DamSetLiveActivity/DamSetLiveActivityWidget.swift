#if os(iOS) && canImport(ActivityKit) && canImport(WidgetKit) && canImport(SwiftUI)
import ActivityKit
import SwiftUI
import WidgetKit
import DamSetCore

@main
struct DamSetWidgetBundle: WidgetBundle {
    var body: some Widget {
        DamSetLiveActivityWidget()
    }
}

struct DamSetLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DamSetActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .lineLimit(1)
                        Text("Set \(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isResting(context.state), let resumeAt = context.state.resumeAt {
                        Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                            .font(.title3.bold().monospacedDigit())
                            .frame(maxWidth: 72)
                    } else {
                        Text("\(context.state.actualReps)")
                            .font(.title2.bold().monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    compactControls(context: context)
                }
            } compactLeading: {
                Text("\(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                    .font(.caption2.bold())
            } compactTrailing: {
                if isResting(context.state), let resumeAt = context.state.resumeAt {
                    Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text("\(context.state.actualReps)")
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
            }
        }
    }

    private func isResting(_ state: DamSetActivityAttributes.ContentState) -> Bool {
        state.phase == LockScreenPhase.resting.rawValue || state.phase == LockScreenPhase.readyForNextSet.rawValue
    }

    private func lockScreenView(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .frame(width: 34, height: 34)
                    .background(.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Set \(context.state.currentSetIndex) of \(context.state.totalPlannedSets)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                phasePill(context.state)
            }

            if context.state.phase == LockScreenPhase.completed.rawValue {
                Label("Workout complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                if isResting(context.state), let resumeAt = context.state.resumeAt {
                    HStack(spacing: 8) {
                        Label("Rest", systemImage: "timer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: 84)
                        Text("Ready \(resumeAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                compactControls(context: context)
            }
        }
        .padding()
    }

    private func compactControls(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            Button(intent: AdjustRepsIntent(delta: -1)) {
                Image(systemName: "minus.circle.fill")
                    .font(.largeTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease reps")

            VStack(spacing: 0) {
                Text("\(context.state.targetReps)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("did \(context.state.actualReps)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(minWidth: 64)

            Button(intent: AdjustRepsIntent(delta: 1)) {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase reps")

            Button(intent: CompleteSetIntent()) {
                Text("Done")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func phasePill(_ state: DamSetActivityAttributes.ContentState) -> some View {
        let text: String
        let color: Color
        if state.phase == LockScreenPhase.resting.rawValue || state.phase == LockScreenPhase.readyForNextSet.rawValue {
            text = "REST"
            color = .orange
        } else if state.phase == LockScreenPhase.completed.rawValue {
            text = "DONE"
            color = .green
        } else {
            text = "LIVE"
            color = .blue
        }
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}
#endif
