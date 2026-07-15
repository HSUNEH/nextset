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
            emoji: "🏋️",
            plannedSets: [
                PlannedSet(setId: "push-bench-1", exerciseName: "Bench Press", targetWeight: 60, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "push-bench-2", exerciseName: "Bench Press", targetWeight: 60, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "push-press-1", exerciseName: "Shoulder Press", targetWeight: 30, targetReps: 10, restDurationSeconds: 75)
            ]
        ),
        RoutineTemplate(
            routineId: "pull-foundation",
            routineName: "Pull Foundation",
            emoji: "💪",
            plannedSets: [
                PlannedSet(setId: "pull-row-1", exerciseName: "Barbell Row", targetWeight: 50, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "pull-row-2", exerciseName: "Barbell Row", targetWeight: 50, targetReps: 8, restDurationSeconds: 90),
                PlannedSet(setId: "pull-curl-1", exerciseName: "Dumbbell Curl", targetWeight: 12, targetReps: 12, restDurationSeconds: 60)
            ]
        ),
        RoutineTemplate(
            routineId: "legs-foundation",
            routineName: "Legs Foundation",
            emoji: "🦵",
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
    public var emoji: String?
    public var plannedSets: [PlannedSet]

    public var id: String { routineId }

    public init(
        routineId: String,
        routineName: String,
        emoji: String? = nil,
        plannedSets: [PlannedSet]
    ) {
        self.routineId = routineId
        self.routineName = routineName
        self.emoji = emoji
        self.plannedSets = plannedSets
    }

    private enum CodingKeys: String, CodingKey {
        case routineId
        case routineName
        case emoji
        case plannedSets
    }

    /// Routines saved before custom icons existed decode with no icon so the
    /// app can continue using its normal fallback artwork.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            routineId: try container.decode(String.self, forKey: .routineId),
            routineName: try container.decode(String.self, forKey: .routineName),
            emoji: try container.decodeIfPresent(String.self, forKey: .emoji),
            plannedSets: try container.decode([PlannedSet].self, forKey: .plannedSets)
        )
    }
}

public enum ExerciseKind: String, Codable, CaseIterable, Equatable, Sendable {
    case bodyweight
    case weighted
}

public struct PlannedSet: Identifiable, Codable, Equatable, Sendable {
    public var setId: String
    public var exerciseName: String
    public var exerciseKind: ExerciseKind {
        didSet {
            storedTargetWeight = Self.normalizedWeight(storedTargetWeight, for: exerciseKind)
        }
    }
    private var storedTargetWeight: Double
    public var targetWeight: Double {
        get { storedTargetWeight }
        set { storedTargetWeight = Self.normalizedWeight(newValue, for: exerciseKind) }
    }
    public var targetReps: Int
    public var restDurationSeconds: Int
    public var manuallyAdded: Bool

    public var id: String { setId }

    public init(
        setId: String,
        exerciseName: String,
        exerciseKind: ExerciseKind = .weighted,
        targetWeight: Double,
        targetReps: Int,
        restDurationSeconds: Int,
        manuallyAdded: Bool = false
    ) {
        self.setId = setId
        self.exerciseName = exerciseName
        self.exerciseKind = exerciseKind
        self.storedTargetWeight = Self.normalizedWeight(targetWeight, for: exerciseKind)
        self.targetReps = max(0, targetReps)
        self.restDurationSeconds = max(0, restDurationSeconds)
        self.manuallyAdded = manuallyAdded
    }

    private enum CodingKeys: String, CodingKey {
        case setId
        case exerciseName
        case exerciseKind
        case targetWeight
        case targetReps
        case restDurationSeconds
        case manuallyAdded
    }

