import Foundation

// Local transcript storage.
//
// One JSON file per video, inside a private 0700 directory, written through a
// 0600 staging file and an atomic rename — the same discipline LocalStore uses
// for realities and checkpoints. Records are validated on the way in and on the
// way out, so a corrupt or hand-edited file is refused rather than half-loaded.
//
// Nothing here is automatic: the Mac layer only calls `save` after the user has
// asked for a transcript, and `delete`/`deleteAll` are one call away.

public final class YouTubeTranscriptStore {
    public let directory: URL
    private let fm = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try ensurePrivateDirectory(directory)
    }

    // MARK: - Paths

    /// Video identifiers are restricted to a safe character set by
    /// `YouTubeVideoID`. A short digest is appended because APFS is
    /// case-insensitive by default and identifiers are case-sensitive.
    public func recordURL(for videoID: String) -> URL {
        let digest = SHA256.hexDigest(Array(videoID.utf8)).prefix(8)
        return directory.appendingPathComponent("\(videoID)-\(digest).json")
    }

    public func storedVideoIDs() throws -> [String] {
        let urls = try jsonFiles()
        var ids: [String] = []
        for url in urls {
            guard let record = try? load(from: url) else { continue }
            ids.append(record.videoID)
        }
        return ids
    }

    // MARK: - Reads

    public func load(videoID: String) throws -> YouTubeTranscriptRecord? {
        let url = recordURL(for: videoID)
        guard fm.fileExists(atPath: url.path) else { return nil }
        let record = try load(from: url)
        return record.videoID == videoID ? record : nil
    }

    /// Every readable record, newest first. Unreadable files are skipped rather
    /// than repaired or removed: the originals stay exactly as they were.
    public func loadLibrary() throws -> YouTubeTranscriptLibrary {
        var records: [YouTubeTranscriptRecord] = []
        for url in try jsonFiles() {
            guard let record = try? load(from: url) else { continue }
            records.append(record)
        }
        return YouTubeTranscriptLibrary(records: records)
    }

    public var isEmptyOnDisk: Bool { (try? jsonFiles().isEmpty) ?? true }

    // MARK: - Writes

    public func save(_ record: YouTubeTranscriptRecord) throws {
        try record.validate()
        try write(record, to: recordURL(for: record.videoID))
    }

    @discardableResult
    public func delete(videoID: String) throws -> Bool {
        let url = recordURL(for: videoID)
        guard fm.fileExists(atPath: url.path) else { return false }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else {
            throw RelayError.invalid("Refusing to delete a non-regular file.")
        }
        try fm.removeItem(at: url)
        return true
    }

    /// Returns how many transcript files were removed.
    @discardableResult
    public func deleteAll() throws -> Int {
        var removed = 0
        for url in try jsonFiles() {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            guard attrs?[.type] as? FileAttributeType == .typeRegular else { continue }
            try fm.removeItem(at: url)
            removed += 1
        }
        return removed
    }

    // MARK: - File helpers

    private func jsonFiles() throws -> [URL] {
        let urls = try fm.contentsOfDirectory(at: directory,
                                              includingPropertiesForKeys: [.contentModificationDateKey, .typeOfFile])
        return urls.filter { $0.pathExtension.lowercased() == "json" && !$0.lastPathComponent.hasPrefix(".") }
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        if fm.fileExists(atPath: url.path) {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory else {
                throw RelayError.invalid("Transcript storage is not an ordinary directory: \(url.lastPathComponent)")
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func load(from url: URL) throws -> YouTubeTranscriptRecord {
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else {
            throw RelayError.invalid("Only ordinary transcript files can be loaded.")
        }
        guard let size = attrs[.size] as? NSNumber, size.intValue <= Limits.fileBytes else {
            throw RelayError.invalid("A stored transcript exceeds the 2 MB safety limit.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Limits.fileBytes else {
            throw RelayError.invalid("A stored transcript became too large while reading.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(YouTubeTranscriptRecord.self, from: data)
        try record.validate()
        return record
    }

    private func write(_ value: YouTubeTranscriptRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard data.count <= Limits.fileBytes else {
            throw RelayError.invalid("This transcript is too large to store locally.")
        }
        if fm.fileExists(atPath: url.path) {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else {
                throw RelayError.invalid("Refusing to overwrite a non-regular file.")
            }
        }
        let temporary = directory.appendingPathComponent(".relaybar-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw RelayError.invalid("Could not write the transcript file.")
        }
        defer { try? fm.removeItem(at: temporary) }
        let result = temporary.path.withCString { source in url.path.withCString { destination in rename(source, destination) } }
        guard result == 0 else {
            throw RelayError.invalid("Could not commit the transcript file (error \(errno)). The previous file is unchanged.")
        }
    }
}
