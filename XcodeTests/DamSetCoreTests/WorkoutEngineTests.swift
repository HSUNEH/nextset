import XCTest
@testable import DamSetCore

final class WorkoutEngineTests: XCTestCase {
    func testCatalogContainsAtLeastThreeDefaultRoutines() {
        XCTAssertGreaterThanOrEqual(RoutineCatalog.defaultRoutines.count, 3)
        XCTAssertTrue(RoutineCatalog.defaultRoutines.allSatisfy { !$0.plannedSets.isEmpty })
    }

    func testStartSessionSeedsLockScreenStateFromFirstSet() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let session = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0), sessionId: "s1")

        XCTAssertEqual(session.sessionId, "s1")
        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(session.currentSetIndex, 1)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertEqual(session.lockScreenState.targetReps, routine.plannedSets[0].targetReps)
        XCTAssertEqual(session.lockScreenState.actualReps, routine.plannedSets[0].targetReps)
        XCTAssertNil(session.workoutEndTime)
    }

    func testAdjustActualRepsClampsAtZero() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        try engine.adjustActualReps(session: &session, delta: -999)

        XCTAssertEqual(session.lockScreenState.actualReps, 0)
        XCTAssertFalse(session.lockScreenState.canDecrementReps)
    }

    func testCompleteSetRecordsSetAndStartsRestTimer() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let now = Date(timeIntervalSince1970: 100)
        var session = try engine.startSession(routine: routine)
        try engine.adjustActualReps(session: &session, delta: -1)

        try engine.completeCurrentSet(session: &session, now: now)

        XCTAssertEqual(session.completedSets.count, 1)
        XCTAssertEqual(session.completedSets[0].actualWeight, routine.plannedSets[0].targetWeight)
        XCTAssertEqual(session.completedSets[0].actualReps, max(0, routine.plannedSets[0].targetReps - 1))
        XCTAssertEqual(session.sessionStatus, .resting)
        XCTAssertEqual(session.lockScreenState.phase, .resting)
        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, routine.plannedSets[0].restDurationSeconds)
        XCTAssertEqual(session.lockScreenState.resumeAt, now.addingTimeInterval(TimeInterval(routine.plannedSets[0].restDurationSeconds)))
    }

    func testRestCountdownBecomesReadyAndAdvancesToNextSet() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let now = Date(timeIntervalSince1970: 100)
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: now)

        engine.updateRest(session: &session, now: now.addingTimeInterval(TimeInterval(routine.plannedSets[0].restDurationSeconds)))
        XCTAssertEqual(session.lockScreenState.phase, .readyForNextSet)
        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, 0)

        try engine.advanceToNextSet(session: &session)
        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertNil(session.lockScreenState.resumeAt)
    }

    func testSummaryCalculatesTotalSetsAndVolume() throws {
        let routine = RoutineTemplate(
            routineId: "test",
            routineName: "Test",
            plannedSets: [
                PlannedSet(setId: "a", exerciseName: "Bench", targetWeight: 10, targetReps: 3, restDurationSeconds: 0),
                PlannedSet(setId: "b", exerciseName: "Bench", targetWeight: 20, targetReps: 4, restDurationSeconds: 0)
            ]
        )
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0), sessionId: "s")
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 1))
        try engine.advanceToNextSet(session: &session)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 2))

        let summary = engine.summarize(session: session, endedAt: Date(timeIntervalSince1970: 3))

        XCTAssertEqual(summary.totalSets, 2)
        XCTAssertEqual(summary.totalVolume, 110)
        XCTAssertEqual(summary.workoutEndTime, Date(timeIntervalSince1970: 3))
    }

    func testManualSetsAreSessionScopedOnly() throws {
        let catalog = RoutineCatalog()
        let routine = try XCTUnwrap(catalog.routines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        engine.addSessionScopedSet(session: &session, exerciseName: "Lateral Raise", targetWeight: 8, targetReps: 15, restDurationSeconds: 45)

        XCTAssertEqual(session.plannedSets.last?.manuallyAdded, true)
        XCTAssertFalse(catalog.routines.flatMap(\.plannedSets).contains { $0.manuallyAdded })
    }

    func testCompleteSetRecordsActualWeightOverride() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        try engine.completeCurrentSet(session: &session, actualWeight: 62.5, now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(session.completedSets.last?.actualWeight, 62.5)
    }

    func testUpdateRestCountsDownMidRest() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 100))
        let resumeAt = try XCTUnwrap(session.lockScreenState.resumeAt)

        engine.updateRest(session: &session, now: resumeAt.addingTimeInterval(-5))

        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, 5)
        XCTAssertEqual(session.lockScreenState.phase, .resting)
    }

    func testFileStoreRoundTripsAndUpsertsBySessionId() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0), sessionId: "file-store")
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))
        let summary = engine.summarize(session: session, endedAt: Date(timeIntervalSince1970: 20))

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = FileWorkoutStore(fileURL: fileURL)
        try store.save(summary)
        try store.save(summary)

        let reloaded = FileWorkoutStore(fileURL: fileURL)
        XCTAssertEqual(try reloaded.summary(sessionId: "file-store"), summary)
        XCTAssertEqual(try reloaded.allSummaries().count, 1)
    }

    func testRefreshAdvancesPastElapsedRest() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0))
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 5))
        let resumeAt = try XCTUnwrap(session.lockScreenState.resumeAt)

        engine.refresh(session: &session, now: resumeAt)

        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertEqual(session.sessionStatus, .active)
    }

    func testActiveSessionStoreRoundTripsAndClears() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0), sessionId: "shared")
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 5))

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-tests-session-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = ActiveSessionStore(fileURL: fileURL)
        try store.save(session)
        XCTAssertEqual(try ActiveSessionStore(fileURL: fileURL).load(), session)

        try store.clear()
        XCTAssertNil(try ActiveSessionStore(fileURL: fileURL).load())
    }

    func testRestCueDecisionRequiresPlayingBeforeAndAfter() {
        let engine = WorkoutEngine()
        XCTAssertEqual(engine.decideRestCue(playbackWasPlaying: true, playbackStillPlayingAfterCue: true, iOSPolicyAllowsIdealCue: true), .idealAudioAllowed)

        let fallback = engine.decideRestCue(playbackWasPlaying: true, playbackStillPlayingAfterCue: false, iOSPolicyAllowsIdealCue: true)
        if case .fallbackNotificationAndHaptics(let reason) = fallback {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected fallback when playback is interrupted")
        }
    }
}
