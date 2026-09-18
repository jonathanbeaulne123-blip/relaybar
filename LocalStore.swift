import Foundation

public final class LocalStore {
    public let directory: URL
    public var configurationURL: URL { directory.appendingPathComponent("projects.json") }
    public var checkpointsURL: URL { directory.appendingPathComponent("Checkpoints", isDirectory: true) }
    public var realitiesURL: URL { directory.appendingPathComponent("Realities", isDirectory: true) }
    public var ledgersURL: URL { directory.appendingPathComponent("Ledgers", isDirectory: true) }
    /// Local YouTube transcripts and Moments. Private 0700, one bounded JSON file
    /// per video; see `YouTubeTranscriptStore`.
    public var transcriptsURL: URL { directory.appendingPathComponent("Transcripts", isDirectory: true) }
    private let fm = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try ensurePrivateDirectory(directory)
        try ensurePrivateDirectory(checkpointsURL)
        try ensurePrivateDirectory(realitiesURL)
        try ensurePrivateDirectory(ledgersURL)
        try ensurePrivateDirectory(transcriptsURL)
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        // Do not follow a substituted directory into an unexpected storage location.
        if fm.fileExists(atPath: url.path) {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory else {
                throw RelayError.invalid("Local storage is not an ordinary directory: \(url.lastPathComponent)")
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    public func loadConfiguration() throws -> AppConfiguration {
        guard fm.fileExists(atPath: configurationURL.path) else {
            let initial = AppConfiguration()
            try saveConfiguration(initial)
            return initial
        }
        let result = try decode(AppConfiguration.self, from: configurationURL)
        try result.validate()
        return result
    }

    public func saveConfiguration(_ configuration: AppConfiguration) throws {
        try configuration.validate()
        try write(configuration, to: configurationURL)
    }

    @discardableResult
    public func saveCheckpoint(_ checkpoint: Checkpoint) throws -> URL {
        try checkpoint.validate()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "\(formatter.string(from: checkpoint.savedAt))-\(SafeFilename.slug(checkpoint.project.name))-\(UUID().uuidString.prefix(8)).json"
        let url = checkpointsURL.appendingPathComponent(filename)
        try write(checkpoint, to: url)
        return url
    }

    public func loadCheckpoint(from url: URL) throws -> Checkpoint {
        let result = try decode(Checkpoint.self, from: url)
        try result.validate()
        return result
    }

    @discardableResult
    public func saveReality(_ reality: RealitySnapshot) throws -> URL {
        try reality.validate()
        let filename = "\(reality.savedAt.timeIntervalSince1970)-\(SafeFilename.slug(reality.name))-\(reality.id.uuidString.prefix(8)).json"
        let url = realitiesURL.appendingPathComponent(filename)
        try write(reality, to: url)
        return url
    }

    public func loadReality(from url: URL) throws -> RealitySnapshot {
        let result = try decode(RealitySnapshot.self, from: url)
        try result.validate()
        return result
    }

    @discardableResult
    public func saveLedger(_ ledger: ClaimLedger) throws -> URL {
        try ledger.validate()
        // Ledger filenames are derived from the ledger, never from reviewed text.
        let filename = "\(ledger.createdAt.timeIntervalSince1970)-\(SafeFilename.slug(ledger.projectName))-\(ledger.id.uuidString.prefix(8)).json"
        let url = ledgersURL.appendingPathComponent(filename)
        try write(ledger, to: url)
        return url
    }

    public func loadLedger(from url: URL) throws -> ClaimLedger {
        let result = try decode(ClaimLedger.self, from: url)
        try result.validate()
        return result
    }

    /// Newest first. Ledgers are never pruned or deleted automatically: a
    /// receipt that disappeared on its own would be worse than a disk full of
    /// them. Invalid or oversized files are skipped rather than repaired.
    public func listLedgers() throws -> [ClaimLedger] {
        let urls = try fm.contentsOfDirectory(at: ledgersURL, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension.lowercased() == "json" }
        return try urls.compactMap { url in
            do { return try loadLedger(from: url) }
            catch { return nil }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func listRealities() throws -> [RealitySnapshot] {
        let urls = try fm.contentsOfDirectory(at: realitiesURL, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension.lowercased() == "json" }
        return try urls.compactMap { url in
            do { return try loadReality(from: url) }
            catch { return nil }
        }.sorted { $0.savedAt > $1.savedAt }
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else { throw RelayError.invalid("Only ordinary local JSON files can be loaded.") }
        guard let size = attrs[.size] as? NSNumber, size.intValue <= Limits.fileBytes else { throw RelayError.invalid("The local file exceeds the 2 MB safety limit.") }
        let data = try Data(contentsOf: url)
        guard data.count <= Limits.fileBytes else { throw RelayError.invalid("The local file became too large while reading.") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard data.count <= Limits.fileBytes else { throw RelayError.invalid("The local file exceeds the 2 MB safety limit.") }
        if fm.fileExists(atPath: url.path) {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeRegular else { throw RelayError.invalid("Refusing to overwrite a non-regular file.") }
        }
        // An explicit staging file keeps sensitive data 0600 even before rename.
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".relaybar-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw RelayError.invalid("Could not write the local data file.")
        }
        defer { try? fm.removeItem(at: temporary) }
        // POSIX rename atomically replaces the destination on the same filesystem.
        let result = temporary.path.withCString { source in url.path.withCString { destination in rename(source, destination) } }
        guard result == 0 else { throw RelayError.invalid("Could not commit the local data file (error \(errno)). The previous file is unchanged.") }
    }
}
