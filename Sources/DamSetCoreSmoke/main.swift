import Foundation
import DamSetCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        FileHandle.standardError.write("Smoke failed: \(message)\n".data(using: .utf8)!)
        exit(1)
    }
}

let catalog = RoutineCatalog()
expect(catalog.routines.count >= 3, "catalog has at least three routines")
expect(catalog.routines.allSatisfy { !$0.plannedSets.isEmpty }, "default routines are non-empty")

let engine = WorkoutEngine()
let routine = catalog.routines[0]
var session = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0), sessionId: "smoke")
expect(session.sessionStatus == .active, "session starts active")
expect(session.lockScreenState.phase == .performingSet, "lock screen starts performing")
expect(session.workoutEndTime == nil, "workoutEndTime is nil while active")

try engine.adjustActualReps(session: &session, delta: -1)
let adjustedReps = session.lockScreenState.actualReps
try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))
expect(session.completedSets.count == 1, "completing set records one completed set")
expect(session.completedSets[0].actualReps == adjustedReps, "completed set preserves adjusted reps")
expect(session.sessionStatus == .resting, "non-final set starts rest")
expect(session.lockScreenState.resumeAt != nil, "resting state has resumeAt")

if let resumeAt = session.lockScreenState.resumeAt {
    engine.updateRest(session: &session, now: resumeAt)
}
expect(session.lockScreenState.phase == .readyForNextSet, "rest reaches ready state")
try engine.advanceToNextSet(session: &session)
expect(session.currentSetIndex == 2, "advance moves to second set")
expect(session.lockScreenState.phase == .performingSet, "next set returns to performing")

engine.addSessionScopedSet(session: &session, exerciseName: "Lateral Raise", targetWeight: 8, targetReps: 15, restDurationSeconds: 45)
expect(session.plannedSets.last?.manuallyAdded == true, "manual set is session-scoped")
expect(!catalog.routines.flatMap(\.plannedSets).contains { $0.manuallyAdded }, "catalog is not mutated by manual set")

let cue = engine.decideRestCue(playbackWasPlaying: true, playbackStillPlayingAfterCue: false, iOSPolicyAllowsIdealCue: true)
if case .fallbackNotificationAndHaptics(let reason) = cue {
    expect(!reason.isEmpty, "fallback has reason")
} else {
    expect(false, "interrupted playback should choose fallback")
}

// Set 2 of 4: canonical actual-weight adjustment and mid-rest countdown.
try engine.adjustActualWeight(session: &session, delta: 62.5 - session.lockScreenState.actualWeight)
try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 20))
expect(session.completedSets.last?.actualWeight == 62.5, "actual weight override is recorded")
expect(session.sessionStatus == .resting, "non-final set starts rest")

if let resumeAt = session.lockScreenState.resumeAt {
    engine.updateRest(session: &session, now: resumeAt.addingTimeInterval(-5))
    expect(session.lockScreenState.restRemainingSeconds == 5, "countdown reflects remaining rest")
    expect(session.lockScreenState.phase == .resting, "still resting mid-countdown")
    engine.updateRest(session: &session, now: resumeAt)
}
try engine.advanceToNextSet(session: &session)

// Finish the remaining sets and verify the summary invariants.
try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 30))
try engine.advanceToNextSet(session: &session)
try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 40))
expect(session.sessionStatus == .completed, "final set completes the session")
expect(session.workoutEndTime == Date(timeIntervalSince1970: 40), "completion stamps workoutEndTime")
expect(session.lockScreenState.phase == .completed, "lock screen reaches completed phase")

let summary = engine.summarize(session: session, endedAt: Date(timeIntervalSince1970: 40))
expect(summary.totalSets == session.completedSets.count, "totalSets equals completed count")
let expectedVolume = session.completedSets.reduce(0.0) { $0 + $1.actualWeight * Double($1.actualReps) }
expect(summary.totalVolume == expectedVolume, "totalVolume equals weight*reps sum")

// File store round-trip: a fresh instance on the same file must return the saved record.
let storeURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("damset-smoke-\(UUID().uuidString).json")
let store = FileWorkoutStore(fileURL: storeURL)
try store.save(summary)
let reloaded = FileWorkoutStore(fileURL: storeURL)
let roundTripped = try reloaded.summary(sessionId: summary.sessionId)
expect(roundTripped == summary, "summary round-trips by sessionId")
try store.save(summary)
let listed = try reloaded.allSummaries()
expect(listed.count == 1, "saving the same sessionId upserts instead of duplicating")
try? FileManager.default.removeItem(at: storeURL)

// Engine refresh only updates wall-clock rest. Advancing is an explicit action
// so the app and Lock Screen cannot silently skip the ready state.
var refreshSession = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0), sessionId: "refresh")
try engine.completeCurrentSet(session: &refreshSession, now: Date(timeIntervalSince1970: 5))
if let resumeAt = refreshSession.lockScreenState.resumeAt {
    engine.refresh(session: &refreshSession, now: resumeAt)
}
expect(refreshSession.currentSetIndex == 1, "refresh keeps the completed set selected")
expect(refreshSession.lockScreenState.phase == .readyForNextSet, "refresh exposes the ready state")
try engine.advanceToNextSet(session: &refreshSession)
expect(refreshSession.currentSetIndex == 2, "explicit advance moves to the next set")
expect(refreshSession.lockScreenState.phase == .performingSet, "explicit advance starts the next set")

// Active session store round-trip used for app <-> Live Activity intent sharing.
let sessionURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("damset-smoke-session-\(UUID().uuidString).json")
let sessionStore = ActiveSessionStore(fileURL: sessionURL)
try sessionStore.save(refreshSession)
let loadedSession = try ActiveSessionStore(fileURL: sessionURL).load()
expect(loadedSession == refreshSession, "active session round-trips through the shared store")
try sessionStore.clear()
let clearedSession = try ActiveSessionStore(fileURL: sessionURL).load()
expect(clearedSession == nil, "clear removes the shared session")

print("DamSetCoreSmoke ok")
