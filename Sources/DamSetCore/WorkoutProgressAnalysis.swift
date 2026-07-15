import Foundation

/// A value that can be plotted for one exercise across completed workouts.
public enum WorkoutProgressMetric: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case weight
    case reps
}

/// One workout's best value for an exercise and metric.
public struct WorkoutProgressPoint: Identifiable, Equatable, Sendable {
    public let sessionId: String
    public let metric: WorkoutProgressMetric
    public let workoutEndTime: Date
    public let value: Double
    public let deltaFromPrevious: Double?
    public let isSelectedSession: Bool

    public var id: String { "\(metric.rawValue)-\(sessionId)" }

    public init(
        sessionId: String,
        metric: WorkoutProgressMetric,
        workoutEndTime: Date,
        value: Double,
        deltaFromPrevious: Double?,
        isSelectedSession: Bool
    ) {
        self.sessionId = sessionId
        self.metric = metric
        self.workoutEndTime = workoutEndTime
        self.value = value
        self.deltaFromPrevious = deltaFromPrevious
        self.isSelectedSession = isSelectedSession
    }
}

/// Chronological progress for one exercise in the selected routine.
public struct ExerciseProgressSeries: Identifiable, Equatable, Sendable {
    public let exerciseName: String
    public let weightPoints: [WorkoutProgressPoint]
    public let repsPoints: [WorkoutProgressPoint]

    public var id: String { exerciseName }

    public init(
        exerciseName: String,
        weightPoints: [WorkoutProgressPoint],
        repsPoints: [WorkoutProgressPoint]
    ) {
        self.exerciseName = exerciseName
        self.weightPoints = weightPoints
        self.repsPoints = repsPoints
    }

    public func points(for metric: WorkoutProgressMetric) -> [WorkoutProgressPoint] {
        switch metric {
        case .weight:
            return weightPoints
        case .reps:
            return repsPoints
        }
    }
}

/// Pure, deterministic progress data derived from workout summaries.
///
/// Routine IDs are authoritative when present. Summaries created before a
/// routine ID was stored fall back to the routine name, so legacy history can
/// still contribute without merging two modern routines that merely share a
/// name.
public struct WorkoutProgressAnalysis: Equatable, Sendable {
    public let selectedSessionId: String
    public let workouts: [WorkoutSummary]
    public let exercises: [ExerciseProgressSeries]

    public var exerciseNames: [String] {
        exercises.map(\.exerciseName)
    }

    public init(selectedSummary: WorkoutSummary, allSummaries: [WorkoutSummary]) {
        selectedSessionId = selectedSummary.sessionId
        let matchingWorkouts = Self.matchingWorkouts(
            selectedSummary: selectedSummary,
            allSummaries: allSummaries
        )
        workouts = matchingWorkouts

        let names = Self.exerciseNames(
            selectedSummary: selectedSummary,
            workouts: matchingWorkouts
        )
        exercises = names.map { exerciseName in
            ExerciseProgressSeries(
                exerciseName: exerciseName,
                weightPoints: Self.points(
                    for: exerciseName,
                    metric: .weight,
                    selectedSessionId: selectedSummary.sessionId,
                    workouts: matchingWorkouts
                ),
                repsPoints: Self.points(
                    for: exerciseName,
                    metric: .reps,
                    selectedSessionId: selectedSummary.sessionId,
                    workouts: matchingWorkouts
                )
            )
        }
    }

    public func progress(forExerciseNamed exerciseName: String) -> ExerciseProgressSeries? {
        exercises.first { $0.exerciseName == exerciseName }
    }

    private static func matchingWorkouts(
        selectedSummary: WorkoutSummary,
        allSummaries: [WorkoutSummary]
    ) -> [WorkoutSummary] {
        var uniqueBySessionId: [String: WorkoutSummary] = [:]

        for summary in allSummaries where sameRoutine(summary, as: selectedSummary) {
            if uniqueBySessionId[summary.sessionId] == nil {
                uniqueBySessionId[summary.sessionId] = summary
            }
        }

        // The selected record is useful even when a caller passes a filtered
        // or stale list. It also wins over a duplicate snapshot of its session.
        uniqueBySessionId[selectedSummary.sessionId] = selectedSummary

        return uniqueBySessionId.values.sorted(by: chronologicalOrder)
    }

    private static func sameRoutine(_ candidate: WorkoutSummary, as selected: WorkoutSummary) -> Bool {
        let selectedId = normalizedRoutineId(selected.routineId)
        let candidateId = normalizedRoutineId(candidate.routineId)

        if let selectedId, let candidateId {
            return selectedId == candidateId
        }

        return normalizedRoutineName(candidate.routineName) == normalizedRoutineName(selected.routineName)
    }

    private static func normalizedRoutineId(_ routineId: String?) -> String? {
        guard let routineId else { return nil }
        let trimmed = routineId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedRoutineName(_ routineName: String) -> String {
        routineName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chronologicalOrder(_ lhs: WorkoutSummary, _ rhs: WorkoutSummary) -> Bool {
        if lhs.workoutEndTime != rhs.workoutEndTime {
            return lhs.workoutEndTime < rhs.workoutEndTime
        }
        if lhs.workoutStartTime != rhs.workoutStartTime {
            return lhs.workoutStartTime < rhs.workoutStartTime
        }
        return lhs.sessionId < rhs.sessionId
    }

    private static func exerciseNames(
        selectedSummary: WorkoutSummary,
        workouts: [WorkoutSummary]
    ) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []

        func appendNames(from summary: WorkoutSummary) {
            for completedSet in summary.completedSets where seen.insert(completedSet.exerciseName).inserted {
                names.append(completedSet.exerciseName)
            }
        }

        // Keep the selected workout's exercise order first. Historical-only
        // exercises are then appended by their first chronological appearance.
        appendNames(from: selectedSummary)
        for workout in workouts where workout.sessionId != selectedSummary.sessionId {
            appendNames(from: workout)
        }
        return names
    }

    private static func points(
        for exerciseName: String,
        metric: WorkoutProgressMetric,
        selectedSessionId: String,
        workouts: [WorkoutSummary]
    ) -> [WorkoutProgressPoint] {
        var previousValue: Double?

        return workouts.compactMap { workout in
            let matchingSets = workout.completedSets.filter { $0.exerciseName == exerciseName }
            let value: Double?

            switch metric {
            case .weight:
                value = matchingSets
                    .filter { $0.exerciseKind == .weighted && $0.actualWeight.isFinite }
                    .map(\.actualWeight)
                    .max()
            case .reps:
                value = matchingSets.map { Double($0.actualReps) }.max()
            }

            guard let value else { return nil }
            let point = WorkoutProgressPoint(
                sessionId: workout.sessionId,
                metric: metric,
                workoutEndTime: workout.workoutEndTime,
                value: value,
                deltaFromPrevious: previousValue.map { value - $0 },
                isSelectedSession: workout.sessionId == selectedSessionId
            )
            previousValue = value
            return point
        }
    }
}
