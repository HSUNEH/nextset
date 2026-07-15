import Foundation

public enum WorkoutEngineError: Error, Equatable, Sendable {
    case routineHasNoSets
    case noActiveSet
    case sessionAlreadyCompleted
    case invalidTransition
}

public enum RestCueDecision: Equatable, Sendable {
    case idealAudioAllowed
    case fallbackNotificationAndHaptics(reason: String)
}

public struct WorkoutEngine: Sendable {
    public init() {}

    public func startSession(routine: RoutineTemplate, now: Date = Date(), sessionId: String = UUID().uuidString) throws -> WorkoutRoutineSession {
        guard let firstSet = routine.plannedSets.first else { throw WorkoutEngineError.routineHasNoSets }
        let lockState = LockScreenState.performing(firstSet, setIndex: 1, totalSets: routine.plannedSets.count)
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
        try validateEditableProgress(session)
        let updatedReps = max(0, session.lockScreenState.actualReps + delta)
        if session.sessionStatus == .resting,
           let lastCompletedIndex = session.completedSets.indices.last {
            session.completedSets[lastCompletedIndex].actualReps = updatedReps
        } else if session.sessionStatus == .resting {
            throw WorkoutEngineError.noActiveSet
        }
        session.lockScreenState.actualReps = updatedReps
    }

    public func adjustActualWeight(session: inout WorkoutRoutineSession, delta: Double) throws {
        try validateEditableProgress(session)
        let updatedWeight = max(0, session.lockScreenState.actualWeight + delta)
        if session.sessionStatus == .resting,
           let lastCompletedIndex = session.completedSets.indices.last {
            session.completedSets[lastCompletedIndex].actualWeight = updatedWeight
        } else if session.sessionStatus == .resting {
            throw WorkoutEngineError.noActiveSet
        }
        session.lockScreenState.actualWeight = updatedWeight
    }

    /// Completes the active set using canonical progress from
    /// `lockScreenState`, shared by the app and Live Activity.
    public func completeCurrentSet(session: inout WorkoutRoutineSession, now: Date = Date()) throws {
        guard session.sessionStatus != .completed else { throw WorkoutEngineError.sessionAlreadyCompleted }
        guard session.sessionStatus == .active,
              session.lockScreenState.phase == .performingSet else {
            throw WorkoutEngineError.invalidTransition
        }
        guard let planned = session.currentPlannedSet else { throw WorkoutEngineError.noActiveSet }
        guard !session.completedSets.contains(where: { $0.setId == planned.setId }) else {
            throw WorkoutEngineError.invalidTransition
        }

        let completed = CompletedSet(
            setId: planned.setId,
            exerciseName: planned.exerciseName,
            actualWeight: session.lockScreenState.actualWeight,
            actualReps: session.lockScreenState.actualReps,
            completedAt: now
        )
        session.completedSets.append(completed)

        if session.currentSetIndex >= session.plannedSets.count {
            session.sessionStatus = .completed
            session.workoutEndTime = now
            session.lockScreenState = .completed(
                after: planned,
                setIndex: session.currentSetIndex,
                totalSets: session.plannedSets.count,
                actualReps: completed.actualReps,
                actualWeight: completed.actualWeight
            )
            return
        }

        session.sessionStatus = .resting
        session.lockScreenState = .resting(
            after: planned,
            setIndex: session.currentSetIndex,
            totalSets: session.plannedSets.count,
            actualReps: completed.actualReps,
            actualWeight: completed.actualWeight,
            resumeAt: now.addingTimeInterval(TimeInterval(planned.restDurationSeconds))
        )
    }

    /// Source-compatible bridge for older callers. New call sites should
    /// mutate weight through `adjustActualWeight` and use the canonical
    /// overload above.
    public func completeCurrentSet(
        session: inout WorkoutRoutineSession,
        actualWeight: Double?,
        now: Date = Date()
    ) throws {
        var updatedSession = session
        if let actualWeight {
            updatedSession.lockScreenState.actualWeight = max(0, actualWeight)
        }
        try completeCurrentSet(session: &updatedSession, now: now)
        session = updatedSession
    }

    public func updateRest(session: inout WorkoutRoutineSession, now: Date = Date()) {
        guard session.sessionStatus == .resting, let resumeAt = session.lockScreenState.resumeAt else { return }
        let remaining = restRemainingSeconds(until: resumeAt, now: now)
        session.lockScreenState.restRemainingSeconds = remaining
        if remaining == 0 {
            session.lockScreenState.phase = .readyForNextSet
        }
    }

