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
    static let control = steel.opacity(0.18)
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
                        Text(displayedExerciseName(for: context))
                            .font(.headline)
                            .lineLimit(1)
                        Text("Set \(displayedSetIndex(for: context))/\(context.state.totalPlannedSets)")
                            .font(.caption)
                            .foregroundStyle(TrainingPalette.accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if showsAutomaticNextSet(context) {
                        Text("\(displayedActualReps(for: context))")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(TrainingPalette.accent)
                    } else if restIsReady(context) {
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
                Text("\(displayedSetIndex(for: context))/\(context.state.totalPlannedSets)")
                    .font(.caption2.bold())
                    .foregroundStyle(TrainingPalette.accent)
            } compactTrailing: {
                if showsAutomaticNextSet(context) {
                    Text("\(displayedActualReps(for: context))")
                        .monospacedDigit()
                        .foregroundStyle(TrainingPalette.accent)
                } else if restIsReady(context) {
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

    /// WidgetKit marks a Live Activity stale at the rest deadline even if iOS
    /// has suspended the app. `isStale` is only advisory, though, and can be
    /// reflected a beat late on the Lock Screen. Use the persisted deadline as
    /// the source of truth so 0:00 renders the following set immediately.
    private func showsAutomaticNextSet(_ context: ActivityViewContext<DamSetActivityAttributes>) -> Bool {
        context.state.phase == LockScreenPhase.resting.rawValue
            && restHasExpired(context)
            && context.state.nextExerciseName != nil
    }

    private func restIsReady(_ context: ActivityViewContext<DamSetActivityAttributes>) -> Bool {
        context.state.phase == LockScreenPhase.readyForNextSet.rawValue ||
            (context.state.phase == LockScreenPhase.resting.rawValue
                && restHasExpired(context)
                && !showsAutomaticNextSet(context))
    }

    private func restHasExpired(_ context: ActivityViewContext<DamSetActivityAttributes>) -> Bool {
        guard let resumeAt = context.state.resumeAt else { return context.isStale }
        return Date.now >= resumeAt
    }

    private func displayedExerciseName(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        showsAutomaticNextSet(context)
            ? context.state.nextExerciseName ?? context.state.exerciseName
            : context.state.exerciseName
    }

    private func displayedSetIndex(for context: ActivityViewContext<DamSetActivityAttributes>) -> Int {
        guard showsAutomaticNextSet(context) else { return context.state.currentSetIndex }
        return min(context.state.currentSetIndex + 1, context.state.totalPlannedSets)
    }

    private func displayedExerciseKind(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        showsAutomaticNextSet(context)
            ? context.state.nextExerciseKind ?? context.state.exerciseKind
            : context.state.exerciseKind
    }

    private func displayedTargetReps(for context: ActivityViewContext<DamSetActivityAttributes>) -> Int {
        showsAutomaticNextSet(context)
            ? context.state.nextTargetReps ?? context.state.targetReps
            : context.state.targetReps
    }

    private func displayedWeight(for context: ActivityViewContext<DamSetActivityAttributes>) -> Double {
        showsAutomaticNextSet(context)
            ? context.state.nextTargetWeight ?? context.state.actualWeight
            : context.state.actualWeight
    }

    private func displayedActualReps(for context: ActivityViewContext<DamSetActivityAttributes>) -> Int {
        showsAutomaticNextSet(context)
            ? displayedTargetReps(for: context)
            : context.state.actualReps
    }

    /// Lock Screen Live Activities are capped at roughly 160pt high. Keep this
    /// deliberately to two information rows and one control row so iOS never
    /// clips the actions behind the flashlight/camera controls.
    private func lockScreenView(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        // `Text(timerInterval:)` keeps the number moving, but it does not
        // re-evaluate surrounding conditional views at zero. Request an exact
        // timeline refresh at the deadline so the card switches from Rest to
        // the next set at the same moment as the final countdown cue.
        TimelineView(.explicit(context.state.resumeAt.map { [$0] } ?? [])) { _ in
            lockScreenContent(context: context)
        }
    }

    private func lockScreenContent(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            compactHeader(context: context)

            if context.state.phase == LockScreenPhase.completed.rawValue {
                Label("Workout complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(TrainingPalette.completed)
                    .frame(maxWidth: .infinity, minHeight: 42)
            } else {
                statusLine(context: context)
                controlsRow(context: context)
                    // WidgetKit renders this as pending while the App Intent
                    // saves and refreshes the Activity, instead of looking as
                    // if a tap was ignored.
                    .invalidatableContent()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactHeader(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(spacing: 9) {
            Image(systemName: phaseSymbol(for: context))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(phaseColor(for: context))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayedExerciseName(for: context))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingPalette.primary)
                    .lineLimit(1)
                Text(loadSummary(for: context))
                    .font(.caption2)
                    .foregroundStyle(TrainingPalette.secondary)
            }
            Spacer()
            Text("Set \(displayedSetIndex(for: context))/\(context.state.totalPlannedSets)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(TrainingPalette.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(TrainingPalette.control, in: Capsule())
        }
    }

    private func statusLine(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if showsAutomaticNextSet(context) {
                Label("Start now", systemImage: "figure.strengthtraining.traditional")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingPalette.completed)
                Spacer()
                Text("Target \(displayedTargetReps(for: context))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
                    .monospacedDigit()
            } else if restIsReady(context) {
                Label("Rest complete", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrainingPalette.completed)
            } else if isResting(context.state), let resumeAt = context.state.resumeAt {
                Label {
                    Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "timer")
                }
                .font(.title3.weight(.bold))
                .foregroundStyle(TrainingPalette.warning)
                Spacer()
                Text("Rest")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
            } else {
                Text("Actual reps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
                Spacer()
                Text("Target \(context.state.targetReps)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: 18)
    }

    /// − / reps / + / Done or Next — every target ≥44pt so a sweaty thumb can
    /// hit it without unlocking. During rest, −/+ corrects the just-finished
    /// rep count and Next explicitly skips/finishes the rest.
    private func controlsRow(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(spacing: 9) {
            Button(intent: AdjustRepsIntent(sessionId: context.attributes.sessionId, delta: -1)) {
                Image(systemName: "minus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(TrainingPalette.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease reps")

            Text("\(displayedActualReps(for: context))")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(TrainingPalette.primary)
                .frame(minWidth: 48)

            Button(intent: AdjustRepsIntent(sessionId: context.attributes.sessionId, delta: 1)) {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(TrainingPalette.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase reps")

            if context.state.phase == LockScreenPhase.performingSet.rawValue || showsAutomaticNextSet(context) {
                Button(intent: CompleteSetIntent(sessionId: context.attributes.sessionId)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(TrainingPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete set")
            } else {
                Button(intent: AdvanceToNextSetIntent(sessionId: context.attributes.sessionId)) {
                    Label(restIsReady(context) ? "Next" : "Skip", systemImage: "forward.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(TrainingPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(restIsReady(context) ? "Start next set" : "Skip rest and start next set")
            }
        }
    }

    private func loadSummary(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        if displayedExerciseKind(for: context) == ExerciseKind.bodyweight.rawValue {
            return "Bodyweight · target \(displayedTargetReps(for: context)) reps"
        }
        return "\(displayedWeight(for: context).formatted()) kg · target \(displayedTargetReps(for: context)) reps"
    }

    private func phaseSymbol(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        if showsAutomaticNextSet(context) {
            return "figure.strengthtraining.traditional"
        }
        if context.state.phase == LockScreenPhase.readyForNextSet.rawValue {
            return "checkmark.circle.fill"
        }
        if isResting(context.state) {
            return "timer"
        }
        return "figure.strengthtraining.traditional"
    }

    private func phaseColor(for context: ActivityViewContext<DamSetActivityAttributes>) -> Color {
        if showsAutomaticNextSet(context) {
            return TrainingPalette.completed
        }
        if restIsReady(context) {
            return TrainingPalette.completed
        }
        return isResting(context.state) ? TrainingPalette.warning : TrainingPalette.accent
    }
}
#endif
