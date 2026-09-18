import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Private, bounded, local IPC. Every connection gets a fresh UUID directory;
/// an expired/replaced context can never receive an earlier command.
public final class BrowserMailbox {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) throws {
        self.root = root
        try Self.privateDirectory(root)
    }
    public static func privateDirectory(_ url: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let a = try fm.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeDirectory,
              (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw RelayError.invalid("Refusing an unowned or symlinked bridge directory.")
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    private func directory(_ id: String, create: Bool = false) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw RelayError.invalid("Invalid bridge session.") }
        try Self.privateDirectory(root)
        let url = root.appendingPathComponent(id, isDirectory: true)
        if !create && !fm.fileExists(atPath: url.path) { throw RelayError.invalid("Browser link expired.") }
        try Self.privateDirectory(url)
        return url
    }
    private func write<T: Encodable>(_ value: T, at url: URL) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 65_536 else { throw RelayError.invalid("Bridge message too large.") }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".write-" + UUID().uuidString)
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw RelayError.invalid("Cannot create private bridge message.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? fm.removeItem(at: temporary) }
        try file.write(contentsOf: data); try file.synchronize(); try file.close()
        guard rename(temporary.path, url.path) == 0 else { throw RelayError.invalid("Cannot commit bridge message.") }
    }
    private func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RelayError.invalid("Missing private bridge message.") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var statBuffer = stat()
        guard fstat(fd, &statBuffer) == 0, (statBuffer.st_mode & S_IFMT) == S_IFREG,
              statBuffer.st_uid == getuid(), statBuffer.st_size > 0, statBuffer.st_size <= 65_536,
              (statBuffer.st_mode & 0o077) == 0 else { throw RelayError.invalid("Unsafe bridge file.") }
        let data = try file.read(upToCount: 65_537) ?? Data()
        guard data.count <= 65_536 else { throw RelayError.invalid("Bridge file too large.") }
        return try JSONDecoder().decode(type, from: data)
    }
    public func save(_ receipt: BrowserReceipt) throws {
        try receipt.validate()
        try write(receipt, at: directory(receipt.sessionID, create: true).appendingPathComponent("context.json"))
    }
    public func receipts() -> [BrowserReceipt] {
        guard (try? Self.privateDirectory(root)) != nil,
              let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        // Refuse an unexpectedly large mailbox instead of scanning arbitrary trees.
        let sessions = entries.filter { UUID(uuidString: $0.lastPathComponent) != nil }
        guard sessions.count <= 64 else { return [] }
        return sessions.compactMap { entry in
            guard let directory = try? directory(entry.lastPathComponent),
                  let result = try? read(BrowserReceipt.self, at: directory.appendingPathComponent("context.json")),
                  result.sessionID == entry.lastPathComponent,
                  (try? result.validate()) != nil else { return nil }
            return result
        }
    }
    public func queue(_ command: BrowserCommand) throws {
        let destination = try directory(command.sessionID).appendingPathComponent("command.json")
        guard !fm.fileExists(atPath: destination.path) else { throw RelayError.invalid("A browser request is already waiting. Do not tap twice.") }
        try write(command, at: destination)
    }
    public func consume(sessionID: String) -> BrowserCommand? {
        guard let destination = try? directory(sessionID).appendingPathComponent("command.json") else { return nil }
        defer { try? fm.removeItem(at: destination) }
        return try? read(BrowserCommand.self, at: destination)
    }
    public func remove(sessionID: String) {
        guard let directory = try? directory(sessionID) else { return }
        try? fm.removeItem(at: directory)
    }
    public func clearExpired(now: Double) {
        // Only valid, managed sessions; never delete unrelated files.
        for receipt in receipts() where now - receipt.receivedAt > 120 { remove(sessionID: receipt.sessionID) }
    }
}
