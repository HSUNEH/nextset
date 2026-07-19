#if os(iOS) && canImport(AppIntents) && canImport(ActivityKit)
import AppIntents
import Foundation
import DamSetCore

/// Shared body for Lock Screen actions. These run in the app process through
/// `LiveActivityIntent`, which keeps the App Group session, Live Activity,
/// and rest-cue scheduling on the same proven pipeline.
///
/// Every action is scoped to the Live Activity's session ID. This keeps an old
/// activity from mutating a newer workout if iOS has not dismissed it yet.
///
/// Refreshing first realizes an expired rest transition, so an action always
/// mutates the same set the Lock Screen is currently presenting. During an
/// active rest, +/- still corrects the set that just finished.
private enum LockScreenAction: Sendable {
    case adjustReps(Int)
    case adjustDuration(Int)
    case adjustWeight(Double)
    case completeSet
    case advanceToNextSet
}

/// App Intent taps can arrive almost simultaneously. Serializing the full
/// load → mutate → save cycle prevents rapid +/- taps from overwriting each
/// other with stale snapshots.
private actor LockScreenActionCoordinator {
    static let shared = LockScreenActionCoordinator()

    func perform(sessionId expectedSessionId: String, action: LockScreenAction) async throws {
        let store = WorkoutSessionSync.sessionStore
        guard var session = try store.load(), session.sessionId == expectedSessionId else { return }
        let engine = WorkoutEngine()
        let phaseBeforeRefresh = session.lockScreenState.phase
        engine.refresh(session: &session)
        let restPhaseChanged = phaseBeforeRefresh != session.lockScreenState.phase

        switch action {
        case .adjustReps(let delta):
            try engine.adjustActualReps(session: &session, delta: delta)
            if restPhaseChanged {
                try await WorkoutSessionSync.applyDidChange(session)
            } else {
                try await WorkoutSessionSync.applyProgressCorrection(session)
            }
            return
        case .adjustDuration(let deltaSeconds):
            try engine.adjustActualDuration(session: &session, deltaSeconds: deltaSeconds)
            if restPhaseChanged {
                try await WorkoutSessionSync.applyDidChange(session)
            } else {
                try await WorkoutSessionSync.applyProgressCorrection(session)
            }
            return
        case .adjustWeight(let delta):
            try engine.adjustActualWeight(session: &session, delta: delta)
            if restPhaseChanged {
                try await WorkoutSessionSync.applyDidChange(session)
            } else {
                try await WorkoutSessionSync.applyProgressCorrection(session)
            }
            return
        case .completeSet:
            guard session.lockScreenState.phase == .performingSet else {
                try await WorkoutSessionSync.applyDidChange(session)
                return
            }
            try engine.completeCurrentSet(session: &session)
        case .advanceToNextSet:
            guard session.sessionStatus == .resting else {
                try await WorkoutSessionSync.applyDidChange(session)
                return
            }
            try engine.advanceToNextSet(session: &session)
        }

        try await WorkoutSessionSync.applyDidChange(session)
    }
}

struct AdjustRepsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust Reps"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    // Repetition taps never need a foreground scene. Keeping them in the
    // background avoids an unnecessary process/UI handoff on the Lock Screen.
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Session ID") var sessionId: String
    @Parameter(title: "Delta") var delta: Int

    init() {
        self.sessionId = ""
        self.delta = 0
    }

    init(sessionId: String, delta: Int) {
        self.sessionId = sessionId
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        try await LockScreenActionCoordinator.shared.perform(
            sessionId: sessionId,
            action: .adjustReps(delta)
        )
        return .result()
    }
}

struct AdjustDurationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust Time"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Session ID") var sessionId: String
    @Parameter(title: "Seconds") var deltaSeconds: Int

    init() {
        self.sessionId = ""
        self.deltaSeconds = 0
    }

    init(sessionId: String, deltaSeconds: Int) {
        self.sessionId = sessionId
        self.deltaSeconds = deltaSeconds
    }

    func perform() async throws -> some IntentResult {
        try await LockScreenActionCoordinator.shared.perform(
            sessionId: sessionId,
            action: .adjustDuration(deltaSeconds)
        )
        return .result()
    }
}

struct AdjustWeightIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust Weight"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Session ID") var sessionId: String
    @Parameter(title: "Kilograms") var delta: Double

    init() {
        self.sessionId = ""
        self.delta = 0
    }

    init(sessionId: String, delta: Double) {
        self.sessionId = sessionId
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        try await LockScreenActionCoordinator.shared.perform(
            sessionId: sessionId,
            action: .adjustWeight(delta)
        )
        return .result()
    }
}

struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Set"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Session ID") var sessionId: String

    init() { self.sessionId = "" }
    init(sessionId: String) { self.sessionId = sessionId }

    func perform() async throws -> some IntentResult {
        try await LockScreenActionCoordinator.shared.perform(sessionId: sessionId, action: .completeSet)
        return .result()
    }
}

/// Starts the next set explicitly during an active countdown. Normally the
/// deadline transition is automatic; the ready-state path remains as a
/// malformed/legacy-session fallback.
struct AdvanceToNextSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Next Set"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Session ID") var sessionId: String

    init() { self.sessionId = "" }
    init(sessionId: String) { self.sessionId = sessionId }

    func perform() async throws -> some IntentResult {
        try await LockScreenActionCoordinator.shared.perform(
            sessionId: sessionId,
            action: .advanceToNextSet
        )
        return .result()
    }
}
#endif
