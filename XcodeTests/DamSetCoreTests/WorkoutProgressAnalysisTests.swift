import XCTest
@testable import DamSetCore

final class WorkoutProgressAnalysisTests: XCTestCase {
    func testFiltersByRoutineIdAndSortsWorkoutsChronologically() {
        let older = makeSummary(
            sessionId: "older",
            routineId: "push-id",
            routineName: "Old Push Name",
            endedAt: 100,
            sets: [completedSet(id: "squat", exercise: "Squat", weight: 80, reps: 5)]
        )
        let selected = makeSummary(
            sessionId: "selected",
            routineId: "push-id",
            routineName: "Push",
            endedAt: 200,
            sets: [
                completedSet(id: "shoulder", exercise: "Shoulder Press", weight: 30, reps: 10),
                completedSet(id: "bench", exercise: "Bench Press", weight: 60, reps: 8)
            ]
        )
        let newer = makeSummary(
            sessionId: "newer",
            routineId: "push-id",
            routineName: "Renamed Push",
            endedAt: 300,
            sets: [completedSet(id: "bench-new", exercise: "Bench Press", weight: 62.5, reps: 8)]
        )
        let sameNameDifferentRoutine = makeSummary(
            sessionId: "different-id",
            routineId: "another-push-id",
            routineName: "Push",
            endedAt: 150,
            sets: [completedSet(id: "wrong", exercise: "Bench Press", weight: 100, reps: 1)]
        )

        let analysis = WorkoutProgressAnalysis(
            selectedSummary: selected,
            allSummaries: [newer, sameNameDifferentRoutine, selected, older, selected]
        )

        XCTAssertEqual(analysis.workouts.map(\.sessionId), ["older", "selected", "newer"])
        XCTAssertEqual(
            analysis.exerciseNames,
            ["Shoulder Press", "Bench Press", "Squat"]
        )
    }

    func testUsesWorkoutMaximumsAndCalculatesDeltaFromPreviousPoint() throws {
        let first = makeSummary(
            sessionId: "first",
            routineId: "push",
            routineName: "Push",
            endedAt: 100,
            sets: [
                completedSet(id: "first-1", exercise: "Bench Press", weight: 40, reps: 10),
                completedSet(id: "first-2", exercise: "Bench Press", weight: 50, reps: 8)
            ]
        )
        let selected = makeSummary(
            sessionId: "selected",
            routineId: "push",
            routineName: "Push",
            endedAt: 200,
            sets: [
                completedSet(id: "selected-1", exercise: "Bench Press", weight: 55, reps: 9),
                completedSet(id: "selected-2", exercise: "Bench Press", weight: 45, reps: 12)
            ]
        )

        let analysis = WorkoutProgressAnalysis(
            selectedSummary: selected,
            allSummaries: [selected, first]
        )
        let bench = try XCTUnwrap(analysis.progress(forExerciseNamed: "Bench Press"))

        XCTAssertEqual(bench.weightPoints.map(\.value), [50, 55])
        XCTAssertNil(bench.weightPoints[0].deltaFromPrevious)
        XCTAssertEqual(bench.weightPoints[1].deltaFromPrevious, 5)
        XCTAssertTrue(bench.weightPoints[1].isSelectedSession)

        XCTAssertEqual(bench.repsPoints.map(\.value), [10, 12])
        XCTAssertNil(bench.repsPoints[0].deltaFromPrevious)
        XCTAssertEqual(bench.repsPoints[1].deltaFromPrevious, 2)
        XCTAssertTrue(bench.repsPoints[1].isSelectedSession)
        XCTAssertEqual(bench.points(for: .weight), bench.weightPoints)
        XCTAssertEqual(bench.points(for: .reps), bench.repsPoints)
    }

