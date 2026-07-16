import Foundation
import XCTest
@testable import DamSetCore

final class RoutineStoreTests: XCTestCase {
    func testFirstLoadSeedsDefaultsAndPersistsThem() throws {
        try withStore { store, fileURL in
            XCTAssertEqual(try store.loadAll(), RoutineCatalog.defaultRoutines)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

            let reloaded = FileRoutineTemplateStore(fileURL: fileURL, seedRoutines: [])
            XCTAssertEqual(try reloaded.loadAll(), RoutineCatalog.defaultRoutines)
        }
    }

    func testUpsertReplacesInPlaceAndPreservesEditedSnapshot() throws {
        try withStore { store, fileURL in
            var edited = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
            edited.routineName = "My Push Day"
            edited.plannedSets[0].targetWeight = 72.5

            try store.upsert(edited)

            let stored = try store.loadAll()
            XCTAssertEqual(stored.count, RoutineCatalog.defaultRoutines.count)
            XCTAssertEqual(stored.first, edited)

            // Mutating the caller's value after upsert does not mutate disk.
            edited.routineName = "Changed Again"
            let reloaded = FileRoutineTemplateStore(fileURL: fileURL)
            XCTAssertEqual(try reloaded.loadAll().first?.routineName, "My Push Day")
            XCTAssertEqual(try reloaded.loadAll().first?.plannedSets[0].targetWeight, 72.5)
        }
    }

    func testUpsertAppendsNewRoutineAndDoesNotDuplicateIt() throws {
        try withStore { store, _ in
            let custom = RoutineTemplate(
                routineId: "custom",
                routineName: "Custom",
                plannedSets: [
                    PlannedSet(
                        setId: "custom-1",
                        exerciseName: "Incline Press",
                        targetWeight: 40,
                        targetReps: 10,
                        restDurationSeconds: 60
                    )
                ]
            )

            try store.upsert(custom)
            try store.upsert(custom)

            let routines = try store.loadAll()
            XCTAssertEqual(routines.last, custom)
            XCTAssertEqual(routines.filter { $0.routineId == custom.routineId }.count, 1)
        }
    }

    func testStoreRoundTripsCustomEmojiAndBodyweightKind() throws {
        try withStore(seedRoutines: []) { store, fileURL in
            let custom = RoutineTemplate(
                routineId: "calisthenics",
                routineName: "Calisthenics",
                emoji: "🤸",
                plannedSets: [
                    PlannedSet(
                        setId: "pull-up-1",
                        exerciseName: "Pull-Up",
                        exerciseKind: .bodyweight,
                        targetWeight: 75,
                        targetReps: 8,
                        restDurationSeconds: 90
                    )
                ]
            )

            try store.upsert(custom)

            let reloaded = try XCTUnwrap(
                FileRoutineTemplateStore(fileURL: fileURL).loadAll().first
            )
            XCTAssertEqual(reloaded.emoji, "🤸")
            XCTAssertEqual(reloaded.plannedSets.first?.exerciseKind, .bodyweight)
            XCTAssertEqual(reloaded.plannedSets.first?.targetWeight, 0)
        }
    }

    func testLegacyRoutineJSONMigratesWithoutLosingWeight() throws {
        try withStore(seedRoutines: []) { store, fileURL in
            let legacyJSON = """
            [
              {
                "routineId": "legacy",
                "routineName": "Legacy Routine",
                "plannedSets": [
                  {
                    "setId": "legacy-1",
                    "exerciseName": "Bench Press",
                    "targetWeight": 62.5,
                    "targetReps": 8,
                    "restDurationSeconds": 90
                  }
                ]
              }
            ]
            """
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try XCTUnwrap(legacyJSON.data(using: .utf8)).write(to: fileURL)

            let routine = try XCTUnwrap(store.loadAll().first)
            XCTAssertNil(routine.emoji)
            XCTAssertEqual(routine.plannedSets.first?.exerciseKind, .weighted)
            XCTAssertEqual(routine.plannedSets.first?.targetWeight, 62.5)
            XCTAssertEqual(routine.plannedSets.first?.manuallyAdded, false)
            XCTAssertEqual(routine.defaultRestDurationSeconds, 90)
        }
    }

