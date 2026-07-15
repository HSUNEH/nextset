import Foundation

/// Persistence boundary for editable workout routines.
///
/// Stored routines are value snapshots. Editing a routine after calling
/// `upsert(_:)` cannot change the persisted copy until it is upserted again.
public protocol RoutineTemplateStore: Sendable {
    func loadAll() throws -> [RoutineTemplate]
    func upsert(_ routine: RoutineTemplate) throws
    func delete(routineId: String) throws
}

/// JSON-file-backed routine persistence.
///
/// A new store seeds its file once with the supplied defaults. From that point
/// onward the file is authoritative, including when the user edits or deletes
/// a default routine, so later loads never overwrite the user's snapshot.
public final class FileRoutineTemplateStore: RoutineTemplateStore, @unchecked Sendable {
    private let box: JSONFileBox<[RoutineTemplate]>
    private let seedRoutines: [RoutineTemplate]

    public init(
        fileURL: URL,
        seedRoutines: [RoutineTemplate] = RoutineCatalog.defaultRoutines
    ) {
        self.box = JSONFileBox(fileURL: fileURL)
        self.seedRoutines = seedRoutines
    }

    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base
            .appendingPathComponent("DamSet", isDirectory: true)
            .appendingPathComponent("routine-templates.json")
        self.init(fileURL: url)
    }

    public convenience init(appGroupId: String) {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.init(fileURL: base.appendingPathComponent("routine-templates.json"))
    }

    public func loadAll() throws -> [RoutineTemplate] {
        if let routines = try box.load() {
            return routines
        }

        // `replace` makes first-load seeding atomic with concurrent mutations.
        // If another operation won the race, its snapshot remains untouched.
        try box.replace { existing in
            existing ?? seedRoutines
        }
        return try box.load() ?? seedRoutines
    }

    public func upsert(_ routine: RoutineTemplate) throws {
        try box.replace { existing in
            var routines = existing ?? seedRoutines
            if let index = routines.firstIndex(where: { $0.routineId == routine.routineId }) {
                routines[index] = routine
                routines.removeAllDuplicates(ofRoutineId: routine.routineId, keeping: index)
            } else {
                routines.append(routine)
            }
            return routines
        }
    }

    public func delete(routineId: String) throws {
        try box.replace { existing in
            var routines = existing ?? seedRoutines
            routines.removeAll { $0.routineId == routineId }
            return routines
        }
    }
}

private extension Array where Element == RoutineTemplate {
    mutating func removeAllDuplicates(ofRoutineId routineId: String, keeping keptIndex: Int) {
        guard indices.contains(keptIndex) else { return }
        var index = endIndex - 1
        while index > keptIndex {
            if self[index].routineId == routineId {
                remove(at: index)
            }
            index -= 1
        }
    }
}
