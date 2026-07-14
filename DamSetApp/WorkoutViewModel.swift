import Foundation
import Observation
import DamSetCore

@MainActor
@Observable
final class WorkoutViewModel {
    private let engine = WorkoutEngine()
    private let store: LocalWorkoutStore
    private let sessionStore = WorkoutSessionSync.sessionStore
    private let cuePlayer = InAppRestCuePlayer()
    let catalog = RoutineCatalog()
    var activeSession: WorkoutRoutineSession?
    var lastSummary: WorkoutSummary?
    var savedSummaries: [WorkoutSummary] = []
    var isCompletingSet = false
    var isClosingWorkout = false
    var errorMessage: String?
    @ObservationIgnored private var pendingSync: Task<Void, Never>?

    var isBusy: Bool { isCompletingSet || isClosingWorkout }

    init(store: LocalWorkoutStore = WorkoutSessionSync.summaryStore) {
        self.store = store
        reloadSummaries()
        adoptSharedSessionIfPresent()
    }

    func start(_ routine: RoutineTemplate) {
        guard !isBusy else { return }
        do {
            let session = try engine.startSession(routine: routine)
            activeSession = session
            lastSummary = nil
            cuePlayer.reset()
            RestCueScheduler.requestAuthorization()
            WorkoutSessionSync.startLiveActivity(for: session)
            sync(session)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func adjustReps(_ delta: Int) {
        guard !isBusy, var session = activeSession else { return }
        do {
            try engine.adjustActualReps(session: &session, delta: delta)
            activeSession = session
            sync(session)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func adjustWeight(_ delta: Double) {
        guard !isBusy, var session = activeSession else { return }
        do {
            try engine.adjustActualWeight(session: &session, delta: delta)
            activeSession = session
            sync(session)
        } catch {
            report(error, context: "Weight could not be updated")
        }
    }

    func completeSet() {
        guard !isBusy, var session = activeSession else { return }
        do {
            try engine.completeCurrentSet(session: &session)
            // Do not present rest/completion until the mutated session is
            // durably persisted. A failed save leaves the current set visible
            // so the user can retry without losing a completed set.
            isCompletingSet = true
            sync(session, completion: { [weak self] in
                guard let self else { return }
                self.activeSession = session
                self.cuePlayer.reset()
                if session.sessionStatus == .completed {
                    self.lastSummary = self.engine.summarize(
                        session: session,
                        endedAt: session.workoutEndTime ?? Date()
                    )
                    self.reloadSummaries()
                }
                self.isCompletingSet = false
            }, failure: { [weak self] in
                self?.isCompletingSet = false
            })
        } catch {
            report(error, context: "Set could not be completed")
        }
    }

    func advanceToNextSet() {
        guard !isBusy, var session = activeSession else { return }
        do {
            try engine.advanceToNextSet(session: &session)
            activeSession = session
            cuePlayer.reset()
            sync(session)
        } catch {
            report(error, context: "The next set could not be started")
        }
    }

    func repeatCurrentSet() {
        guard !isBusy, var session = activeSession, let planned = session.currentPlannedSet else { return }
        engine.addSessionScopedSet(
            session: &session,
            exerciseName: planned.exerciseName,
            targetWeight: planned.targetWeight,
            targetReps: planned.targetReps,
            restDurationSeconds: planned.restDurationSeconds
        )
        activeSession = session
        sync(session)
    }

    func tick(now: Date = Date()) {
        guard !isClosingWorkout, var session = activeSession, session.sessionStatus == .resting else { return }
        let previousPhase = session.lockScreenState.phase

        engine.refresh(session: &session, now: now)
        cuePlayer.handleRestTick(remainingSeconds: session.lockScreenState.restRemainingSeconds)

        if session != activeSession {
            activeSession = session
            // Countdown values are derived from resumeAt and only need to live
            // in memory. Persist/update ActivityKit on a meaningful phase edge.
            if previousPhase != session.lockScreenState.phase {
                sync(session)
            }
        }
    }

    func closeWorkout() {
        guard !isClosingWorkout else { return }
        isClosingWorkout = true
        let pending = self.pendingSync
        Task { [weak self] in
            guard let self else { return }
            await pending?.value
            do {
                try self.sessionStore.clear()
                RestCueScheduler.cancelPendingCues()
                await WorkoutSessionSync.endAllLiveActivities()
                self.activeSession = nil
                self.cuePlayer.reset()
            } catch {
                self.report(error, context: "Workout could not be closed")
            }
            self.isClosingWorkout = false
        }
    }

    /// Re-syncs with the App Group store after a Live Activity intent mutated
    /// the session while the app was backgrounded.
    func refreshFromSharedStore() {
        reloadSummaries()
        guard let current = activeSession else { return }
        do {
            if let stored = try sessionStore.load(), stored.sessionId == current.sessionId {
                if stored != current {
                    activeSession = stored
                    cuePlayer.reset()
                }
            } else if current.sessionStatus != .completed {
                // The intent finished the workout: session file is gone, summary saved.
                if let summary = try store.summary(sessionId: current.sessionId) {
                    lastSummary = summary
                    activeSession = completedSession(restoring: current, from: summary)
                } else {
                    // Keep the in-memory workout rather than discarding it when
                    // neither a shared session nor a durable summary exists.
                    errorMessage = "Workout state could not be recovered. Please try again."
                }
            }
        } catch {
            report(error, context: "Workout state could not be refreshed")
        }
    }

    private func adoptSharedSessionIfPresent() {
        do {
            guard let stored = try sessionStore.load(),
                  stored.sessionStatus != .completed, stored.sessionStatus != .cancelled else { return }
            activeSession = stored
            WorkoutSessionSync.startLiveActivity(for: stored)
        } catch {
            report(error, context: "Saved workout could not be restored")
        }
    }

    private func completedSession(
        restoring current: WorkoutRoutineSession,
        from summary: WorkoutSummary
    ) -> WorkoutRoutineSession {
        var finished = current
        finished.completedSets = summary.completedSets
        finished.sessionStatus = .completed
        finished.workoutStartTime = summary.workoutStartTime
        finished.workoutEndTime = summary.workoutEndTime

        if let lastCompleted = summary.completedSets.last,
           let zeroBasedIndex = finished.plannedSets.firstIndex(where: { $0.setId == lastCompleted.setId }) {
            let planned = finished.plannedSets[zeroBasedIndex]
            finished.currentSetIndex = zeroBasedIndex + 1
            finished.lockScreenState = .completed(
                after: planned,
                setIndex: zeroBasedIndex + 1,
                totalSets: finished.plannedSets.count,
                actualReps: lastCompleted.actualReps,
                actualWeight: lastCompleted.actualWeight
            )
        } else {
            finished.lockScreenState.phase = .completed
            finished.lockScreenState.canCompleteSet = false
        }
        return finished
    }

    /// Fire-and-forget propagation to the shared store / Live Activity / cues;
    /// `completion` runs on the main actor after the side effects land.
    private func sync(
        _ session: WorkoutRoutineSession,
        completion: (() -> Void)? = nil,
        failure: (() -> Void)? = nil
    ) {
        let previous = pendingSync
        pendingSync = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await WorkoutSessionSync.applyDidChange(session)
                completion?()
            } catch {
                self.report(error, context: "Workout changes could not be saved")
                failure?()
            }
        }
    }

    private func report(_ error: Error, context: String) {
        errorMessage = "\(context). \(String(describing: error))"
    }

    private func reloadSummaries() {
        do {
            savedSummaries = try store.allSummaries()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
