import Foundation

public struct RoutineCatalog: Codable, Equatable, Sendable {
    public var routines: [RoutineTemplate]

    public init(routines: [RoutineTemplate] = RoutineCatalog.defaultRoutines) {
        self.routines = routines
    }

    public static let defaultRoutines: [RoutineTemplate] = [
        RoutineTemplate(
            routineId: "push-foundation",
            routineName: "Push Foundation",
            plannedSets: [
                PlannedSet(setId: "push-bench-1", exerciseName: "Bench Press", targetWeight: 60, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "push-bench-2", exerciseName: "Bench Press", targetWeight: 60, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "push-press-1", exerciseName: "Shoulder Press", targetWeight: 30, targetReps: 10, restDurationSeconds: 75)
            ]
        ),
        RoutineTemplate(
            routineId: "pull-foundation",
            routineName: "Pull Foundation",
            plannedSets: [
                PlannedSet(setId: "pull-row-1", exerciseName: "Barbell Row", targetWeight: 50, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "pull-row-2", exerciseName: "Barbell Row", targetWeight: 50, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "pull-curl-1", exerciseName: "Dumbbell Curl", targetWeight: 12, targetReps: 12, restDurationSeconds: 60)
            ]
        ),
        RoutineTemplate(
            routineId: "legs-foundation",
            routineName: "Legs Foundation",
            plannedSets: [
                PlannedSet(setId: "legs-squat-1", exerciseName: "Back Squat", targetWeight: 80, targetReps: 5, restDurationSeconds: 120),
                PlannedSet(setId: "legs-squat-2", exerciseName: "Back Squat", targetWeight: 80, targetReps: 5, restDurationSeconds: 120),
                PlannedSet(setId: "legs-rdl-1", exerciseName: "Romanian Deadlift", targetWeight: 70, targetReps: 8, restDurationSeconds: 90)
            ]
        )
    ]
}

public struct RoutineTemplate: Identifiable, Codable, Equatable, Sendable {
    public var routineId: String
    public var routineName: String
    public var plannedSets: [PlannedSet]

    public var id: String { routineId }

    public init(routineId: String, routineName: String, plannedSets: [PlannedSet]) {
        self.routineId = routineId
        self.routineName = routineName
        self.plannedSets = plannedSets
    }
}

public struct PlannedSet: Identifiable, Codable, Equatable, Sendable {
    public var setId: String
    public var exerciseName: String
    public var targetWeight: Double
    public var targetReps: Int
    public var restDurationSeconds: Int
    public var manuallyAdded: Bool

    public var id: String { setId }

    public init(setId: String, exerciseName: String, targetWeight: Double, targetReps: Int, restDurationSeconds: Int, manuallyAdded: Bool = false) {
        self.setId = setId
        self.exerciseName = exerciseName
        self.targetWeight = max(0, targetWeight)
        self.targetReps = max(0, targetReps)
        self.restDurationSeconds = max(0, restDurationSeconds)
        self.manuallyAdded = manuallyAdded
    }
}

public struct CompletedSet: Identifiable, Codable, Equatable, Sendable {
    public var setId: String
    public var exerciseName: String
    public var actualWeight: Double
    public var actualReps: Int
    public var completedAt: Date

    public var id: String { setId }

    public init(setId: String, exerciseName: String, actualWeight: Double, actualReps: Int, completedAt: Date) {
        self.setId = setId
        self.exerciseName = exerciseName
        self.actualWeight = max(0, actualWeight)
        self.actualReps = max(0, actualReps)
        self.completedAt = completedAt
    }
}

public enum WorkoutSessionStatus: String, Codable, Equatable, Sendable {
    case notStarted
    case active
    case resting
    case completed
    case cancelled
}

public enum LockScreenPhase: String, Codable, Equatable, Sendable {
    case performingSet
    case resting
    case readyForNextSet
    case completed
}

public struct LockScreenState: Codable, Equatable, Sendable {
    public var exerciseName: String
    public var currentSetIndex: Int
    public var totalPlannedSets: Int
    public var targetReps: Int
    public var actualReps: Int
    /// The single source of truth for the weight being performed or most
    /// recently completed. Keeping this beside `actualReps` lets the app and
    /// Live Activity mutate the same progress instead of maintaining separate
    /// process-local values.
    public var actualWeight: Double
    public var canCompleteSet: Bool
    public var restRemainingSeconds: Int
    public var resumeAt: Date?
    public var phase: LockScreenPhase

