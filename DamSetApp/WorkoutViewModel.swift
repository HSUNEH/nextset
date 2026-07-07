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
    var actualWeight: Double = 0
    var errorMessage: String?

    init(store: LocalWorkoutStore = WorkoutSessionSync.summaryStore) {
        self.store = store
        reloadSummaries()
        adoptSharedSessionIfPresent()
    }

    func start(_ routine: RoutineTemplate) {
        do {
            let session = try engine.startSession(routine: routine)
            activeSession = session
            actualWeight = session.currentPlannedSet?.targetWeight ?? 0
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
        guard var session = activeSession else { return }
        do {
            try engine.adjustActualReps(session: &session, delta: delta)
            activeSession = session
            sync(session)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func adjustWeight(_ delta: Double) {
        actualWeight = max(0, actualWeight + delta)
    }

    func completeSet() {
        guard var session = activeSession else { return }
        do {
            try engine.completeCurrentSet(session: &session, actualWeight: actualWeight)
            activeSession = session
            cuePlayer.reset()
            if session.sessionStatus == .completed {
                lastSummary = engine.summarize(session: session, endedAt: session.workoutEndTime ?? Date())
                sync(session) { [weak self] in self?.reloadSummaries() }
            } else {
                sync(session)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func repeatCurrentSet() {
        guard var session = activeSession, let planned = session.currentPlannedSet else { return }
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
        guard var session = activeSession, session.sessionStatus == .resting else { return }
        let previousPhase = session.lockScreenState.phase
        let previousSetIndex = session.currentSetIndex

        engine.refresh(session: &session, now: now)
        cuePlayer.handleRestTick(remainingSeconds: session.lockScreenState.restRemainingSeconds)

        if session != activeSession {
            activeSession = session
            if session.currentSetIndex != previousSetIndex || session.lockScreenState.phase == .performingSet {
                actualWeight = session.currentPlannedSet?.targetWeight ?? actualWeight
            }
            if previousPhase != session.lockScreenState.phase {
                cuePlayer.reset()
            }
            sync(session)
        }
    }

    func closeWorkout() {
        activeSession = nil
        cuePlayer.reset()
        Task {
            RestCueScheduler.cancelPendingCues()
            try? sessionStore.clear()
            await WorkoutSessionSync.endAllLiveActivities()
        }
    }

    /// Re-syncs with the App Group store after a Live Activity intent mutated
    /// the session while the app was backgrounded.
    func refreshFromSharedStore() {
        reloadSummaries()
        guard let current = activeSession else { return }
        if let stored = try? sessionStore.load(), stored.sessionId == current.sessionId {
            if stored != current {
                activeSession = stored
                actualWeight = stored.currentPlannedSet?.targetWeight ?? actualWeight
                cuePlayer.reset()
            }
        } else if current.sessionStatus != .completed {
            // The intent finished the workout: session file is gone, summary saved.
            if let summary = try? store.summary(sessionId: current.sessionId) {
                lastSummary = summary
                var finished = current
                finished.sessionStatus = .completed
                finished.lockScreenState.phase = .completed
                finished.lockScreenState.canCompleteSet = false
                activeSession = finished
            } else {
                activeSession = nil
            }
        }
    }

    private func adoptSharedSessionIfPresent() {
        guard let stored = try? sessionStore.load(),
              stored.sessionStatus != .completed, stored.sessionStatus != .cancelled else { return }
        activeSession = stored
        actualWeight = stored.currentPlannedSet?.targetWeight ?? 0
        WorkoutSessionSync.startLiveActivity(for: stored)
    }

    /// Fire-and-forget propagation to the shared store / Live Activity / cues;
    /// `completion` runs on the main actor after the side effects land.
    private func sync(_ session: WorkoutRoutineSession, completion: (() -> Void)? = nil) {
        Task {
            await WorkoutSessionSync.applyDidChange(session)
            completion?()
        }
    }

    private func reloadSummaries() {
        do {
            savedSummaries = try store.allSummaries()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