    /// Changes the wall-clock rest deadline while keeping the rendered
    /// countdown and phase derived from that deadline. This also lets a user
    /// add time after the countdown has reached the ready state.
    public func adjustRest(
        session: inout WorkoutRoutineSession,
        deltaSeconds: Int,
        now: Date = Date()
    ) throws {
        guard session.sessionStatus == .resting,
              session.lockScreenState.phase == .resting
                || session.lockScreenState.phase == .readyForNextSet else {
            throw WorkoutEngineError.invalidTransition
        }

        let currentRemaining: Int
        if let resumeAt = session.lockScreenState.resumeAt {
            currentRemaining = restRemainingSeconds(until: resumeAt, now: now)
        } else {
            currentRemaining = max(0, session.lockScreenState.restRemainingSeconds)
        }

        let (unclampedRemaining, overflowed) = currentRemaining.addingReportingOverflow(deltaSeconds)
        let adjustedRemaining: Int
        if overflowed {
            adjustedRemaining = deltaSeconds > 0 ? Int.max : 0
        } else {
            adjustedRemaining = max(0, unclampedRemaining)
        }

        session.lockScreenState.restRemainingSeconds = adjustedRemaining
        session.lockScreenState.resumeAt = now.addingTimeInterval(TimeInterval(adjustedRemaining))
        session.lockScreenState.phase = adjustedRemaining == 0 ? .readyForNextSet : .resting
    }

    /// Brings the wall-clock countdown up to date without changing sets. The
    /// user explicitly advances (or skips rest) through `advanceToNextSet`.
    public func refresh(session: inout WorkoutRoutineSession, now: Date = Date()) {
        updateRest(session: &session, now: now)
    }

    public func advanceToNextSet(session: inout WorkoutRoutineSession) throws {
        guard session.sessionStatus == .resting,
              session.lockScreenState.phase == .resting
                || session.lockScreenState.phase == .readyForNextSet else {
            throw WorkoutEngineError.invalidTransition
        }
        guard let nextSet = session.nextPlannedSet else { throw WorkoutEngineError.noActiveSet }
        let nextIndex = session.currentSetIndex + 1
        session.currentSetIndex = nextIndex
        session.sessionStatus = .active
        session.lockScreenState = .performing(nextSet, setIndex: nextIndex, totalSets: session.plannedSets.count)
    }

    /// Reopens the set that was just completed, preserving the recorded reps
    /// and weight so an accidental completion can be corrected without loss.
    public func undoLastCompletedSet(session: inout WorkoutRoutineSession) throws {
        let canUndoDuringRest = session.sessionStatus == .resting
            && (session.lockScreenState.phase == .resting
                || session.lockScreenState.phase == .readyForNextSet)
        let canUndoCompletedSession = session.sessionStatus == .completed
            && session.lockScreenState.phase == .completed
        guard canUndoDuringRest || canUndoCompletedSession else {
            throw WorkoutEngineError.invalidTransition
        }
        guard let planned = session.currentPlannedSet,
              let completed = session.completedSets.last else {
            throw WorkoutEngineError.noActiveSet
        }
        guard completed.setId == planned.setId else {
            throw WorkoutEngineError.invalidTransition
        }

        session.completedSets.removeLast()
        session.sessionStatus = .active
        session.workoutEndTime = nil
        session.lockScreenState = .performing(
            planned,
            setIndex: session.currentSetIndex,
            totalSets: session.plannedSets.count
        )
        session.lockScreenState.actualReps = completed.actualReps
        session.lockScreenState.actualWeight = completed.actualWeight
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
        let insertionIndex: Int
        if session.plannedSets.indices.contains(session.currentSetIndex - 1) {
            insertionIndex = session.currentSetIndex
        } else {
            insertionIndex = session.plannedSets.endIndex
        }
        session.plannedSets.insert(planned, at: insertionIndex)
        session.lockScreenState.totalPlannedSets = session.plannedSets.count

        // A set added immediately after completing the original last set makes
        // that session actionable again. Treat it as a zero-second rest so the
        // existing next-set transition remains the single way to advance.
        if session.sessionStatus == .completed {
            session.sessionStatus = .resting
            session.workoutEndTime = nil
            session.lockScreenState.canCompleteSet = false
            session.lockScreenState.restRemainingSeconds = 0
            session.lockScreenState.resumeAt = nil
            session.lockScreenState.phase = .readyForNextSet
        }
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

    private func validateEditableProgress(_ session: WorkoutRoutineSession) throws {
        guard session.sessionStatus != .completed else {
            throw WorkoutEngineError.sessionAlreadyCompleted
        }
        let isPerforming = session.sessionStatus == .active
            && session.lockScreenState.phase == .performingSet
        let isCorrectingCompletedSet = session.sessionStatus == .resting
            && (session.lockScreenState.phase == .resting
                || session.lockScreenState.phase == .readyForNextSet)
        guard isPerforming || isCorrectingCompletedSet else {
            throw WorkoutEngineError.invalidTransition
        }
    }

    private func restRemainingSeconds(until resumeAt: Date, now: Date) -> Int {
        let interval = max(0, resumeAt.timeIntervalSince(now))
        guard interval < Double(Int.max) else { return Int.max }
        return Int(ceil(interval))
    }
}
