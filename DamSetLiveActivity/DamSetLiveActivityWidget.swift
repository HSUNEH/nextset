#if os(iOS) && canImport(ActivityKit) && canImport(WidgetKit) && canImport(SwiftUI)
import ActivityKit
import Foundation
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
                        Text(displayedProgressValue(for: context))
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
                        Text(displayedProgressValue(for: context))
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
                    Text(displayedProgressValue(for: context))
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
                    Text(displayedProgressValue(for: context))
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

    private func showsUpcomingExercise(_ context: ActivityViewContext<DamSetActivityAttributes>) -> Bool {
        isResting(context.state) && context.state.nextExerciseName != nil
    }

    private func displayedExerciseName(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        showsUpcomingExercise(context)
            ? context.state.nextExerciseName ?? context.state.exerciseName
            : context.state.exerciseName
    }

    private func displayedSetIndex(for context: ActivityViewContext<DamSetActivityAttributes>) -> Int {
        guard showsUpcomingExercise(context) else { return context.state.currentSetIndex }
        return min(context.state.currentSetIndex + 1, context.state.totalPlannedSets)
    }

    private func displayedExerciseKind(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        showsAutomaticNextSet(context)
            ? context.state.nextExerciseKind ?? context.state.exerciseKind
            : context.state.exerciseKind
    }

    private func displayedTrackingMode(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        showsAutomaticNextSet(context)
            ? context.state.nextTrackingMode ?? context.state.trackingMode
            : context.state.trackingMode
    }

    private func displayedTargetReps(for context: ActivityViewContext<DamSetActivityAttributes>) -> Int {
        showsAutomaticNextSet(context)
            ? context.state.nextTargetReps ?? context.state.targetReps
            : context.state.targetReps
    }

    private func displayedTargetDuration(for context: ActivityViewContext<DamSetActivityAttributes>) -> Int {
        showsAutomaticNextSet(context)
            ? context.state.nextTargetDurationSeconds ?? context.state.targetDurationSeconds
            : context.state.targetDurationSeconds
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

    private func displayedActualDuration(for context: ActivityViewContext<DamSetActivityAttributes>) -> Int {
        showsAutomaticNextSet(context)
            ? displayedTargetDuration(for: context)
            : context.state.actualDurationSeconds
    }

    private func isDurationTracked(_ context: ActivityViewContext<DamSetActivityAttributes>) -> Bool {
        displayedTrackingMode(for: context) == ExerciseTrackingMode.duration.rawValue
    }

    private func displayedProgressValue(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        if isDurationTracked(context) {
            return durationText(displayedActualDuration(for: context))
        }
        return "\(displayedActualReps(for: context))"
    }

    private func displayedTargetValue(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        if isDurationTracked(context) {
            return durationText(displayedTargetDuration(for: context))
        }
        return "\(displayedTargetReps(for: context))"
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
                Text("Target \(displayedTargetValue(for: context))")
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
                Text(isDurationTracked(context) ? "Actual time" : "Actual reps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
                Spacer()
                Text("Target \(displayedTargetValue(for: context))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrainingPalette.secondary)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: 18)
    }

    /// − / reps / + / actual kg / Done or Next — every target ≥44pt so a
    /// sweaty thumb can hit it without unlocking. During rest, −/+ corrects
    /// the just-finished rep count and Next explicitly skips/finishes the
    /// rest. The compact actual-weight tile only appears for weighted work;
    /// bodyweight exercises keep the former, roomier layout.
    private func controlsRow(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(spacing: 9) {
            progressAdjustmentControls(context: context)

            if displayedExerciseKind(for: context) == ExerciseKind.weighted.rawValue {
                actualWeightMetric(context: context)
            }

            if context.state.phase == LockScreenPhase.performingSet.rawValue || showsAutomaticNextSet(context) {
                Button(intent: CompleteSetIntent(sessionId: context.attributes.sessionId)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 82, maxWidth: .infinity, minHeight: 44)
                        .background(TrainingPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete set")
            } else {
                Button(intent: AdvanceToNextSetIntent(sessionId: context.attributes.sessionId)) {
                    Label(restIsReady(context) ? "Next" : "Skip", systemImage: "forward.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 82, maxWidth: .infinity, minHeight: 44)
                        .background(TrainingPalette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(restIsReady(context) ? "Start next set" : "Skip rest and start next set")
            }
        }
    }

    @ViewBuilder
    private func progressAdjustmentControls(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        if isDurationTracked(context) {
            Button(intent: AdjustDurationIntent(sessionId: context.attributes.sessionId, deltaSeconds: -5)) {
                progressControlIcon("minus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease time by 5 seconds")

            actualDurationMetric(context: context)

            Button(intent: AdjustDurationIntent(sessionId: context.attributes.sessionId, deltaSeconds: 5)) {
                progressControlIcon("plus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase time by 5 seconds")
        } else {
            Button(intent: AdjustRepsIntent(sessionId: context.attributes.sessionId, delta: -1)) {
                progressControlIcon("minus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease reps")

            actualRepsMetric(context: context)

            Button(intent: AdjustRepsIntent(sessionId: context.attributes.sessionId, delta: 1)) {
                progressControlIcon("plus")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase reps")
        }
    }

    private func progressControlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(TrainingPalette.control, in: Circle())
    }

    /// Label the editable number so a just-finished set on the Rest screen is
    /// still unambiguously the actual rep count, rather than the set target.
    private func actualRepsMetric(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        VStack(spacing: 1) {
            Text(showsAutomaticNextSet(context) ? "TARGET REPS" : "ACTUAL REPS")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(TrainingPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("\(displayedActualReps(for: context))")
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(TrainingPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 52, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsAutomaticNextSet(context) ? "Target reps" : "Actual reps")
        .accessibilityValue("\(displayedActualReps(for: context))")
    }

    private func actualDurationMetric(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        VStack(spacing: 1) {
            Text(showsAutomaticNextSet(context) ? "TARGET TIME" : "ACTUAL TIME")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(TrainingPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(durationText(displayedActualDuration(for: context)))
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(TrainingPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 64, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsAutomaticNextSet(context) ? "Target time" : "Actual time")
        .accessibilityValue("\(displayedActualDuration(for: context)) seconds")
    }

    /// A compact read-only tile keeps the weighted-set's real load visible
    /// beside the editable rep value without spending a fourth row of the
    /// 160pt Lock Screen budget. At the instant the resting card becomes the
    /// next-set card, this intentionally changes to Target so it never claims
    /// an unperformed set already has an actual weight.
    private func actualWeightMetric(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        VStack(spacing: 1) {
            Text(showsAutomaticNextSet(context) ? "TARGET KG" : "ACTUAL KG")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(TrainingPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(displayedWeight(for: context).formatted())
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TrainingPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 56, height: 44)
        .background(TrainingPalette.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsAutomaticNextSet(context) ? "Target weight" : "Actual weight")
        .accessibilityValue("\(displayedWeight(for: context).formatted()) kilograms")
    }

    private func loadSummary(for context: ActivityViewContext<DamSetActivityAttributes>) -> String {
        if showsUpcomingExercise(context) {
            let isDuration = context.state.nextTrackingMode == ExerciseTrackingMode.duration.rawValue
            let target = isDuration
                ? durationText(context.state.nextTargetDurationSeconds ?? 0)
                : "\(context.state.nextTargetReps ?? 0) reps"
            if context.state.nextExerciseKind == ExerciseKind.bodyweight.rawValue {
                return "Up next · Bodyweight · target \(target)"
            }
            return "Up next · \((context.state.nextTargetWeight ?? 0).formatted()) kg · target \(target)"
        }

        let target = isDurationTracked(context)
            ? durationText(displayedTargetDuration(for: context))
            : "\(displayedTargetReps(for: context)) reps"
        if displayedExerciseKind(for: context) == ExerciseKind.bodyweight.rawValue {
            return "Bodyweight · target \(target)"
        }
        return "\(displayedWeight(for: context).formatted()) kg · target \(target)"
    }

    private func durationText(_ seconds: Int) -> String {
        let normalized = max(0, seconds)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
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
