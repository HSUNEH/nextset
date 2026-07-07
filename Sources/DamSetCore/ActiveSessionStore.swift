import Foundation

/// Persists the in-flight workout session as ISO-8601 JSON so the app and the
/// Live Activity extension can act on the same state across process boundaries.
public final class ActiveSessionStore: @unchecked Sendable {
    private let box: JSONFileBox<WorkoutRoutineSession>

    public init(fileURL: URL) {
        self.box = JSONFileBox(fileURL: fileURL)
    }

    /// Uses the shared App Group container when the entitlement is present,
    /// falling back to a local path so development builds keep functioning.
    public convenience init(appGroupId: String) {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.init(fileURL: base.appendingPathComponent("active-workout-session.json"))
    }

    public func save(_ session: WorkoutRoutineSession) throws {
        try box.save(session)
    }

    public func load() throws -> WorkoutRoutineSession? {
        try box.load()
    }

    public func clear() throws {
        try box.clear()
    }
}
