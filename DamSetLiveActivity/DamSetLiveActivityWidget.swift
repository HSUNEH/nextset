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

/// Wood-on-iron palette for the Lock Screen: warm oak accents on the black
/// activity background, tuned for glanceability mid-workout.
private enum WoodTone {
    static let oak = Color(red: 0.588, green: 0.408, blue: 0.247)
    static let oakBright = Color(red: 0.788, green: 0.616, blue: 0.443)
    static let amber = Color(red: 0.780, green: 0.480, blue: 0.230)
    static let moss = Color(red: 0.518, green: 0.643, blue: 0.333)

    /// Chrome bar finish for the Done CTA (matches DamSetDesign.steel).
    static let steel = LinearGradient(
        stops: [
            .init(color: Color(red: 0.95, green: 0.95, blue: 0.96), location: 0.0),
            .init(color: Color(red: 0.79, green: 0.80, blue: 0.82), location: 0.18),
            .init(color: Color(red: 0.56, green: 0.57, blue: 0.60), location: 0.42),
            .init(color: Color(red: 0.73, green: 0.74, blue: 0.76), location: 0.52),
            .init(color: Color(red: 0.49, green: 0.50, blue: 0.53), location: 0.68),
            .init(color: Color(red: 0.78, green: 0.79, blue: 0.81), location: 0.88),
            .init(color: Color(red: 0.62, green: 0.63, blue: 0.66), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Cast-iron plate face for the −/+ controls (matches DamSetDesign.ironPlate),
    /// lifted slightly so it separates from the black activity background.
    static let ironPlate = RadialGradient(
        colors: [
            Color(red: 0.33, green: 0.33, blue: 0.35),
            Color(red: 0.16, green: 0.16, blue: 0.17)
        ],
        center: .init(x: 0.35, y: 0.3),
        startRadius: 2,
        endRadius: 40
    )

    static let ironText = Color(red: 0.10, green: 0.10, blue: 0.11)
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
                            .foregroundStyle(WoodTone.oakBright)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isResting(context.state), let resumeAt = context.state.resumeAt {
                        Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(WoodTone.amber)
                            .frame(maxWidth: 72)
                    } else {
                        Text("\(context.state.actualReps)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(WoodTone.oakBright)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controlsRow(context: context)
                }
            } compactLeading: {
                Text("\(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                    .font(.caption2.bold())
                    .foregroundStyle(WoodTone.oakBright)
            } compactTrailing: {
                if isResting(context.state), let resumeAt = context.state.resumeAt {
                    Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(WoodTone.amber)
                        .frame(maxWidth: 44)
                } else {
                    Text("\(context.state.actualReps)")
                        .monospacedDigit()
                        .foregroundStyle(WoodTone.oakBright)
                }
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundStyle(WoodTone.oakBright)
            }
        }
    }

    private func isResting(_ state: DamSetActivityAttributes.ContentState) -> Bool {
        state.phase == LockScreenPhase.resting.rawValue || state.phase == LockScreenPhase.readyForNextSet.rawValue
    }

    /// Lock Screen layout, optimized for the between-sets glance: one line of
    /// context on top, the rest countdown as the loudest element while
    /// resting, and full-size record controls that are always tappable.
    private func lockScreenView(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WoodTone.oakBright)
                Text(context.state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text("Set \(context.state.currentSetIndex)/\(context.state.totalPlannedSets)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(WoodTone.oak.opacity(0.32), in: Capsule())
                    .foregroundStyle(WoodTone.oakBright)
            }

            if context.state.phase == LockScreenPhase.completed.rawValue {
                Label("Workout complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(WoodTone.moss)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                if isResting(context.state), let resumeAt = context.state.resumeAt {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(timerInterval: Date.now...max(Date.now, resumeAt), countsDown: true)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WoodTone.amber)
                            .frame(maxWidth: 110)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("rest · ready \(resumeAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("target \(context.state.targetReps) reps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                controlsRow(context: context)
            }
        }
        .padding(14)
    }

    /// − / did / + / Done — every target ≥44pt so a sweaty thumb can hit it
    /// without unlocking.
    private func controlsRow(context: ActivityViewContext<DamSetActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Button(intent: AdjustRepsIntent(delta: -1)) {
                Image(systemName: "minus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(WoodTone.ironPlate, in: Circle())
                    .overlay(Circle().inset(by: 7).stroke(.white.opacity(0.10), lineWidth: 1))
                    .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease reps")

            VStack(spacing: 0) {
                Text("\(context.state.targetReps)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("did \(context.state.actualReps)")
                    .font(.caption2)
                    .foregroundStyle(WoodTone.oakBright)
                    .monospacedDigit()
            }
            .frame(minWidth: 56)

            Button(intent: AdjustRepsIntent(delta: 1)) {
                Image(systemName: "plus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(WoodTone.ironPlate, in: Circle())
                    .overlay(Circle().inset(by: 7).stroke(.white.opacity(0.10), lineWidth: 1))
                    .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase reps")

            Button(intent: CompleteSetIntent()) {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(WoodTone.ironText)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(WoodTone.steel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.9), .white.opacity(0.1), .black.opacity(0.25)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete set")
        }
    }
}
#endif
