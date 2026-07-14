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

/// Dark training palette for the Lock Screen: equipment red for actions,
/// satin-steel neutrals for structure, and amber reserved for active rest.
private enum TrainingPalette {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.047)
    static let steel = Color(red: 0.76, green: 0.79, blue: 0.82)
    static let card = steel.opacity(0.10)
    static let control = steel.opacity(0.18)
    static let stroke = steel.opacity(0.26)
    static let primary = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let secondary = steel.opacity(0.74)
    static let accent = Color(red: 0.90, green: 0.20, blue: 0.18)
    static let warning = accent
    static let completed = Color(red: 0.82, green: 0.85, blue: 0.88)
}

struct DamSetLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DamSetActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(TrainingPalette.background)
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
                            .foregroundStyle(TrainingPalette.accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if restIsReady(context) {
                        Text("READY")
                            .font(.caption.bold())
                            .foregroundStyle(TrainingPalette.completed)
                    } else if isResting(context.state), let resumeAt = context.state.resumeAt {
                        Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(TrainingPalette.warning)
                            .frame(maxWidth: 72)
                    } else {
                        Text("\(context.state.actualReps)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(TrainingPalette.accent)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase == LockScreenPhase.completed.rawValue {
                        Label("Workout complete", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(TrainingPalette.completed)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        controlsRow(context: context)
                    }
                }
            } compactLeading: {
                Text("\(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                    .font(.caption2.bold())
                    .foregroundStyle(TrainingPalette.accent)
            } compactTrailing: {
                if restIsReady(context) {
                    Image(systemName: "forward.fill")
                        .foregroundStyle(TrainingPalette.completed)
                } else if isResting(context.state), let resumeAt = context.state.resumeAt {
                    Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(TrainingPalette.warning)
                        .frame(maxWidth: 44)
                } else {
                    Text("\(context.state.actualReps)")
                        .monospacedDigit()
                        .foregroundStyle(TrainingPalette.accent)
                }
            } minimal: {
                Image(systemName: "checklist")
                    .foregroundStyle(TrainingPalette.accent)
            }
        }
    }

    private func isResting(_ state: DamSetActivityAttributes.ContentState) -> Bool {
        state.phase == LockScreenPhase.resting.rawValue || state.phase == LockScreenPhase.readyForNextSet.rawValue
    }

    private func restIsReady(_ context: ActivityViewContext<DamSetActivityAttributes>) -> Bool {
        context.state.phase == LockScreenPhase.readyForNextSet.rawValue ||
            (context.state.phase == LockScreenPhase.resting.rawValue && context.isStale)
    }

    /// Lock Screen layout, optimized as a mission card: remaining rest time on
    /// top, then the actual reps the user did with −/+ correction controls.
    private func lockScreenView(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingPalette.accent)
                Text(context.state.exerciseName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("Set \(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(TrainingPalette.card, in: Capsule())
                    .foregroundStyle(TrainingPalette.secondary)
            }

            if context.state.phase == LockScreenPhase.completed.rawValue {
                Label("Workout complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(TrainingPalette.completed)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                missionStatusRow(context: context)
                controlsRow(context: context)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TrainingPalette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(TrainingPalette.stroke, lineWidth: 1)
                )
        )
    }

    private func missionStatusRow(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(restIsReady(context) ? "Rest complete" : (isResting(context.state) ? "Rest" : "Current set"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
                if restIsReady(context) {
                    Text("READY")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(TrainingPalette.completed)
                } else if isResting(context.state), let resumeAt = context.state.resumeAt {
                    Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TrainingPalette.warning)
                } else {
                    Text("Set \(context.state.currentSetIndex)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TrainingPalette.primary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Actual reps")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
                Text("\(context.state.actualReps)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TrainingPalette.accent)
                Text("\(context.state.actualWeight.formatted()) kg · target \(context.state.targetReps)")
                    .font(.caption2)
                    .foregroundStyle(TrainingPalette.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// − / reps / + / Done or Next — every target ≥44pt so a sweaty thumb can
    /// hit it without unlocking. During rest, −/+ corrects the just-finished
    /// rep count and Next explicitly skips/finishes the rest.
    private func controlsRow(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Button(intent: AdjustRepsIntent(sessionId: context.attributes.sessionId, delta: -1)) {
                Image(systemName: "minus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(TrainingPalette.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease reps")

            VStack(spacing: 1) {
                Text("\(context.state.actualReps)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TrainingPalette.primary)
                Text("reps")
                    .font(.caption2)
                    .foregroundStyle(TrainingPalette.secondary)
            }
            .frame(minWidth: 54)

            Button(intent: AdjustRepsIntent(sessionId: context.attributes.sessionId, delta: 1)) {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(TrainingPalette.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase reps")

            if context.state.phase == LockScreenPhase.performingSet.rawValue {
                Button(intent: CompleteSetIntent(sessionId: context.attributes.sessionId)) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(TrainingPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete set")
            } else {
                Button(intent: AdvanceToNextSetIntent(sessionId: context.attributes.sessionId)) {
                    Label(restIsReady(context) ? "Next" : "Skip", systemImage: "forward.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(TrainingPalette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(restIsReady(context) ? "Start next set" : "Skip rest and start next set")
            }
        }
    }
}
#endif