    func testRoutineRestDefaultRoundTripsAlongsideExerciseOverrides() throws {
        try withStore(seedRoutines: []) { store, fileURL in
            let routine = RoutineTemplate(
                routineId: "custom-rest",
                routineName: "Custom Rest",
                defaultRestDurationSeconds: 105,
                plannedSets: [
                    PlannedSet(
                        setId: "custom-rest-1",
                        exerciseName: "Bench Press",
                        targetWeight: 60,
                        targetReps: 8,
                        restDurationSeconds: 105
                    ),
                    PlannedSet(
                        setId: "custom-rest-2",
                        exerciseName: "Lateral Raise",
                        targetWeight: 10,
                        targetReps: 12,
                        restDurationSeconds: 60
                    )
                ]
            )

            try store.upsert(routine)

            let reloaded = try XCTUnwrap(
                FileRoutineTemplateStore(fileURL: fileURL).loadAll().first
            )
            XCTAssertEqual(reloaded.defaultRestDurationSeconds, 105)
            XCTAssertEqual(reloaded.plannedSets.map(\.restDurationSeconds), [105, 60])
        }
    }

    func testBodyweightTargetWeightStaysNormalizedAtZero() {
        var set = PlannedSet(
            setId: "push-up-1",
            exerciseName: "Push-Up",
            exerciseKind: .bodyweight,
            targetWeight: 80,
            targetReps: 20,
            restDurationSeconds: 60
        )

        XCTAssertEqual(set.targetWeight, 0)
        set.targetWeight = 25
        XCTAssertEqual(set.targetWeight, 0)

        set.exerciseKind = .weighted
        set.targetWeight = 25
        XCTAssertEqual(set.targetWeight, 25)

        set.exerciseKind = .bodyweight
        XCTAssertEqual(set.targetWeight, 0)
    }