    /// Existing routine files did not identify an exercise kind. Treat them as
    /// weighted so their saved kilogram targets retain their original meaning.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            setId: try container.decode(String.self, forKey: .setId),
            exerciseName: try container.decode(String.self, forKey: .exerciseName),
            exerciseKind: try container.decodeIfPresent(ExerciseKind.self, forKey: .exerciseKind) ?? .weighted,
            targetWeight: try container.decode(Double.self, forKey: .targetWeight),
            targetReps: try container.decode(Int.self, forKey: .targetReps),
            restDurationSeconds: try container.decode(Int.self, forKey: .restDurationSeconds),
            manuallyAdded: try container.decodeIfPresent(Bool.self, forKey: .manuallyAdded) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setId, forKey: .setId)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encode(exerciseKind, forKey: .exerciseKind)
        try container.encode(targetWeight, forKey: .targetWeight)
        try container.encode(targetReps, forKey: .targetReps)
        try container.encode(restDurationSeconds, forKey: .restDurationSeconds)
        try container.encode(manuallyAdded, forKey: .manuallyAdded)
    }

    private static func normalizedWeight(_ weight: Double, for kind: ExerciseKind) -> Double {
        guard kind == .weighted, weight.isFinite else { return 0 }
        return max(0, weight)
    }
}

public struct CompletedSet: Identifiable, Codable, Equatable, Sendable {
    public var setId: String
    public var exerciseName: String
    public var exerciseKind: ExerciseKind {
        didSet {
            storedActualWeight = Self.normalizedWeight(storedActualWeight, for: exerciseKind)
        }
    }
    private var storedActualWeight: Double
    public var actualWeight: Double {
        get { storedActualWeight }
        set { storedActualWeight = Self.normalizedWeight(newValue, for: exerciseKind) }
    }
    public var actualReps: Int
    public var completedAt: Date

    public var id: String { setId }

    public init(
        setId: String,
        exerciseName: String,
        exerciseKind: ExerciseKind = .weighted,
        actualWeight: Double,
        actualReps: Int,
        completedAt: Date
    ) {
        self.setId = setId
        self.exerciseName = exerciseName
        self.exerciseKind = exerciseKind
        self.storedActualWeight = Self.normalizedWeight(actualWeight, for: exerciseKind)
        self.actualReps = max(0, actualReps)
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case setId, exerciseName, exerciseKind, actualWeight, actualReps, completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            setId: try container.decode(String.self, forKey: .setId),
            exerciseName: try container.decode(String.self, forKey: .exerciseName),
            exerciseKind: try container.decodeIfPresent(ExerciseKind.self, forKey: .exerciseKind) ?? .weighted,
            actualWeight: try container.decode(Double.self, forKey: .actualWeight),
            actualReps: try container.decode(Int.self, forKey: .actualReps),
            completedAt: try container.decode(Date.self, forKey: .completedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setId, forKey: .setId)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encode(exerciseKind, forKey: .exerciseKind)
        try container.encode(actualWeight, forKey: .actualWeight)
        try container.encode(actualReps, forKey: .actualReps)
        try container.encode(completedAt, forKey: .completedAt)
    }

