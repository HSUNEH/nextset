import Foundation

/// Lock-guarded ISO-8601 JSON persistence for one Codable value at a fixed
/// file URL. The workout stores wrap this so the locking, directory creation,
/// and coder configuration live in one place.
final class JSONFileBox<Value: Codable>: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return try loadWhileLocked()
    }

    func save(_ value: Value) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveWhileLocked(value)
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Read-modify-write under a single lock acquisition.
    func replace(_ transform: (Value?) throws -> Value) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveWhileLocked(transform(loadWhileLocked()))
    }

    private func loadWhileLocked() throws -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    private func saveWhileLocked(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}