    // Derived, so they can never drift out of sync with actualReps.
    public var canDecrementReps: Bool { actualReps > 0 }
    public var canIncrementReps: Bool { true }

    public init(
        exerciseName: String,
        currentSetIndex: Int,
        totalPlannedSets: Int,
        targetReps: Int,
        actualReps: Int,
        actualWeight: Double,
        canCompleteSet: Bool,
        restRemainingSeconds: Int,
        resumeAt: Date?,
        phase: LockScreenPhase
    ) {
        self.exerciseName = exerciseName
        self.currentSetIndex = max(1, currentSetIndex)
        self.totalPlannedSets = max(1, totalPlannedSets)
        self.targetReps = max(0, targetReps)
        self.actualReps = max(0, actualReps)
        self.actualWeight = max(0, actualWeight)
        self.canCompleteSet = canCompleteSet
        self.restRemainingSeconds = max(0, restRemainingSeconds)
        self.resumeAt = resumeAt
        self.phase = phase
    }

    public static func performing(_ set: PlannedSet, setIndex: Int, totalSets: Int) -> LockScreenState {
        LockScreenState(
            exerciseName: set.exerciseName,
            currentSetIndex: setIndex,
            totalPlannedSets: totalSets,
            targetReps: set.targetReps,
            actualReps: set.targetReps,
            actualWeight: set.targetWeight,
            canCompleteSet: true,
            restRemainingSeconds: 0,
            resumeAt: nil,
            phase: .performingSet
        )
    }

    public static func resting(
        after set: PlannedSet,
        setIndex: Int,
        totalSets: Int,
        actualReps: Int,
        actualWeight: Double,
        resumeAt: Date
    ) -> LockScreenState {
        LockScreenState(
            exerciseName: set.exerciseName,
            currentSetIndex: setIndex,
            totalPlannedSets: totalSets,
            targetReps: set.targetReps,
            actualReps: actualReps,
            actualWeight: actualWeight,
            canCompleteSet: false,
            restRemainingSeconds: set.restDurationSeconds,
            resumeAt: resumeAt,
            phase: .resting
        )
    }

    public static func completed(
        after set: PlannedSet,
        setIndex: Int,
        totalSets: Int,
        actualReps: Int,
        actualWeight: Double
    ) -> LockScreenState {
        LockScreenState(
            exerciseName: set.exerciseName,
            currentSetIndex: setIndex,
            totalPlannedSets: totalSets,
            targetReps: set.targetReps,
            actualReps: actualReps,
            actualWeight: actualWeight,
            canCompleteSet: false,
            restRemainingSeconds: 0,
            resumeAt: nil,
            phase: .completed
        )
    }

    enum CodingKeys: String, CodingKey {
        case exerciseName
        case currentSetIndex
        case totalPlannedSets
        case targetReps
        case actualReps
        case actualWeight
        case canCompleteSet
        case restRemainingSeconds
        case resumeAt
        case phase
    }

    /// Older persisted sessions did not contain `actualWeight`. Decode those
    /// sessions instead of discarding them; `WorkoutRoutineSession` performs a
    /// second migration pass where the surrounding planned/completed set data
    /// is available.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseName = try container.decode(String.self, forKey: .exerciseName)
        currentSetIndex = max(1, try container.decode(Int.self, forKey: .currentSetIndex))
        totalPlannedSets = max(1, try container.decode(Int.self, forKey: .totalPlannedSets))
        targetReps = max(0, try container.decode(Int.self, forKey: .targetReps))
        actualReps = max(0, try container.decode(Int.self, forKey: .actualReps))
        actualWeight = max(0, try container.decodeIfPresent(Double.self, forKey: .actualWeight) ?? 0)
        canCompleteSet = try container.decode(Bool.self, forKey: .canCompleteSet)
        restRemainingSeconds = max(0, try container.decode(Int.self, forKey: .restRemainingSeconds))
        resumeAt = try container.decodeIfPresent(Date.self, forKey: .resumeAt)
        phase = try container.decode(LockScreenPhase.self, forKey: .phase)
    }
}

public struct RestCountdownCue: Codable, Equatable, Sendable {
    public enum FallbackMode: String, Codable, Equatable, Sendable {
        case none
        case notificationSoundAndHaptics
    }

