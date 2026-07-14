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
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            // Current files encode the complete TimeInterval so sub-second
            // timestamps round-trip without being truncated.
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }

            // Continue accepting the ISO-8601 strings written by earlier
            // versions so an app update never invalidates local history.
            let value = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: value) {
                return date
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected seconds-since-1970 or an ISO-8601 date"
            )
        }
        return try decoder.decode(Value.self, from: data)
    }

    private func saveWhileLocked(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970)
        }
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}