    func testBodyweightExerciseProducesRepsPointWithoutWeightPoint() throws {
        let selected = makeSummary(
            sessionId: "calisthenics",
            routineId: "bodyweight",
            routineName: "Bodyweight",
            endedAt: 100,
            sets: [
                completedSet(
                    id: "pull-up-1",
                    exercise: "Pull-Up",
                    kind: .bodyweight,
                    weight: 80,
                    reps: 8
                ),
                completedSet(
                    id: "pull-up-2",
                    exercise: "Pull-Up",
                    kind: .bodyweight,
                    weight: 80,
                    reps: 12
                )
            ]
        )

        let analysis = WorkoutProgressAnalysis(selectedSummary: selected, allSummaries: [])
        let pullUp = try XCTUnwrap(analysis.progress(forExerciseNamed: "Pull-Up"))

        XCTAssertTrue(pullUp.weightPoints.isEmpty)
        XCTAssertEqual(pullUp.repsPoints.map(\.value), [12])
        XCTAssertTrue(pullUp.repsPoints[0].isSelectedSession)
        XCTAssertNil(pullUp.repsPoints[0].deltaFromPrevious)
    }

    func testLegacySummaryFallsBackToRoutineNameWithoutMergingModernIds() {
        let legacySameName = makeSummary(
            sessionId: "legacy-same",
            routineId: nil,
            routineName: " Push ",
            endedAt: 100,
            sets: [completedSet(id: "legacy-bench", exercise: "Bench Press", weight: 50, reps: 8)]
        )
        let selected = makeSummary(
            sessionId: "selected-modern",
            routineId: "push-id",
            routineName: "Push",
            endedAt: 200,
            sets: [completedSet(id: "selected-bench", exercise: "Bench Press", weight: 60, reps: 8)]
        )
        let modernSameNameDifferentId = makeSummary(
            sessionId: "modern-different",
            routineId: "other-push-id",
            routineName: "Push",
            endedAt: 150,
            sets: [completedSet(id: "other-bench", exercise: "Bench Press", weight: 70, reps: 8)]
        )
        let legacyDifferentName = makeSummary(
            sessionId: "legacy-different",
            routineId: nil,
            routineName: "Pull",
            endedAt: 125,
            sets: [completedSet(id: "legacy-row", exercise: "Row", weight: 50, reps: 8)]
        )

        let modernSelection = WorkoutProgressAnalysis(
            selectedSummary: selected,
            allSummaries: [modernSameNameDifferentId, legacyDifferentName, legacySameName]
        )
        XCTAssertEqual(modernSelection.workouts.map(\.sessionId), ["legacy-same", "selected-modern"])

        let legacySelection = WorkoutProgressAnalysis(
            selectedSummary: legacyDifferentName,
            allSummaries: [
                makeSummary(
                    sessionId: "modern-pull",
                    routineId: "pull-id",
                    routineName: "Pull",
                    endedAt: 175,
                    sets: [completedSet(id: "modern-row", exercise: "Row", weight: 55, reps: 8)]
                ),
                selected
            ]
        )
        XCTAssertEqual(legacySelection.workouts.map(\.sessionId), ["legacy-different", "modern-pull"])
    }

    private func makeSummary(
        sessionId: String,
        routineId: String?,
        routineName: String,
        endedAt: TimeInterval,
        sets: [CompletedSet]
    ) -> WorkoutSummary {
        let plannedSets = sets.enumerated().map { index, set in
            PlannedSet(
                setId: "\(sessionId)-planned-\(index)",
                exerciseName: set.exerciseName,
                exerciseKind: set.exerciseKind,
                targetWeight: set.actualWeight,
                targetReps: set.actualReps,
                restDurationSeconds: 0
            )
        }
        let routine = RoutineTemplate(
            routineId: routineId ?? "legacy-source-\(sessionId)",
            routineName: routineName,
            plannedSets: plannedSets
        )
        let engine = WorkoutEngine()
        var session = try! engine.startSession(
            routine: routine,
            now: Date(timeIntervalSince1970: endedAt - 60),
            sessionId: sessionId
        )
        session.completedSets = sets

        var summary = engine.summarize(
            session: session,
            endedAt: Date(timeIntervalSince1970: endedAt)
        )
        summary.routineId = routineId
        return summary
    }

    private func completedSet(
        id: String,
        exercise: String,
        kind: ExerciseKind = .weighted,
        weight: Double,
        reps: Int
    ) -> CompletedSet {
        CompletedSet(
            setId: id,
            exerciseName: exercise,
            exerciseKind: kind,
            actualWeight: weight,
            actualReps: reps,
            completedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