    public var notificationLeadTimeSeconds: Int
    public var spokenCountdown: [String]
    public var hornCueEnabled: Bool
    public var vibrationCueEnabled: Bool
    public var shouldNotInterruptMusic: Bool
    public var fallbackMode: FallbackMode

    public init(fallbackMode: FallbackMode = .none) {
        self.notificationLeadTimeSeconds = 3
        self.spokenCountdown = ["3", "2", "1"]
        self.hornCueEnabled = true
        self.vibrationCueEnabled = true
        self.shouldNotInterruptMusic = true
        self.fallbackMode = fallbackMode
    }
}

public struct WorkoutRoutineSession: Identifiable, Codable, Equatable, Sendable {
    public var sessionId: String
    public var routineId: String
    public var routineName: String
    public var plannedSets: [PlannedSet]
    public var completedSets: [CompletedSet]
    public var currentSetIndex: Int
    public var sessionStatus: WorkoutSessionStatus
    public var workoutStartTime: Date
    public var workoutEndTime: Date?
    public var lockScreenState: LockScreenState
    public var restCountdownCue: RestCountdownCue

    public var id: String { sessionId }

    /// `currentSetIndex` is 1-based; planned sets are addressed through these
    /// accessors so the off-by-one lives in exactly one place.
    public var currentPlannedSet: PlannedSet? {
        guard plannedSets.indices.contains(currentSetIndex - 1) else { return nil }
        return plannedSets[currentSetIndex - 1]
    }

    public var nextPlannedSet: PlannedSet? {
        guard plannedSets.indices.contains(currentSetIndex) else { return nil }
        return plannedSets[currentSetIndex]
    }
}

extension WorkoutRoutineSession {
    private enum CodingKeys: String, CodingKey {
        case sessionId
        case routineId
        case routineName
        case plannedSets
        case completedSets
        case currentSetIndex
        case sessionStatus
        case workoutStartTime
        case workoutEndTime
        case lockScreenState
        case restCountdownCue
    }

    /// Migrates pre-`actualWeight` active-session files using information that
    /// is not available while decoding `LockScreenState` in isolation.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        routineId = try container.decode(String.self, forKey: .routineId)
        routineName = try container.decode(String.self, forKey: .routineName)
        plannedSets = try container.decode([PlannedSet].self, forKey: .plannedSets)
        completedSets = try container.decode([CompletedSet].self, forKey: .completedSets)
        currentSetIndex = try container.decode(Int.self, forKey: .currentSetIndex)
        sessionStatus = try container.decode(WorkoutSessionStatus.self, forKey: .sessionStatus)
        workoutStartTime = try container.decode(Date.self, forKey: .workoutStartTime)
        workoutEndTime = try container.decodeIfPresent(Date.self, forKey: .workoutEndTime)
        lockScreenState = try container.decode(LockScreenState.self, forKey: .lockScreenState)
        restCountdownCue = try container.decode(RestCountdownCue.self, forKey: .restCountdownCue)

        let legacyLockState = try? container.nestedContainer(
            keyedBy: LockScreenState.CodingKeys.self,
            forKey: .lockScreenState
        )
        if legacyLockState?.contains(.actualWeight) != true {
            let currentPlannedSet = plannedSets.indices.contains(currentSetIndex - 1)
                ? plannedSets[currentSetIndex - 1]
                : nil
            switch sessionStatus {
            case .resting, .completed:
                lockScreenState.actualWeight = completedSets.last?.actualWeight
                    ?? currentPlannedSet?.targetWeight
                    ?? 0
            case .notStarted, .active, .cancelled:
                lockScreenState.actualWeight = currentPlannedSet?.targetWeight ?? 0
            }
        }
    }
}

public struct WorkoutSummary: Identifiable, Codable, Equatable, Sendable {
    public var sessionId: String
    public var routineName: String
    public var completedSets: [CompletedSet]
    public var totalSets: Int
    public var totalVolume: Double
    public var workoutStartTime: Date
    public var workoutEndTime: Date

    public var id: String { sessionId }

    public init(session: WorkoutRoutineSession, endedAt: Date) {
        self.sessionId = session.sessionId
        self.routineName = session.routineName
        self.completedSets = session.completedSets
        self.totalSets = session.completedSets.count
        self.totalVolume = session.completedSets.reduce(0) { $0 + ($1.actualWeight * Double($1.actualReps)) }
        self.workoutStartTime = session.workoutStartTime
        self.workoutEndTime = endedAt
    }
}