    private static func normalizedWeight(_ weight: Double, for kind: ExerciseKind) -> Double {
        guard kind == .weighted, weight.isFinite else { return 0 }
        return max(0, weight)
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
    public var exerciseKind: ExerciseKind {
        didSet {
            storedActualWeight = Self.normalizedWeight(storedActualWeight, for: exerciseKind)
        }
    }
    public var currentSetIndex: Int
    public var totalPlannedSets: Int
    public var targetReps: Int
    public var actualReps: Int
    /// The single source of truth for the weight being performed or most
    /// recently completed. Keeping this beside `actualReps` lets the app and
    /// Live Activity mutate the same progress instead of maintaining separate
    /// process-local values.
    private var storedActualWeight: Double
    public var actualWeight: Double {
        get { storedActualWeight }
        set { storedActualWeight = Self.normalizedWeight(newValue, for: exerciseKind) }
    }
    public var canCompleteSet: Bool
    public var restRemainingSeconds: Int
    public var resumeAt: Date?
    public var phase: LockScreenPhase

    // Derived, so they can never drift out of sync with actualReps.
    public var canDecrementReps: Bool { actualReps > 0 }
    public var canIncrementReps: Bool { true }

    public init(
        exerciseName: String,
        exerciseKind: ExerciseKind = .weighted,
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
        self.exerciseKind = exerciseKind
        self.currentSetIndex = max(1, currentSetIndex)
        self.totalPlannedSets = max(1, totalPlannedSets)
        self.targetReps = max(0, targetReps)
        self.actualReps = max(0, actualReps)
        self.storedActualWeight = Self.normalizedWeight(actualWeight, for: exerciseKind)
        self.canCompleteSet = canCompleteSet
        self.restRemainingSeconds = max(0, restRemainingSeconds)
        self.resumeAt = resumeAt
        self.phase = phase
    }

    public static func performing(_ set: PlannedSet, setIndex: Int, totalSets: Int) -> LockScreenState {
        LockScreenState(
            exerciseName: set.exerciseName,
            exerciseKind: set.exerciseKind,
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
            exerciseKind: set.exerciseKind,
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
            exerciseKind: set.exerciseKind,
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
        case exerciseKind
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
        self.init(
            exerciseName: try container.decode(String.self, forKey: .exerciseName),
            exerciseKind: try container.decodeIfPresent(ExerciseKind.self, forKey: .exerciseKind) ?? .weighted,
            currentSetIndex: try container.decode(Int.self, forKey: .currentSetIndex),
            totalPlannedSets: try container.decode(Int.self, forKey: .totalPlannedSets),
            targetReps: try container.decode(Int.self, forKey: .targetReps),
            actualReps: try container.decode(Int.self, forKey: .actualReps),
            actualWeight: try container.decodeIfPresent(Double.self, forKey: .actualWeight) ?? 0,
            canCompleteSet: try container.decode(Bool.self, forKey: .canCompleteSet),
            restRemainingSeconds: try container.decode(Int.self, forKey: .restRemainingSeconds),
            resumeAt: try container.decodeIfPresent(Date.self, forKey: .resumeAt),
            phase: try container.decode(LockScreenPhase.self, forKey: .phase)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseName, forKey: .exerciseName)
        try container.encode(exerciseKind, forKey: .exerciseKind)
        try container.encode(currentSetIndex, forKey: .currentSetIndex)
        try container.encode(totalPlannedSets, forKey: .totalPlannedSets)
        try container.encode(targetReps, forKey: .targetReps)
        try container.encode(actualReps, forKey: .actualReps)
        try container.encode(actualWeight, forKey: .actualWeight)
        try container.encode(canCompleteSet, forKey: .canCompleteSet)
        try container.encode(restRemainingSeconds, forKey: .restRemainingSeconds)
        try container.encodeIfPresent(resumeAt, forKey: .resumeAt)
        try container.encode(phase, forKey: .phase)
    }

    private static func normalizedWeight(_ weight: Double, for kind: ExerciseKind) -> Double {
        guard kind == .weighted, weight.isFinite else { return 0 }
        return max(0, weight)
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
    public var routineId: String?
    public var routineName: String
    public var completedSets: [CompletedSet]
    public var totalSets: Int
    public var totalVolume: Double
    public var workoutStartTime: Date
    public var workoutEndTime: Date

    public var id: String { sessionId }

    public init(session: WorkoutRoutineSession, endedAt: Date) {
        self.sessionId = session.sessionId
        self.routineId = session.routineId
        self.routineName = session.routineName
        self.completedSets = session.completedSets
        self.totalSets = session.completedSets.count
        self.totalVolume = Self.volume(for: session.completedSets)
        self.workoutStartTime = session.workoutStartTime
        self.workoutEndTime = endedAt
    }

    /// Returns an edited snapshot while keeping derived totals consistent.
    /// Bodyweight sets contribute no external-load volume.
    public func replacingCompletedSets(_ completedSets: [CompletedSet]) -> WorkoutSummary {
        var updated = self
        updated.completedSets = completedSets
        updated.totalSets = completedSets.count
        updated.totalVolume = Self.volume(for: completedSets)
        return updated
    }

    private static func volume(for completedSets: [CompletedSet]) -> Double {
        completedSets.reduce(0) { volume, set in
            guard set.exerciseKind == .weighted else { return volume }
            return volume + (set.actualWeight * Double(set.actualReps))
        }
    }
}
