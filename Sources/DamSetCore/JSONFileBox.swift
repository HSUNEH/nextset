import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private struct JSONFileLockError: Error, CustomStringConvertible {
    let operation: String
    let path: String
    let code: Int32

    var description: String {
        "Could not \(operation) file lock at \(path) (errno \(code))"
    }
}

/// Lock-guarded ISO-8601 JSON persistence for one Codable value at a fixed
/// file URL. An in-process lock protects each instance while a sidecar POSIX
/// lock serializes access across instances and processes sharing the same URL.
final class JSONFileBox<Value: Codable>: @unchecked Sendable {
    private let fileURL: URL
    private let lockFileURL: URL
    private let accessibleWhileLocked: Bool
    private let lock = NSLock()

    init(fileURL: URL, accessibleWhileLocked: Bool = false) {
        let standardizedURL = fileURL.standardizedFileURL
        self.fileURL = standardizedURL
        self.lockFileURL = standardizedURL.appendingPathExtension("lock")
        self.accessibleWhileLocked = accessibleWhileLocked
        makeExistingFilesAccessibleWhileLocked()
    }

    func load() throws -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return try withExclusiveFileLock {
            try loadWhileLocked()
        }
    }

    func save(_ value: Value) throws {
        lock.lock()
        defer { lock.unlock() }
        try withExclusiveFileLock {
            try saveWhileLocked(value)
        }
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        try withExclusiveFileLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Read-modify-write under one in-process and cross-process lock acquisition.
    func replace(_ transform: (Value?) throws -> Value) throws {
        lock.lock()
        defer { lock.unlock() }
        try withExclusiveFileLock {
            try saveWhileLocked(transform(loadWhileLocked()))
        }
    }

    private func withExclusiveFileLock<Result>(_ operation: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(
            at: lockFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = lockFileURL.path.withCString { path in
            open(path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(S_IRUSR | S_IWUSR))
        }
        guard descriptor >= 0 else {
            throw JSONFileLockError(operation: "open", path: lockFileURL.path, code: errno)
        }
        makeAccessibleWhileLocked(lockFileURL)
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }

        while flock(descriptor, LOCK_EX) != 0 {
            let errorCode = errno
            if errorCode == EINTR { continue }
            throw JSONFileLockError(operation: "acquire", path: lockFileURL.path, code: errorCode)
        }
        return try operation()
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
        #if os(iOS)
        let options: Data.WritingOptions = accessibleWhileLocked
            ? [.atomic, .noFileProtection]
            : .atomic
        try data.write(to: fileURL, options: options)
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    /// Live Activity intents must be able to read the active session while
    /// Face ID/passcode is still locked. Only callers that explicitly opt in
    /// receive this protection class; history and routine files retain the
    /// platform default.
    private func makeExistingFilesAccessibleWhileLocked() {
        makeAccessibleWhileLocked(fileURL)
        makeAccessibleWhileLocked(lockFileURL)
    }

    private func makeAccessibleWhileLocked(_ url: URL) {
        #if os(iOS)
        guard accessibleWhileLocked,
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.none],
            ofItemAtPath: url.path
        )
        #endif
    }
}
