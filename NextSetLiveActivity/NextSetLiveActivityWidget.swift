#if os(iOS) && canImport(ActivityKit) && canImport(WidgetKit) && canImport(SwiftUI)
import ActivityKit
import SwiftUI
import WidgetKit
import NextSetCore

@main
struct NextSetWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextSetLiveActivityWidget()
    }
}

struct NextSetLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextSetActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.exerciseName).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Set \(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    lockScreenView(context: context)
                }
            } compactLeading: {
                Text("\(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
            } compactTrailing: {
                if isResting(context.state), let resumeAt = context.state.resumeAt {
                    Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                } else {
                    Text("\(context.state.actualReps)")
                }
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
            }
        }
    }

    private func isResting(_ state: NextSetActivityAttributes.ContentState) -> Bool {
        state.phase == LockScreenPhase.resting.rawValue || state.phase == LockScreenPhase.readyForNextSet.rawValue
    }

    private func lockScreenView(context: ActivityViewContext<NextSetActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(context.state.exerciseName).font(.headline)
                Spacer()
                Text("Set \(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if context.state.phase == LockScreenPhase.completed.rawValue {
                Label("Workout complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
            } else {
                // Spec: rest countdown, resume time, and the reps/complete controls
                // stay visible together. During an active rest the intents no-op;
                // once rest has elapsed they auto-advance and act on the next set.
                if isResting(context.state), let resumeAt = context.state.resumeAt {
                    HStack(spacing: 8) {
                        Text("Rest")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: 80)
                        Text("· resumes \(resumeAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 20) {
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
                        Text("Done").bold()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
}
#endif
