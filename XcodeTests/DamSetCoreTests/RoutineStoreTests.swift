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
}
