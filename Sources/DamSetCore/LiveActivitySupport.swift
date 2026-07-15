import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

#if os(iOS) && canImport(ActivityKit)
public struct DamSetActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var exerciseName: String
        public var currentSetIndex: Int
        public var totalPlannedSets: Int
        public var targetReps: Int
        public var actualReps: Int
        public var actualWeight: Double
        public var restRemainingSeconds: Int
        public var resumeAt: Date?
        public var phase: String

        public init(exerciseName: String, currentSetIndex: Int, totalPlannedSets: Int, targetReps: Int, actualReps: Int, actualWeight: Double, restRemainingSeconds: Int, resumeAt: Date?, phase: String) {
            self.exerciseName = exerciseName
            self.currentSetIndex = currentSetIndex
            self.totalPlannedSets = totalPlannedSets
            self.targetReps = targetReps
            self.actualReps = actualReps
            self.actualWeight = actualWeight
            self.restRemainingSeconds = restRemainingSeconds
            self.resumeAt = resumeAt
            self.phase = phase
        }

        public init(_ state: LockScreenState) {
            self.init(
                exerciseName: state.exerciseName,
                currentSetIndex: state.currentSetIndex,
                totalPlannedSets: state.totalPlannedSets,
                targetReps: state.targetReps,
                actualReps: state.actualReps,
                actualWeight: state.actualWeight,
                restRemainingSeconds: state.restRemainingSeconds,
                resumeAt: state.resumeAt,
                phase: state.phase.rawValue
            )
        }
    }

    public var sessionId: String
    public var routineName: String

    public init(sessionId: String, routineName: String) {
        self.sessionId = sessionId
        self.routineName = routineName
    }
}
#endif

/// Single side-effect pipeline shared by the app and the Live Activity intents:
/// persist the session to the App Group store, keep the Live Activity in sync,
/// and (re)schedule the rest-end cue. Off-iOS the Live Activity and cue calls
/// compile to no-ops so the SwiftPM shell target can type-check callers.
public enum WorkoutSessionSync {
    public static let appGroupId = "group.com.hsuneh.damset"

    /// Shared instances: each store serializes its read-modify-write cycles
    /// with an instance-level lock, so every caller in the process must go
    /// through the same instance for that lock to mean anything.
    public static let sessionStore = ActiveSessionStore(appGroupId: appGroupId)
    public static let summaryStore = FileWorkoutStore(appGroupId: appGroupId)
    public static let routineStore = FileRoutineTemplateStore(appGroupId: appGroupId)

    #if os(iOS) && canImport(ActivityKit)
    private static func activityContent(for session: WorkoutRoutineSession) -> ActivityContent<DamSetActivityAttributes.ContentState> {
        let lockState = session.lockScreenState
        let staleDate = lockState.phase == .resting ? lockState.resumeAt : nil
        return ActivityContent(
            state: DamSetActivityAttributes.ContentState(lockState),
            staleDate: staleDate
        )
    }
    #endif

    /// Starts the Live Activity for a session, or adopts an existing one after
    /// an app relaunch.
    public static func startLiveActivity(for session: WorkoutRoutineSession) {
        #if os(iOS) && canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = activityContent(for: session)
        if let existing = Activity<DamSetActivityAttributes>.activities.first(where: {
            $0.attributes.sessionId == session.sessionId
                && ($0.activityState == .active || $0.activityState == .stale)
        }) {
            Task { await existing.update(content) }
            return
        }
        let attributes = DamSetActivityAttributes(sessionId: session.sessionId, routineName: session.routineName)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        #endif
    }

    /// Pushes the session's lock-screen state to its Live Activity; ends the
    /// activity when the session is finished.
    public static func updateLiveActivity(for session: WorkoutRoutineSession) async {
        #if os(iOS) && canImport(ActivityKit)
        let content = activityContent(for: session)
        for activity in Activity<DamSetActivityAttributes>.activities where activity.attributes.sessionId == session.sessionId {
            if session.sessionStatus == .completed || session.sessionStatus == .cancelled {
                await activity.end(content, dismissalPolicy: .immediate)
            } else {
                await activity.update(content)
            }
        }
        #endif
    }

    public static func endAllLiveActivities() async {
        #if os(iOS) && canImport(ActivityKit)
        for activity in Activity<DamSetActivityAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
        #endif
    }

    /// Applies every side effect a session mutation requires. Call after each
    /// engine operation, whether it ran in the app or in a Live Activity intent.
    public static func applyDidChange(_ session: WorkoutRoutineSession) async throws {
        try await WorkoutSessionMutationGate.shared.apply(session)
    }

    /// Ends an in-progress workout without allowing an already-running Live
    /// Activity intent to write its stale snapshot back after the clear.
    public static func discardSession(sessionId: String) async throws {
        try await WorkoutSessionMutationGate.shared.discard(sessionId: sessionId)
    }

    /// Saves the completed portion of a workout and closes the active session
    /// as one coordinated terminal operation. The persisted session is read
    /// inside the gate so a just-finished Lock Screen action is included.
    public static func finishAndSaveCompletedSets(
        fallbackSession: WorkoutRoutineSession,
        store: LocalWorkoutStore
    ) async throws -> WorkoutSummary {
        try await WorkoutSessionMutationGate.shared.finishAndSaveCompletedSets(
            fallbackSession: fallbackSession,
            store: store
        )
    }

    /// Persists an Undo-reopened session behind a temporary barrier. The app
    /// gives it a fresh ID so the completed session's tombstone stays intact.
    public static func reopenCompletedSession(_ session: WorkoutRoutineSession) async throws {
        try await WorkoutSessionMutationGate.shared.reopenCompletedSession(session)
    }

