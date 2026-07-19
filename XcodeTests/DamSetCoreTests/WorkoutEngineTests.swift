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
        XCTAssertEqual(session.lockScreenState.actualWeight, routine.plannedSets[0].targetWeight)
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
        XCTAssertEqual(session.lockScreenState.actualWeight, routine.plannedSets[0].targetWeight)
        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, routine.plannedSets[0].restDurationSeconds)
        XCTAssertEqual(session.lockScreenState.resumeAt, now.addingTimeInterval(TimeInterval(routine.plannedSets[0].restDurationSeconds)))
    }

    func testAdjustActualRepsDuringRestCorrectsCompletedSet() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 100))

        try engine.adjustActualReps(session: &session, delta: 2)

        XCTAssertEqual(session.lockScreenState.actualReps, routine.plannedSets[0].targetReps + 2)
        XCTAssertEqual(session.completedSets.last?.actualReps, routine.plannedSets[0].targetReps + 2)
        XCTAssertEqual(session.lockScreenState.phase, .resting)
    }

    func testActualWeightIsCanonicalDuringRestAndAfterAutomaticNextSet() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let now = Date(timeIntervalSince1970: 100)
        var session = try engine.startSession(routine: routine)

        try engine.adjustActualWeight(session: &session, delta: 2.5)
        try engine.completeCurrentSet(session: &session, now: now)

        XCTAssertEqual(session.completedSets.last?.actualWeight, routine.plannedSets[0].targetWeight + 2.5)
        XCTAssertEqual(session.lockScreenState.actualWeight, routine.plannedSets[0].targetWeight + 2.5)

        try engine.adjustActualWeight(session: &session, delta: -1)
        XCTAssertEqual(session.completedSets.last?.actualWeight, routine.plannedSets[0].targetWeight + 1.5)
        XCTAssertEqual(session.lockScreenState.actualWeight, routine.plannedSets[0].targetWeight + 1.5)

        let resumeAt = try XCTUnwrap(session.lockScreenState.resumeAt)
        engine.refresh(session: &session, now: resumeAt)
        try engine.adjustActualWeight(session: &session, delta: 0.5)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.lockScreenState.actualWeight, routine.plannedSets[1].targetWeight + 0.5)
        XCTAssertEqual(session.completedSets.last?.actualWeight, routine.plannedSets[0].targetWeight + 1.5)
    }

    func testRestCountdownAutomaticallyStartsNextSet() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let now = Date(timeIntervalSince1970: 100)
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: now)

        engine.updateRest(session: &session, now: now.addingTimeInterval(TimeInterval(routine.plannedSets[0].restDurationSeconds)))
        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, 0)
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
        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
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

        XCTAssertEqual(session.plannedSets[1].exerciseName, "Lateral Raise")
        XCTAssertEqual(session.plannedSets[1].manuallyAdded, true)
        XCTAssertEqual(session.nextPlannedSet, session.plannedSets[1])
        XCTAssertEqual(session.lockScreenState.totalPlannedSets, routine.plannedSets.count + 1)
        XCTAssertFalse(catalog.routines.flatMap(\.plannedSets).contains { $0.manuallyAdded })
    }

    func testSessionScopedSetInsertedAfterCurrentSetDuringRest() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))

        engine.addSessionScopedSet(
            session: &session,
            exerciseName: "Cable Fly",
            targetWeight: 20,
            targetReps: 12,
            restDurationSeconds: 60
        )

        XCTAssertEqual(session.currentSetIndex, 1)
        XCTAssertEqual(session.currentPlannedSet?.setId, routine.plannedSets[0].setId)
        XCTAssertEqual(session.nextPlannedSet?.exerciseName, "Cable Fly")
        XCTAssertEqual(session.lockScreenState.totalPlannedSets, routine.plannedSets.count + 1)
        XCTAssertEqual(session.sessionStatus, .resting)
        XCTAssertEqual(session.lockScreenState.phase, .resting)
    }

    func testAddingSetAfterCompletedSessionStartsItImmediately() throws {
        let routine = RoutineTemplate(
            routineId: "one-set-add",
            routineName: "One Set",
            plannedSets: [
                PlannedSet(setId: "only", exerciseName: "Squat", targetWeight: 100, targetReps: 5, restDurationSeconds: 60)
            ]
        )
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))

        engine.addSessionScopedSet(
            session: &session,
            exerciseName: "Back-off Squat",
            targetWeight: 80,
            targetReps: 8,
            restDurationSeconds: 60
        )

        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertNil(session.workoutEndTime)
        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.currentPlannedSet?.exerciseName, "Back-off Squat")
        XCTAssertEqual(session.lockScreenState.totalPlannedSets, 2)
    }

    func testAdjustRestUsesWallClockRemainingAndUpdatesDeadline() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        let completedAt = Date(timeIntervalSince1970: 100)
        try engine.completeCurrentSet(session: &session, now: completedAt)

        let adjustmentTime = Date(timeIntervalSince1970: 130)
        try engine.adjustRest(session: &session, deltaSeconds: 30, now: adjustmentTime)

        let expectedRemaining = routine.plannedSets[0].restDurationSeconds
        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, expectedRemaining)
        XCTAssertEqual(
            session.lockScreenState.resumeAt,
            adjustmentTime.addingTimeInterval(TimeInterval(expectedRemaining))
        )
        XCTAssertEqual(session.lockScreenState.phase, .resting)
    }

    func testAdjustRestToZeroAutomaticallyStartsNextSet() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        let completedAt = Date(timeIntervalSince1970: 100)
        try engine.completeCurrentSet(session: &session, now: completedAt)

        let adjustmentTime = Date(timeIntervalSince1970: 130)
        try engine.adjustRest(session: &session, deltaSeconds: -999, now: adjustmentTime)

        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, 0)
        XCTAssertNil(session.lockScreenState.resumeAt)
        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
    }

    func testUndoLastCompletedSetRestoresPerformingProgress() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.adjustActualReps(session: &session, delta: -2)
        try engine.adjustActualWeight(session: &session, delta: 2.5)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))

        try engine.undoLastCompletedSet(session: &session)

        XCTAssertTrue(session.completedSets.isEmpty)
        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(session.currentSetIndex, 1)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertEqual(session.lockScreenState.actualReps, routine.plannedSets[0].targetReps - 2)
        XCTAssertEqual(session.lockScreenState.actualWeight, routine.plannedSets[0].targetWeight + 2.5)
        XCTAssertTrue(session.lockScreenState.canCompleteSet)
        XCTAssertNil(session.lockScreenState.resumeAt)
    }

    func testUndoOnlySetReopensCompletedSession() throws {
        let routine = RoutineTemplate(
            routineId: "one-set-undo",
            routineName: "One Set",
            plannedSets: [
                PlannedSet(setId: "only", exerciseName: "Squat", targetWeight: 100, targetReps: 5, restDurationSeconds: 60)
            ]
        )
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))

        try engine.undoLastCompletedSet(session: &session)

        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertNil(session.workoutEndTime)
        XCTAssertTrue(session.completedSets.isEmpty)
        XCTAssertEqual(session.currentSetIndex, 1)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertEqual(session.lockScreenState.actualReps, 5)
        XCTAssertEqual(session.lockScreenState.actualWeight, 100)
    }

    func testCompleteSetRecordsCanonicalActualWeight() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        try engine.adjustActualWeight(session: &session, delta: 2.5)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(session.completedSets.last?.actualWeight, 62.5)
    }

    func testCompleteSetRejectsDuplicateCompletionDuringRest() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10))

        XCTAssertThrowsError(
            try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 11))
        ) { error in
            XCTAssertEqual(error as? WorkoutEngineError, .invalidTransition)
        }
        XCTAssertEqual(session.completedSets.count, 1)
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

    func testRestDurationAppliesWhenMovingBetweenDifferentExercises() throws {
        let routine = RoutineTemplate(
            routineId: "exercise-boundary-rest",
            routineName: "Boundary Rest",
            plannedSets: [
                PlannedSet(
                    setId: "bench-last",
                    exerciseName: "Bench Press",
                    targetWeight: 60,
                    targetReps: 8,
                    restDurationSeconds: 135
                ),
                PlannedSet(
                    setId: "row-first",
                    exerciseName: "Barbell Row",
                    targetWeight: 50,
                    targetReps: 10,
                    restDurationSeconds: 60
                )
            ]
        )
        let engine = WorkoutEngine()
        let completedAt = Date(timeIntervalSince1970: 1_000)
        var session = try engine.startSession(routine: routine)

        try engine.completeCurrentSet(session: &session, now: completedAt)

        XCTAssertEqual(session.sessionStatus, .resting)
        XCTAssertEqual(session.nextPlannedSet?.exerciseName, "Barbell Row")
        XCTAssertEqual(session.lockScreenState.restRemainingSeconds, 135)
        XCTAssertEqual(
            session.lockScreenState.resumeAt,
            completedAt.addingTimeInterval(135)
        )
    }

    func testFileStoreRoundTripsAndUpsertsBySessionId() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine, now: Date(timeIntervalSince1970: 0.125), sessionId: "file-store")
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 10.375))
        let summary = engine.summarize(session: session, endedAt: Date(timeIntervalSince1970: 20.875))

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

    func testInMemoryWorkoutStoreDeleteRemovesOnlyMatchingSession() throws {
        let first = try makeSummary(sessionId: "memory-first", endedAt: 10)
        let second = try makeSummary(sessionId: "memory-second", endedAt: 20)
        let store = InMemoryWorkoutStore()
        try store.save(first)
        try store.save(second)

        try store.delete(sessionId: first.sessionId)

        XCTAssertNil(try store.summary(sessionId: first.sessionId))
        XCTAssertEqual(try store.summary(sessionId: second.sessionId), second)
        XCTAssertEqual(try store.allSummaries(), [second])
    }

    func testFileWorkoutStoreDeletePersistsAndKeepsOtherSessions() throws {
        let first = try makeSummary(sessionId: "file-first", endedAt: 10)
        let second = try makeSummary(sessionId: "file-second", endedAt: 20)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-tests-delete-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = FileWorkoutStore(fileURL: fileURL)
        try store.save(first)
        try store.save(second)
        try store.delete(sessionId: first.sessionId)

        let reloaded = FileWorkoutStore(fileURL: fileURL)
        XCTAssertNil(try reloaded.summary(sessionId: first.sessionId))
        XCTAssertEqual(try reloaded.summary(sessionId: second.sessionId), second)
        XCTAssertEqual(try reloaded.allSummaries(), [second])
    }

    func testRefreshAutomaticallyStartsNextSetWhenRestExpires() throws {
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

    func testActiveSessionStoreReadsLegacyISO8601Dates() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(
            routine: routine,
            now: Date(timeIntervalSince1970: 0),
            sessionId: "legacy-date"
        )
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 5))

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-tests-legacy-date-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        try legacyEncoder.encode(session).write(to: fileURL, options: .atomic)

        XCTAssertEqual(try ActiveSessionStore(fileURL: fileURL).load(), session)
    }

    func testActiveSessionStoreMigratesMissingCanonicalWeight() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine, sessionId: "legacy")
        try engine.adjustActualWeight(session: &session, delta: 2.5)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 5.25))

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-tests-legacy-session-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = ActiveSessionStore(fileURL: fileURL)
        try store.save(session)

        let data = try Data(contentsOf: fileURL)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var lockState = try XCTUnwrap(json["lockScreenState"] as? [String: Any])
        lockState.removeValue(forKey: "actualWeight")
        json["lockScreenState"] = lockState
        try JSONSerialization.data(withJSONObject: json).write(to: fileURL, options: .atomic)

        let migrated = try XCTUnwrap(try ActiveSessionStore(fileURL: fileURL).load())
        XCTAssertEqual(migrated.lockScreenState.actualWeight, 62.5)
        XCTAssertEqual(migrated.completedSets.last?.actualWeight, 62.5)
    }

    func testActiveSessionStoreMigratesMissingDurationFieldsAsReps() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine, sessionId: "legacy-duration")
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 5))

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-tests-legacy-duration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = ActiveSessionStore(fileURL: fileURL)
        try store.save(session)

        let data = try Data(contentsOf: fileURL)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var planned = try XCTUnwrap(json["plannedSets"] as? [[String: Any]])
        for index in planned.indices {
            planned[index].removeValue(forKey: "trackingMode")
            planned[index].removeValue(forKey: "targetDurationSeconds")
        }
        json["plannedSets"] = planned

        var completed = try XCTUnwrap(json["completedSets"] as? [[String: Any]])
        for index in completed.indices {
            completed[index].removeValue(forKey: "trackingMode")
            completed[index].removeValue(forKey: "actualDurationSeconds")
        }
        json["completedSets"] = completed

        var lockState = try XCTUnwrap(json["lockScreenState"] as? [String: Any])
        lockState.removeValue(forKey: "trackingMode")
        lockState.removeValue(forKey: "targetDurationSeconds")
        lockState.removeValue(forKey: "actualDurationSeconds")
        json["lockScreenState"] = lockState
        try JSONSerialization.data(withJSONObject: json).write(to: fileURL, options: .atomic)

        let migrated = try XCTUnwrap(try ActiveSessionStore(fileURL: fileURL).load())
        XCTAssertTrue(migrated.plannedSets.allSatisfy { $0.trackingMode == .reps })
        XCTAssertTrue(migrated.completedSets.allSatisfy { $0.trackingMode == .reps })
        XCTAssertEqual(migrated.lockScreenState.trackingMode, .reps)
        XCTAssertEqual(migrated.lockScreenState.targetDurationSeconds, 0)
        XCTAssertEqual(migrated.lockScreenState.actualDurationSeconds, 0)
    }

    func testCompletedSessionRejectsProgressCorrections() throws {
        let routine = RoutineTemplate(
            routineId: "one-set",
            routineName: "One Set",
            plannedSets: [
                PlannedSet(setId: "only", exerciseName: "Squat", targetWeight: 100, targetReps: 5, restDurationSeconds: 60)
            ]
        )
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session)

        XCTAssertEqual(session.lockScreenState.actualWeight, 100)
        XCTAssertThrowsError(try engine.adjustActualReps(session: &session, delta: 1))
        XCTAssertThrowsError(try engine.adjustActualWeight(session: &session, delta: 2.5))
    }

    func testRestCuePlanSchedulesOnlyAnActiveRestDeadline() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let completedAt = Date(timeIntervalSince1970: 100)
        var session = try engine.startSession(routine: routine)

        try engine.completeCurrentSet(session: &session, now: completedAt)

        XCTAssertEqual(
            RestCueScheduler.plan(for: session),
            .schedule(
                resumeAt: completedAt.addingTimeInterval(
                    TimeInterval(routine.plannedSets[0].restDurationSeconds)
                ),
                upcomingExercise: routine.plannedSets[1].exerciseName
            )
        )
    }

    func testRestCuePlanCancelsWhenRestAutomaticallyStartsNextSet() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 100))

        try engine.adjustRest(
            session: &session,
            deltaSeconds: -999,
            now: Date(timeIntervalSince1970: 110)
        )

        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        XCTAssertEqual(session.sessionStatus, .active)
        XCTAssertEqual(RestCueScheduler.plan(for: session), .cancel)
    }

    func testRestCuePlanCancelsOutsideRest() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let session = try engine.startSession(routine: routine)

        XCTAssertEqual(RestCueScheduler.plan(for: session), .cancel)
    }

    func testRestCueNotificationUsesOneCombinedCountdownSound() {
        let spec = RestCueScheduler.notificationSpec(
            resumeAt: Date(timeIntervalSince1970: 100),
            upcomingExercise: "Bench Press",
            now: Date(timeIntervalSince1970: 90)
        )

        XCTAssertEqual(
            spec,
            RestCueNotificationSpec(
                identifier: "damset.restcue.countdown",
                title: "Next set in 3…",
                body: "Bench Press",
                delay: 7,
                soundFileName: "RestCountdown.wav"
            )
        )
    }

    func testRestCueNotificationUsesStandaloneGoSoundForShortRest() {
        let spec = RestCueScheduler.notificationSpec(
            resumeAt: Date(timeIntervalSince1970: 100),
            upcomingExercise: nil,
            now: Date(timeIntervalSince1970: 98)
        )

        XCTAssertEqual(spec?.identifier, "damset.restcue.start")
        XCTAssertEqual(spec?.delay, 2)
        XCTAssertEqual(spec?.soundFileName, "RestStart.wav")
    }

    func testRestCueNotificationSkipsElapsedDeadline() {
        XCTAssertNil(
            RestCueScheduler.notificationSpec(
                resumeAt: Date(timeIntervalSince1970: 100),
                upcomingExercise: nil,
                now: Date(timeIntervalSince1970: 100)
            )
        )
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

    func testDurationExerciseSeedsAndRecordsCanonicalDuration() throws {
        let routine = RoutineTemplate(
            routineId: "plank",
            routineName: "Core",
            plannedSets: [
                PlannedSet(
                    setId: "plank-1",
                    exerciseName: "Plank",
                    exerciseKind: .bodyweight,
                    targetWeight: 0,
                    targetReps: 0,
                    trackingMode: .duration,
                    targetDurationSeconds: 75,
                    restDurationSeconds: 0
                )
            ]
        )
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        XCTAssertEqual(session.lockScreenState.trackingMode, .duration)
        XCTAssertEqual(session.lockScreenState.targetDurationSeconds, 75)
        XCTAssertEqual(session.lockScreenState.actualDurationSeconds, 75)
        XCTAssertEqual(session.lockScreenState.actualReps, 0)
        XCTAssertFalse(session.lockScreenState.canIncrementReps)
        XCTAssertTrue(session.lockScreenState.canIncrementDuration)

        try engine.adjustActualDuration(session: &session, deltaSeconds: -15)
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 100))

        let completed = try XCTUnwrap(session.completedSets.first)
        XCTAssertEqual(completed.trackingMode, .duration)
        XCTAssertEqual(completed.actualDurationSeconds, 60)
        XCTAssertEqual(completed.actualReps, 0)
        XCTAssertEqual(session.lockScreenState.phase, .completed)
        XCTAssertEqual(session.lockScreenState.actualDurationSeconds, 60)
        XCTAssertEqual(engine.summarize(session: session).totalVolume, 0)
    }

    func testDurationCorrectionDuringRestAndNextSetKeepMode() throws {
        let routine = RoutineTemplate(
            routineId: "plank-rest",
            routineName: "Core",
            plannedSets: [
                PlannedSet(
                    setId: "plank-1",
                    exerciseName: "Plank",
                    exerciseKind: .bodyweight,
                    targetWeight: 0,
                    targetReps: 0,
                    trackingMode: .duration,
                    targetDurationSeconds: 45,
                    restDurationSeconds: 30
                ),
                PlannedSet(
                    setId: "plank-2",
                    exerciseName: "Plank",
                    exerciseKind: .bodyweight,
                    targetWeight: 0,
                    targetReps: 0,
                    trackingMode: .duration,
                    targetDurationSeconds: 60,
                    restDurationSeconds: 30
                )
            ]
        )
        let engine = WorkoutEngine()
        let completedAt = Date(timeIntervalSince1970: 100)
        var session = try engine.startSession(routine: routine)

        try engine.completeCurrentSet(session: &session, now: completedAt)
        try engine.adjustActualDuration(session: &session, deltaSeconds: 5)
        XCTAssertEqual(session.completedSets.last?.actualDurationSeconds, 50)
        XCTAssertEqual(session.lockScreenState.actualDurationSeconds, 50)

        let resumeAt = try XCTUnwrap(session.lockScreenState.resumeAt)
        engine.updateRest(session: &session, now: resumeAt)
        XCTAssertEqual(session.lockScreenState.trackingMode, .duration)
        XCTAssertEqual(session.lockScreenState.targetDurationSeconds, 60)
        XCTAssertEqual(session.lockScreenState.actualDurationSeconds, 60)
    }

    func testProgressAdjustmentsRejectTheInactiveMetric() throws {
        let durationRoutine = RoutineTemplate(
            routineId: "duration-only",
            routineName: "Duration",
            plannedSets: [
                PlannedSet(
                    setId: "hold",
                    exerciseName: "Wall Sit",
                    exerciseKind: .bodyweight,
                    targetWeight: 0,
                    targetReps: 0,
                    trackingMode: .duration,
                    targetDurationSeconds: 30,
                    restDurationSeconds: 0
                )
            ]
        )
        let repsRoutine = RoutineTemplate(
            routineId: "reps-only",
            routineName: "Reps",
            plannedSets: [
                PlannedSet(
                    setId: "push-up",
                    exerciseName: "Push-Up",
                    exerciseKind: .bodyweight,
                    targetWeight: 0,
                    targetReps: 10,
                    restDurationSeconds: 0
                )
            ]
        )
        let engine = WorkoutEngine()
        var durationSession = try engine.startSession(routine: durationRoutine)
        var repsSession = try engine.startSession(routine: repsRoutine)

        XCTAssertThrowsError(try engine.adjustActualReps(session: &durationSession, delta: 1)) {
            XCTAssertEqual($0 as? WorkoutEngineError, .invalidProgressMetric)
        }
        XCTAssertThrowsError(try engine.adjustActualDuration(session: &repsSession, deltaSeconds: 1)) {
            XCTAssertEqual($0 as? WorkoutEngineError, .invalidProgressMetric)
        }
        XCTAssertEqual(durationSession.lockScreenState.actualDurationSeconds, 30)
        XCTAssertEqual(repsSession.lockScreenState.actualReps, 10)
    }

    private func makeSummary(sessionId: String, endedAt: TimeInterval) throws -> WorkoutSummary {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let session = try engine.startSession(
            routine: routine,
            now: Date(timeIntervalSince1970: 0),
            sessionId: sessionId
        )
        return engine.summarize(
            session: session,
            endedAt: Date(timeIntervalSince1970: endedAt)
        )
    }
}
