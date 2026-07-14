#if os(iOS) && canImport(AppIntents) && canImport(ActivityKit)
import AppIntents
import Foundation
import DamSetCore

/// Shared body for Live Activity actions. `LiveActivityIntent` runs perform()
/// in the app process, so the App Group session file, the Live Activity, and
/// the rest-cue notifications are all mutated through the same
/// WorkoutSessionSync pipeline the in-app UI uses.
///
/// Every action is scoped to the Live Activity's session ID. This keeps an old
/// activity from mutating a newer workout if iOS has not dismissed it yet.
///
/// Refreshing only updates the wall-clock rest phase; it intentionally does
/// not advance the set. That makes +/- during both an active and an expired
/// rest correct the set that was just completed.
private enum LockScreenAction: Sendable {
    case adjustReps(Int)
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
        engine.refresh(session: &session)

        switch action {
        case .adjustReps(let delta):
            try engine.adjustActualReps(session: &session, delta: delta)
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

struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete Set"
    static let isDiscoverable = false

    @Parameter(title: "Session ID") var sessionId: String

    init() { self.sessionId = "" }
    init(sessionId: String) { self.sessionId = sessionId }

    func perform() async throws -> some IntentResult {
        try await LockScreenActionCoordinator.shared.perform(sessionId: sessionId, action: .completeSet)
        return .result()
    }
}

/// Starts the next set explicitly. During an active countdown this is the
/// user's "skip rest" action; after expiry it is the "next set" action.
struct AdvanceToNextSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Next Set"
    static let isDiscoverable = false

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