    /// Persists before any ActivityKit await so the mutation actor keeps the
    /// load/save boundary linearizable even though actor methods are reentrant.
    fileprivate static func persistDidChange(_ session: WorkoutRoutineSession) throws {
        switch session.sessionStatus {
        case .completed:
            let summary = WorkoutEngine().summarize(session: session, endedAt: session.workoutEndTime ?? Date())
            // The active session is only cleared after the durable summary
            // succeeds. A caller can surface/retry either error without losing
            // the completed workout.
            try summaryStore.save(summary)
            try sessionStore.clear()
            RestCueScheduler.cancelPendingCues()
        case .cancelled:
            try sessionStore.clear()
            RestCueScheduler.cancelPendingCues()
        default:
            try sessionStore.save(session)
            if session.sessionStatus == .resting,
               session.lockScreenState.phase == .resting,
               let resumeAt = session.lockScreenState.resumeAt {
                RestCueScheduler.scheduleRestEndCue(resumeAt: resumeAt, upcomingExercise: session.nextPlannedSet?.exerciseName)
            } else if session.lockScreenState.phase == .performingSet {
                RestCueScheduler.cancelPendingCues()
            }
        }
    }
}

private enum WorkoutSessionMutationError: Error {
    case noCompletedSets
    case conflictingActiveSession
}

/// Serializes terminal app actions with Live Activity writes. Actor methods
/// can re-enter while ActivityKit is awaited, so a per-session barrier is set
/// before any terminal persistence starts and rejects stale in-flight writes.
private actor WorkoutSessionMutationGate {
    static let shared = WorkoutSessionMutationGate()

    private enum Barrier {
        case completing
        case completed
        case reopening
        case closed
    }

    private var barriers: [String: Barrier] = [:]

    func apply(_ session: WorkoutRoutineSession) async throws {
        guard barriers[session.sessionId] == nil else { return }

        let isTerminal = session.sessionStatus == .completed || session.sessionStatus == .cancelled
        if isTerminal {
            barriers[session.sessionId] = .completing
        }

        do {
            try WorkoutSessionSync.persistDidChange(session)
        } catch {
            if isTerminal, barriers[session.sessionId] == .completing {
                barriers.removeValue(forKey: session.sessionId)
            }
            throw error
        }

        if session.sessionStatus == .completed {
            if barriers[session.sessionId] == .completing {
                barriers[session.sessionId] = .completed
            }
        } else if session.sessionStatus == .cancelled {
            if barriers[session.sessionId] == .completing {
                barriers[session.sessionId] = .closed
            }
        }
        await WorkoutSessionSync.updateLiveActivity(for: session)
    }

    func discard(sessionId: String) async throws {
        if barriers[sessionId] == .closed { return }
        barriers[sessionId] = .closed

        do {
            if let stored = try WorkoutSessionSync.sessionStore.load(),
               stored.sessionId != sessionId {
                throw WorkoutSessionMutationError.conflictingActiveSession
            }
            try WorkoutSessionSync.sessionStore.clear()
            RestCueScheduler.cancelPendingCues()
            await WorkoutSessionSync.endAllLiveActivities()
        } catch {
            barriers.removeValue(forKey: sessionId)
            throw error
        }
    }

    func finishAndSaveCompletedSets(
        fallbackSession: WorkoutRoutineSession,
        store: LocalWorkoutStore
    ) async throws -> WorkoutSummary {
        let sessionId = fallbackSession.sessionId

        switch barriers[sessionId] {
        case .completing, .completed:
            if let existing = try store.summary(sessionId: sessionId) {
                return existing
            }
            if let canonical = try WorkoutSessionSync.summaryStore.summary(sessionId: sessionId) {
                try store.save(canonical)
                return canonical
            }
            throw WorkoutSessionMutationError.conflictingActiveSession
        case .closed:
            if let existing = try store.summary(sessionId: sessionId) {
                return existing
            }
            throw WorkoutSessionMutationError.conflictingActiveSession
        case .reopening:
            throw WorkoutSessionMutationError.conflictingActiveSession
        case nil:
            break
        }

        barriers[sessionId] = .closed

        var didSaveSummary = false
        do {
            let stored = try WorkoutSessionSync.sessionStore.load()
            if let stored, stored.sessionId != sessionId {
                throw WorkoutSessionMutationError.conflictingActiveSession
            }
            let latestSession = stored ?? fallbackSession
            guard !latestSession.completedSets.isEmpty else {
                throw WorkoutSessionMutationError.noCompletedSets
            }

            let summary = WorkoutEngine().summarize(session: latestSession, endedAt: Date())
            try store.save(summary)
            didSaveSummary = true
            try WorkoutSessionSync.sessionStore.clear()
            RestCueScheduler.cancelPendingCues()
            await WorkoutSessionSync.endAllLiveActivities()
            return summary
        } catch {
            if didSaveSummary {
                try? store.delete(sessionId: sessionId)
            }
            barriers.removeValue(forKey: sessionId)
            throw error
        }
    }

    func reopenCompletedSession(_ session: WorkoutRoutineSession) async throws {
        let previousBarrier = barriers[session.sessionId]
        if previousBarrier == .closed || previousBarrier == .reopening {
            throw WorkoutSessionMutationError.conflictingActiveSession
        }
        barriers[session.sessionId] = .reopening
        do {
            try WorkoutSessionSync.persistDidChange(session)
        } catch {
            barriers[session.sessionId] = previousBarrier ?? .completed
            throw error
        }
        await WorkoutSessionSync.updateLiveActivity(for: session)
        if barriers[session.sessionId] == .reopening {
            barriers.removeValue(forKey: session.sessionId)
        }
    }
}
