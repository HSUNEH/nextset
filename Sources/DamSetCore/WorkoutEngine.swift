import Foundation

public enum WorkoutEngineError: Error, Equatable, Sendable {
    case routineHasNoSets
    case noActiveSet
    case sessionAlreadyCompleted
}

public enum RestCueDecision: Equatable, Sendable {
    case idealAudioAllowed
    case fallbackNotificationAndHaptics(reason: String)
}

public struct WorkoutEngine: Sendable {
    public init() {}

    public func startSession(routine: RoutineTemplate, now: Date = Date(), sessionId: String = UUID().uuidString) throws -> WorkoutRoutineSession {
        guard let firstSet = routine.plannedSets.first else { throw WorkoutEngineError.routineHasNoSets }
        let lockState = LockScreenState(
            exerciseName: firstSet.exerciseName,
            currentSetIndex: 1,
            totalPlannedSets: routine.plannedSets.count,
            targetReps: firstSet.targetReps,
            actualReps: firstSet.targetReps,
            canCompleteSet: true,
            restRemainingSeconds: 0,
            resumeAt: nil,
            phase: .performingSet
        )
        return WorkoutRoutineSession(
            sessionId: sessionId,
            routineId: routine.routineId,
            routineName: routine.routineName,
            plannedSets: routine.plannedSets,
            completedSets: [],
            currentSetIndex: 1,
            sessionStatus: .active,
            workoutStartTime: now,
            workoutEndTime: nil,
            lockScreenState: lockState,
            restCountdownCue: RestCountdownCue()
        )
    }

    public func adjustActualReps(session: inout WorkoutRoutineSession, delta: Int) throws {
        guard session.sessionStatus != .completed else { throw WorkoutEngineError.sessionAlreadyCompleted }
        let next = max(0, session.lockScreenState.actualReps + delta)
        session.lockScreenState.actualReps = next
        session.lockScreenState.canDecrementReps = next > 0
        session.lockScreenState.canIncrementReps = true
    }

    /// Completes the current set. `actualWeight` overrides the recorded weight when the user
    /// edited it in the app; when nil, the planned target weight is recorded per spec.
    public func completeCurrentSet(session: inout WorkoutRoutineSession, actualWeight: Double? = nil, now: Date = Date()) throws {
        guard session.sessionStatus != .completed else { throw WorkoutEngineError.sessionAlreadyCompleted }
        guard let planned = session.currentPlannedSet else { throw WorkoutEngineError.noActiveSet }

        let completed = CompletedSet(
            setId: planned.setId,
            exerciseName: planned.exerciseName,
            actualWeight: actualWeight ?? planned.targetWeight,
            actualReps: session.lockScreenState.actualReps,
            completedAt: now
        )
        session.completedSets.append(completed)

        if session.currentSetIndex >= session.plannedSets.count {
            session.sessionStatus = .completed
            session.workoutEndTime = now
            session.lockScreenState = LockScreenState(
                exerciseName: planned.exerciseName,
                currentSetIndex: session.currentSetIndex,
                totalPlannedSets: session.plannedSets.count,
                targetReps: planned.targetReps,
                actualReps: completed.actualReps,
                canCompleteSet: false,
                restRemainingSeconds: 0,
                resumeAt: nil,
                phase: .completed
            )
            return
        }

        let resumeAt = now.addingTimeInterval(TimeInterval(planned.restDurationSeconds))
        session.sessionStatus = .resting
        session.lockScreenState = LockScreenState(
            exerciseName: planned.exerciseName,
            currentSetIndex: session.currentSetIndex,
            totalPlannedSets: session.plannedSets.count,
            targetReps: planned.targetReps,
            actualReps: completed.actualReps,
            canCompleteSet: false,
            restRemainingSeconds: planned.restDurationSeconds,
            resumeAt: resumeAt,
            phase: .resting
        )
    }

    public func updateRest(session: inout WorkoutRoutineSession, now: Date = Date()) {
        guard session.sessionStatus == .resting, let resumeAt = session.lockScreenState.resumeAt else { return }
        let remaining = max(0, Int(ceil(resumeAt.timeIntervalSince(now))))
        session.lockScreenState.restRemainingSeconds = remaining
        if remaining == 0 {
            session.lockScreenState.phase = .readyForNextSet
        }
    }

    /// Brings a session up to date with wall-clock time. Once rest has fully
    /// elapsed the session advances to the next set, so a lock-screen action
    /// taken after the rest ended applies to the set the user is about to do.
    public func refresh(session: inout WorkoutRoutineSession, now: Date = Date()) {
        updateRest(session: &session, now: now)
        if session.lockScreenState.phase == .readyForNextSet {
            try? advanceToNextSet(session: &session)
        }
    }

    public func advanceToNextSet(session: inout WorkoutRoutineSession) throws {
        guard session.sessionStatus == .resting || session.lockScreenState.phase == .readyForNextSet else { return }
        let nextIndex = session.currentSetIndex + 1
        guard session.plannedSets.indices.contains(nextIndex - 1) else { throw WorkoutEngineError.noActiveSet }
        let nextSet = session.plannedSets[nextIndex - 1]
        session.currentSetIndex = nextIndex
        session.sessionStatus = .active
        session.lockScreenState = LockScreenState(
            exerciseName: nextSet.exerciseName,
            currentSetIndex: nextIndex,
            totalPlannedSets: session.plannedSets.count,
            targetReps: nextSet.targetReps,
            actualReps: nextSet.targetReps,
            canCompleteSet: true,
            restRemainingSeconds: 0,
            resumeAt: nil,
            phase: .performingSet
        )
    }

    public func addSessionScopedSet(session: inout WorkoutRoutineSession, exerciseName: String, targetWeight: Double, targetReps: Int, restDurationSeconds: Int) {
        let planned = PlannedSet(
            setId: "manual-\(UUID().uuidString)",
            exerciseName: exerciseName,
            targetWeight: targetWeight,
            targetReps: targetReps,
            restDurationSeconds: restDurationSeconds,
            manuallyAdded: true
        )
        session.plannedSets.append(planned)
        session.lockScreenState.totalPlannedSets = session.plannedSets.count
    }

    public func summarize(session: WorkoutRoutineSession, endedAt: Date = Date()) -> WorkoutSummary {
        WorkoutSummary(session: session, endedAt: endedAt)
    }

    public func decideRestCue(playbackWasPlaying: Bool, playbackStillPlayingAfterCue: Bool, iOSPolicyAllowsIdealCue: Bool) -> RestCueDecision {
        if playbackWasPlaying && playbackStillPlayingAfterCue && iOSPolicyAllowsIdealCue {
            return .idealAudioAllowed
        }
        return .fallbackNotificationAndHaptics(reason: "Ideal countdown audio must preserve playbackState=playing and comply with iOS policy")
    }
}