    func testExercisePlansGroupAdjacentIdenticalSetsAndRoundTripLosslessly() {
        let plannedSets = [
            PlannedSet(
                setId: "bench-1",
                exerciseName: "Bench Press",
                targetWeight: 60,
                targetReps: 8,
                restDurationSeconds: 90
            ),
            PlannedSet(
                setId: "bench-2",
                exerciseName: "Bench Press",
                targetWeight: 60,
                targetReps: 8,
                restDurationSeconds: 90
            ),
            PlannedSet(
                setId: "press-1",
                exerciseName: "Shoulder Press",
                targetWeight: 30,
                targetReps: 10,
                restDurationSeconds: 75
            )
        ]

        let plans = plannedSets.groupedExercisePlans()

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.map(\.exerciseName), ["Bench Press", "Shoulder Press"])
        XCTAssertEqual(plans.map(\.setCount), [2, 1])
        XCTAssertEqual(plans.first?.id, "bench-1")
        XCTAssertEqual(plans.expandedPlannedSets(), plannedSets)
    }

    func testExercisePlanGroupingDoesNotMergeSeparatedOrDifferentTargets() {
        let plannedSets = [
            PlannedSet(setId: "bench-1", exerciseName: "Bench Press", targetWeight: 60, targetReps: 8, restDurationSeconds: 90),
            PlannedSet(setId: "bench-2", exerciseName: "Bench Press", targetWeight: 65, targetReps: 8, restDurationSeconds: 90),
            PlannedSet(setId: "row-1", exerciseName: "Row", targetWeight: 50, targetReps: 8, restDurationSeconds: 90),
            PlannedSet(setId: "bench-3", exerciseName: "Bench Press", targetWeight: 60, targetReps: 8, restDurationSeconds: 90)
        ]

        let plans = RoutineExercisePlan.group(plannedSets)

        XCTAssertEqual(plans.count, 4)
        XCTAssertEqual(plans.map(\.setCount), [1, 1, 1, 1])
        XCTAssertEqual(RoutineExercisePlan.expand(plans), plannedSets)
    }

    func testExercisePlanPreservesIdsAndGeneratesStableIdsWhenSetCountGrows() throws {
        let existingSets = [
            PlannedSet(setId: "squat-original-1", exerciseName: "Squat", targetWeight: 80, targetReps: 5, restDurationSeconds: 120),
            PlannedSet(setId: "squat-original-2", exerciseName: "Squat", targetWeight: 80, targetReps: 5, restDurationSeconds: 120),
            PlannedSet(setId: "squat-original-3", exerciseName: "Squat", targetWeight: 80, targetReps: 5, restDurationSeconds: 120)
        ]
        var plan = try XCTUnwrap(existingSets.groupedExercisePlans().first)

        plan.setCount = 1
        XCTAssertEqual(plan.expandedPlannedSets().map(\.setId), ["squat-original-1"])

        plan.setCount = 5
        let firstExpansion = plan.expandedPlannedSets()
        plan.targetWeight = 85
        let secondExpansion = plan.expandedPlannedSets()

        XCTAssertEqual(
            Array(firstExpansion.map(\.setId).prefix(3)),
            existingSets.map(\.setId)
        )
        XCTAssertEqual(firstExpansion.map(\.setId), secondExpansion.map(\.setId))
        XCTAssertEqual(Set(firstExpansion.map(\.setId)).count, 5)
        XCTAssertEqual(secondExpansion.map(\.targetWeight), Array(repeating: 85, count: 5))
    }

    func testNewExercisePlanExpandsWithNormalizedValuesAndStableIdentity() {
        var plan = RoutineExercisePlan(
            id: "new-pull-up",
            exerciseName: "Pull-Up",
            exerciseKind: .bodyweight,
            targetWeight: 75,
            targetReps: -1,
            setCount: 0,
            restDurationSeconds: -10
        )

        XCTAssertEqual(plan.targetWeight, 0)
        XCTAssertEqual(plan.targetReps, 0)
        XCTAssertEqual(plan.setCount, 1)
        XCTAssertEqual(plan.restDurationSeconds, 0)

        plan.setCount = 3
        let firstIds = plan.expandedPlannedSets().map(\.setId)
        let secondIds = plan.expandedPlannedSets().map(\.setId)
        XCTAssertEqual(firstIds, secondIds)
        XCTAssertEqual(Set(firstIds).count, 3)
    }

    func testExercisePlanPreservesRoutineTemplatePersistenceShape() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let plans = routine.plannedSets.groupedExercisePlans()
        var edited = routine
        edited.plannedSets = plans.expandedPlannedSets()

        let data = try JSONEncoder().encode(edited)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let plannedSets = try XCTUnwrap(json["plannedSets"] as? [[String: Any]])

        XCTAssertEqual(
            Set(json.keys),
            ["routineId", "routineName", "emoji", "defaultRestDurationSeconds", "plannedSets"]
        )
        XCTAssertNil(json["exercisePlans"])
        XCTAssertNil(plannedSets.first?["setCount"])
        XCTAssertEqual(edited, routine)
    }

    func testWorkoutEngineSeedsAndRecordsZeroWeightForBodyweightSet() throws {
        let routine = RoutineTemplate(
            routineId: "bodyweight-engine",
            routineName: "Bodyweight",
            plannedSets: [
                PlannedSet(
                    setId: "dip-1",
                    exerciseName: "Dip",
                    exerciseKind: .bodyweight,
                    targetWeight: 100,
                    targetReps: 12,
                    restDurationSeconds: 0
                )
            ]
        )
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        XCTAssertEqual(session.currentPlannedSet?.targetWeight, 0)
        XCTAssertEqual(session.lockScreenState.actualWeight, 0)

        try engine.completeCurrentSet(session: &session)

        XCTAssertEqual(session.completedSets.first?.actualWeight, 0)
        XCTAssertEqual(engine.summarize(session: session).totalVolume, 0)
    }

    func testAdjustingBodyweightLoadIsNoOpDuringSetAndRest() throws {
        let routine = Self.makeBodyweightRoutine(setCount: 2)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        try engine.adjustActualWeight(session: &session, delta: 25)
        XCTAssertEqual(session.lockScreenState.actualWeight, 0)

        try engine.completeCurrentSet(session: &session)
        try engine.adjustActualWeight(session: &session, delta: 25)

        XCTAssertEqual(session.lockScreenState.exerciseKind, .bodyweight)
        XCTAssertEqual(session.lockScreenState.actualWeight, 0)
        XCTAssertEqual(session.completedSets.last?.exerciseKind, .bodyweight)
        XCTAssertEqual(session.completedSets.last?.actualWeight, 0)
    }

    func testMixedWorkoutVolumeCountsOnlyWeightedSets() throws {
        let routine = RoutineTemplate(
            routineId: "mixed-volume",
            routineName: "Mixed",
            plannedSets: [
                PlannedSet(
                    setId: "push-up",
                    exerciseName: "Push-Up",
                    exerciseKind: .bodyweight,
                    targetWeight: 80,
                    targetReps: 10,
                    restDurationSeconds: 0
                ),
                PlannedSet(
                    setId: "bench",
                    exerciseName: "Bench Press",
                    exerciseKind: .weighted,
                    targetWeight: 50,
                    targetReps: 4,
                    restDurationSeconds: 0
                )
            ]
        )
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)

        try engine.completeCurrentSet(session: &session)
        XCTAssertEqual(session.currentSetIndex, 2)
        XCTAssertEqual(session.lockScreenState.phase, .performingSet)
        try engine.completeCurrentSet(session: &session)

        XCTAssertEqual(session.completedSets.map(\.exerciseKind), [.bodyweight, .weighted])
        XCTAssertEqual(engine.summarize(session: session).totalVolume, 200)
    }

    func testRepeatingBodyweightSetPreservesKindAndZeroWeight() throws {
        let routine = Self.makeBodyweightRoutine(setCount: 1)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        let current = try XCTUnwrap(session.currentPlannedSet)

        engine.addSessionScopedSet(
            session: &session,
            exerciseName: current.exerciseName,
            exerciseKind: current.exerciseKind,
            targetWeight: current.targetWeight,
            targetReps: current.targetReps,
            restDurationSeconds: current.restDurationSeconds
        )

        XCTAssertEqual(session.nextPlannedSet?.exerciseKind, .bodyweight)
        XCTAssertEqual(session.nextPlannedSet?.targetWeight, 0)

        try engine.completeCurrentSet(session: &session)
        try engine.advanceToNextSet(session: &session)
        XCTAssertEqual(session.lockScreenState.exerciseKind, .bodyweight)
        XCTAssertEqual(session.lockScreenState.actualWeight, 0)
    }

    func testBodyweightActiveSessionRoundTripPreservesZeroWeightInvariant() throws {
        let routine = Self.makeBodyweightRoutine(setCount: 2)
        let engine = WorkoutEngine()
        var session = try engine.startSession(routine: routine)
        try engine.completeCurrentSet(session: &session)

        // Public model mutation must not be able to create bodyweight load.
        session.lockScreenState.actualWeight = 100
        session.completedSets[0].actualWeight = 100

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-bodyweight-session-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("active.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = ActiveSessionStore(fileURL: fileURL)
        try store.save(session)
        let reloaded = try XCTUnwrap(store.load())

        XCTAssertEqual(reloaded.currentPlannedSet?.exerciseKind, .bodyweight)
        XCTAssertEqual(reloaded.currentPlannedSet?.targetWeight, 0)
        XCTAssertEqual(reloaded.lockScreenState.exerciseKind, .bodyweight)
        XCTAssertEqual(reloaded.lockScreenState.actualWeight, 0)
        XCTAssertEqual(reloaded.completedSets.last?.exerciseKind, .bodyweight)
        XCTAssertEqual(reloaded.completedSets.last?.actualWeight, 0)
    }

    func testNewWorkoutSummaryStoresAndRoundTripsRoutineId() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        var session = try engine.startSession(
            routine: routine,
            now: Date(timeIntervalSince1970: 100),
            sessionId: "summary-with-routine"
        )
        try engine.completeCurrentSet(session: &session, now: Date(timeIntervalSince1970: 110))
        let summary = engine.summarize(session: session, endedAt: Date(timeIntervalSince1970: 120))

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-summary-routine-id-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("summaries.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileWorkoutStore(fileURL: fileURL)
        try store.save(summary)
        let reloaded = try XCTUnwrap(store.summary(sessionId: summary.sessionId))

        XCTAssertEqual(summary.routineId, routine.routineId)
        XCTAssertEqual(reloaded.routineId, routine.routineId)
        XCTAssertEqual(reloaded, summary)
    }

    func testLegacyWorkoutSummaryWithoutRoutineIdDecodesAsNil() throws {
        let routine = try XCTUnwrap(RoutineCatalog.defaultRoutines.first)
        let engine = WorkoutEngine()
        let session = try engine.startSession(
            routine: routine,
            now: Date(timeIntervalSince1970: 100),
            sessionId: "legacy-summary"
        )
        let summary = engine.summarize(session: session, endedAt: Date(timeIntervalSince1970: 120))

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-legacy-summary-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("summaries.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileWorkoutStore(fileURL: fileURL)
        try store.save(summary)

        let data = try Data(contentsOf: fileURL)
        var summaries = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        summaries[0].removeValue(forKey: "routineId")
        try JSONSerialization.data(withJSONObject: summaries).write(to: fileURL, options: .atomic)

        let legacy = try XCTUnwrap(store.summary(sessionId: summary.sessionId))
        XCTAssertNil(legacy.routineId)
        XCTAssertEqual(legacy.sessionId, summary.sessionId)
        XCTAssertEqual(legacy.routineName, summary.routineName)
        XCTAssertEqual(legacy.completedSets, summary.completedSets)
    }

    func testReplacingCompletedSetsRecalculatesDerivedTotals() throws {
        let original = try Self.makeEmptySummary(sessionId: "edited-summary")
        let weighted = Self.makeCompletedSet(
            id: "weighted",
            exerciseKind: .weighted,
            weight: 50,
            reps: 4
        )
        let bodyweight = Self.makeCompletedSet(
            id: "bodyweight",
            exerciseKind: .bodyweight,
            weight: 90,
            reps: 10
        )

        let edited = original.replacingCompletedSets([weighted, bodyweight])

        XCTAssertEqual(edited.sessionId, original.sessionId)
        XCTAssertEqual(edited.routineId, original.routineId)
        XCTAssertEqual(edited.workoutStartTime, original.workoutStartTime)
        XCTAssertEqual(edited.workoutEndTime, original.workoutEndTime)
        XCTAssertEqual(edited.totalSets, 2)
        XCTAssertEqual(edited.totalVolume, 200)
        XCTAssertEqual(edited.completedSets.last?.actualWeight, 0)
        XCTAssertTrue(original.completedSets.isEmpty)
        XCTAssertEqual(original.totalSets, 0)
    }

    func testInMemoryWorkoutStoreUpdateIsAtomicAndRejectsIdentityChange() throws {
        let original = try Self.makeEmptySummary(sessionId: "memory-update")
        let store = InMemoryWorkoutStore()
        try store.save(original)

        let updated = try store.update(sessionId: original.sessionId) { summary in
            summary.replacingCompletedSets([
                Self.makeCompletedSet(id: "edited", weight: 40, reps: 5)
            ])
        }

        XCTAssertEqual(updated?.totalSets, 1)
        XCTAssertEqual(updated?.totalVolume, 200)
        XCTAssertEqual(try store.summary(sessionId: original.sessionId), updated)
        XCTAssertNil(try store.update(sessionId: "missing") { $0 })

        XCTAssertThrowsError(
            try store.update(sessionId: original.sessionId) { summary in
                var invalid = summary
                invalid.sessionId = "different-session"
                return invalid
            }
        ) { error in
            XCTAssertEqual(
                error as? LocalWorkoutStoreError,
                .sessionIdChanged(expected: original.sessionId, actual: "different-session")
            )
        }
        XCTAssertEqual(try store.summary(sessionId: original.sessionId), updated)
    }

    func testFileWorkoutStoreUpdatePersistsWithoutDuplicatingSummary() throws {
        let original = try Self.makeEmptySummary(sessionId: "file-update")
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-summary-update-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("summaries.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = FileWorkoutStore(fileURL: fileURL)
        try store.save(original)
        let updated = try store.update(sessionId: original.sessionId) { summary in
            summary.replacingCompletedSets([
                Self.makeCompletedSet(id: "edited", weight: 62.5, reps: 8)
            ])
        }

        let reloaded = FileWorkoutStore(fileURL: fileURL)
        XCTAssertEqual(try reloaded.summary(sessionId: original.sessionId), updated)
        XCTAssertEqual(try reloaded.allSummaries().count, 1)
        XCTAssertEqual(updated?.totalVolume, 500)
    }

    func testConcurrentInMemoryWorkoutUpdatesDoNotLoseEdits() throws {
        let original = try Self.makeEmptySummary(sessionId: "concurrent-update")
        let store = InMemoryWorkoutStore()
        try store.save(original)

        let iterations = 40
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            _ = try? store.update(sessionId: original.sessionId) { summary in
                var sets = summary.completedSets
                sets.append(Self.makeCompletedSet(id: "set-\(index)", weight: 10, reps: 1))
                return summary.replacingCompletedSets(sets)
            }
        }

        let updated = try XCTUnwrap(store.summary(sessionId: original.sessionId))
        XCTAssertEqual(updated.totalSets, iterations)
        XCTAssertEqual(updated.totalVolume, Double(iterations * 10))
        XCTAssertEqual(Set(updated.completedSets.map(\.setId)).count, iterations)
    }

    func testSeparateFileWorkoutStoreInstancesSerializeConcurrentUpdates() throws {
        let original = try Self.makeEmptySummary(sessionId: "cross-instance-update")
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-cross-instance-update-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("summaries.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let stores = [
            FileWorkoutStore(fileURL: fileURL),
            FileWorkoutStore(fileURL: fileURL)
        ]
        try stores[0].save(original)

        let iterations = 40
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            _ = try? stores[index % stores.count].update(sessionId: original.sessionId) { summary in
                // Widen the RMW window so this test reliably catches per-instance-only locking.
                Thread.sleep(forTimeInterval: 0.001)
                var sets = summary.completedSets
                sets.append(Self.makeCompletedSet(id: "file-set-\(index)", weight: 10, reps: 1))
                return summary.replacingCompletedSets(sets)
            }
        }

        let updated = try XCTUnwrap(FileWorkoutStore(fileURL: fileURL).summary(sessionId: original.sessionId))
        XCTAssertEqual(updated.totalSets, iterations)
        XCTAssertEqual(updated.totalVolume, Double(iterations * 10))
        XCTAssertEqual(Set(updated.completedSets.map(\.setId)).count, iterations)
    }

    func testSeparateFileWorkoutStoreInstancesSerializeConcurrentSaves() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-cross-instance-save-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("summaries.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let iterations = 40
        let stores = (0..<iterations).map { _ in FileWorkoutStore(fileURL: fileURL) }
        let summaries = try (0..<iterations).map { index in
            try Self.makeEmptySummary(sessionId: "saved-session-\(index)")
        }

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            _ = try? stores[index].save(summaries[index])
        }

        let saved = try FileWorkoutStore(fileURL: fileURL).allSummaries()
        XCTAssertEqual(saved.count, iterations)
        XCTAssertEqual(Set(saved.map(\.sessionId)), Set(summaries.map(\.sessionId)))
    }

    func testDeletingSeedAndAddingCustomRoutinePersistsAsUserCatalog() throws {
        try withStore { store, fileURL in
            let deletedId = try XCTUnwrap(RoutineCatalog.defaultRoutines.first?.routineId)
            let custom = Self.makeRoutine(id: "user-added")

            try store.delete(routineId: deletedId)
            try store.upsert(custom)

            let reloaded = try FileRoutineTemplateStore(fileURL: fileURL).loadAll()
            XCTAssertFalse(reloaded.contains { $0.routineId == deletedId })
            XCTAssertTrue(reloaded.contains(custom))
            XCTAssertEqual(reloaded.count, RoutineCatalog.defaultRoutines.count)
        }
    }

    func testDeletePersistsAndEmptyFileDoesNotReseed() throws {
        let seed = [Self.makeRoutine(id: "only")]
        try withStore(seedRoutines: seed) { store, fileURL in
            try store.delete(routineId: "only")
            XCTAssertEqual(try store.loadAll(), [])

            let reloaded = FileRoutineTemplateStore(fileURL: fileURL, seedRoutines: seed)
            XCTAssertEqual(try reloaded.loadAll(), [])
        }
    }

    func testConcurrentUpsertsAreSerializedWithoutLosingRoutines() throws {
        try withStore(seedRoutines: []) { store, _ in
            let iterations = 40
            DispatchQueue.concurrentPerform(iterations: iterations) { index in
                try? store.upsert(Self.makeRoutine(id: "routine-\(index)"))
            }

            let routines = try store.loadAll()
            XCTAssertEqual(routines.count, iterations)
            XCTAssertEqual(Set(routines.map(\.routineId)).count, iterations)
        }
    }

    private func withStore(
        seedRoutines: [RoutineTemplate] = RoutineCatalog.defaultRoutines,
        _ body: (FileRoutineTemplateStore, URL) throws -> Void
    ) throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("damset-routine-store-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("routines.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try body(FileRoutineTemplateStore(fileURL: fileURL, seedRoutines: seedRoutines), fileURL)
    }

    private static func makeRoutine(id: String) -> RoutineTemplate {
        RoutineTemplate(
            routineId: id,
            routineName: "Routine \(id)",
            plannedSets: [
                PlannedSet(
                    setId: "\(id)-set",
                    exerciseName: "Squat",
                    targetWeight: 80,
                    targetReps: 5,
                    restDurationSeconds: 120
                )
            ]
        )
    }

    private static func makeBodyweightRoutine(setCount: Int) -> RoutineTemplate {
        RoutineTemplate(
            routineId: "bodyweight-\(setCount)",
            routineName: "Bodyweight",
            plannedSets: (0..<setCount).map { index in
                PlannedSet(
                    setId: "bodyweight-\(index)",
                    exerciseName: "Pull-Up",
                    exerciseKind: .bodyweight,
                    targetWeight: 100,
                    targetReps: 8,
                    restDurationSeconds: 60
                )
            }
        )
    }

    private static func makeEmptySummary(sessionId: String) throws -> WorkoutSummary {
        let routine = makeRoutine(id: "summary-routine")
        let session = try WorkoutEngine().startSession(
            routine: routine,
            now: Date(timeIntervalSince1970: 100),
            sessionId: sessionId
        )
        return WorkoutSummary(session: session, endedAt: Date(timeIntervalSince1970: 200))
    }

    private static func makeCompletedSet(
        id: String,
        exerciseKind: ExerciseKind = .weighted,
        weight: Double,
        reps: Int
    ) -> CompletedSet {
        CompletedSet(
            setId: id,
            exerciseName: exerciseKind == .weighted ? "Bench Press" : "Push-Up",
            exerciseKind: exerciseKind,
            actualWeight: weight,
            actualReps: reps,
            completedAt: Date(timeIntervalSince1970: 150)
        )
    }
}
