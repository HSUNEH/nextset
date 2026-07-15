import Foundation

public protocol LocalWorkoutStore: Sendable {
    func save(_ summary: WorkoutSummary) throws
    @discardableResult
    func update(
        sessionId: String,
        _ transform: (WorkoutSummary) throws -> WorkoutSummary
    ) throws -> WorkoutSummary?
    func delete(sessionId: String) throws
    func summary(sessionId: String) throws -> WorkoutSummary?
    func allSummaries() throws -> [WorkoutSummary]
}

public enum LocalWorkoutStoreError: Error, Equatable, Sendable {
    case sessionIdChanged(expected: String, actual: String)
}

public final class InMemoryWorkoutStore: LocalWorkoutStore, @unchecked Sendable {
    private var summaries: [String: WorkoutSummary] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(_ summary: WorkoutSummary) throws {
        lock.lock()
        defer { lock.unlock() }
        summaries[summary.sessionId] = summary
    }

    @discardableResult
    public func update(
        sessionId: String,
        _ transform: (WorkoutSummary) throws -> WorkoutSummary
    ) throws -> WorkoutSummary? {
        lock.lock()
        defer { lock.unlock() }
        guard let existing = summaries[sessionId] else { return nil }

        let updated = try transform(existing)
        guard updated.sessionId == sessionId else {
            throw LocalWorkoutStoreError.sessionIdChanged(
                expected: sessionId,
                actual: updated.sessionId
            )
        }
        summaries[sessionId] = updated
        return updated
    }

    public func delete(sessionId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        summaries.removeValue(forKey: sessionId)
    }

    public func summary(sessionId: String) throws -> WorkoutSummary? {
        lock.lock()
        defer { lock.unlock() }
        return summaries[sessionId]
    }

    public func allSummaries() throws -> [WorkoutSummary] {
        lock.lock()
        defer { lock.unlock() }
        return summaries.values.sorted { $0.workoutEndTime > $1.workoutEndTime }
    }
}

/// Codable-file persistence used while SwiftData is unavailable in the local toolchain.
/// Summaries are stored as an ISO-8601 JSON array and looked up by sessionId.
public final class FileWorkoutStore: LocalWorkoutStore, @unchecked Sendable {
    private let box: JSONFileBox<[WorkoutSummary]>

    public init(fileURL: URL) {
        self.box = JSONFileBox(fileURL: fileURL)
    }

    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base
            .appendingPathComponent("DamSet", isDirectory: true)
            .appendingPathComponent("workout-summaries.json")
        self.init(fileURL: url)
    }

    /// Stores summaries in the shared App Group container so both the app and
    /// the Live Activity extension read and write the same history.
    public convenience init(appGroupId: String) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            self.init()
            return
        }
        self.init(fileURL: base.appendingPathComponent("workout-summaries.json"))
    }

    public func save(_ summary: WorkoutSummary) throws {
        try box.replace { existing in
            var summaries = existing ?? []
            summaries.removeAll { $0.sessionId == summary.sessionId }
            summaries.append(summary)
            return summaries
        }
    }

    @discardableResult
    public func update(
        sessionId: String,
        _ transform: (WorkoutSummary) throws -> WorkoutSummary
    ) throws -> WorkoutSummary? {
        var result: WorkoutSummary?
        try box.replace { existing in
            var summaries = existing ?? []
            guard let index = summaries.firstIndex(where: { $0.sessionId == sessionId }) else {
                return summaries
            }

            let updated = try transform(summaries[index])
            guard updated.sessionId == sessionId else {
                throw LocalWorkoutStoreError.sessionIdChanged(
                    expected: sessionId,
                    actual: updated.sessionId
                )
            }
            summaries[index] = updated
            result = updated
            return summaries
        }
        return result
    }

    public func delete(sessionId: String) throws {
        try box.replace { existing in
            var summaries = existing ?? []
            summaries.removeAll { $0.sessionId == sessionId }
            return summaries
        }
    }

    public func summary(sessionId: String) throws -> WorkoutSummary? {
        try box.load()?.first { $0.sessionId == sessionId }
    }

    public func allSummaries() throws -> [WorkoutSummary] {
        try (box.load() ?? []).sorted { $0.workoutEndTime > $1.workoutEndTime }
    }
}
