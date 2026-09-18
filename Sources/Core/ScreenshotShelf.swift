import Foundation

/// Portable policy and storage; image decoding and clipboard operations live in the Mac adapter.
public enum ScreenshotPolicy {
    public static let capacity = 5
    public static let maximumBytes = 80 * 1024 * 1024
    public static let maximumPixels = 50_000_000
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "heif"]

    public static func isCandidate(filename: String, markedAsScreenshot: Bool, customPrefix: String? = nil) -> Bool {
        guard !filename.hasPrefix("."), extensions.contains((filename as NSString).pathExtension.lowercased()) else { return false }
        if markedAsScreenshot { return true }
        let prefixes = ["Screenshot", "Screen Shot", "ScreenShot", "Touch Bar Shot", "Capture d’écran", "Capture d'écran", "Capture d'écran", "Bildschirmfoto", "Captura de pantalla", "Captura de ecrã", "Captura de Tela", "Schermata", "Schermafbeelding", "Skärmbild", "Skjermbilde", "Skærmbillede", "Näyttökuva", "スクリーンショット", "스크린샷", "截屏", "螢幕截圖", "屏幕快照"] + [customPrefix].compactMap { $0 }
        let name = filename.precomposedStringWithCanonicalMapping
        return prefixes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.contains { prefix in
            let p = NSRegularExpression.escapedPattern(for: prefix.precomposedStringWithCanonicalMapping)
            return name.range(of: "^" + p + "[ _-]+[0-9]{4}[- /年][0-9]{1,2}[- /月][0-9]{1,2}", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

public struct ScreenshotEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let sourceKey: String
    public let sourceVersion: String
    public let name: String
    public let capturedAt: Date
    public let addedAt: Date
    public let width: Int
    public let height: Int
    public let byteCount: Int
    public var storageName: String { id.uuidString.lowercased() + ".png" }

    public init(id: UUID = UUID(), sourceKey: String, sourceVersion: String, name: String,
                capturedAt: Date, addedAt: Date = Date(), width: Int, height: Int, byteCount: Int) {
        self.id = id; self.sourceKey = sourceKey; self.sourceVersion = sourceVersion; self.name = name
        self.capturedAt = capturedAt; self.addedAt = addedAt; self.width = width; self.height = height; self.byteCount = byteCount
    }
    public func validate() throws {
        guard !sourceKey.isEmpty, sourceKey.count <= 512, !sourceVersion.isEmpty, sourceVersion.count <= 512,
              !name.isEmpty, name.count <= 1024, !name.contains("\u{0}"),
              capturedAt.timeIntervalSince1970.isFinite, addedAt.timeIntervalSince1970.isFinite,
              width > 0, height > 0, width <= ScreenshotPolicy.maximumPixels / height,
              byteCount > 0, byteCount <= ScreenshotPolicy.maximumBytes else {
            throw RelayError.invalid("Invalid screenshot record or image safety limit exceeded.")
        }
    }
    public static func newestFirst(_ a: Self, _ b: Self) -> Bool {
        if a.capturedAt != b.capturedAt { return a.capturedAt > b.capturedAt }
        if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
        return a.id.uuidString > b.id.uuidString
    }
}

public struct ScreenshotManifest: Codable, Equatable {
    public var schemaVersion = 1
    public var entries: [ScreenshotEntry] = []
    /// Clear is durable: screenshots predating it are not silently re-imported on a later scan/relaunch.
    public var ignoreBefore = Date.distantPast
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1, entries.count <= ScreenshotPolicy.capacity,
              Set(entries.map(\.id)).count == entries.count,
              Set(entries.map(\.sourceKey)).count == entries.count,
              ignoreBefore.timeIntervalSince1970.isFinite else {
            throw RelayError.invalid("Invalid screenshot shelf index. Existing files were left untouched.")
        }
        for entry in entries { try entry.validate() }
    }
    public func contains(sourceKey: String, version: String) -> Bool {
        entries.contains { $0.sourceKey == sourceKey && $0.sourceVersion == version }
    }
}

/// Same-size/mtime evidence must be observed twice, separated by a quiet interval, before reading.
/// The Mac reader also checks a file descriptor before/after reading and validates its image data.
public struct ScreenshotStabilityGate {
    private struct Observation { let version: String; let since: Date }
    private var observations: [String: Observation] = [:]
    public init() {}
    public mutating func isReady(key: String, version: String, byteCount: Int, now: Date, modifiedAt: Date) -> Bool {
        guard byteCount > 0, byteCount <= ScreenshotPolicy.maximumBytes else {
            observations.removeValue(forKey: key); return false
        }
        guard let previous = observations[key], previous.version == version else {
            observations[key] = Observation(version: version, since: now); return false
        }
        return now.timeIntervalSince(previous.since) >= 0.5 && now.timeIntervalSince(modifiedAt) >= 0.5
    }
    public mutating func retain(keys: Set<String>) { observations = observations.filter { keys.contains($0.key) } }
    public mutating func reset() { observations.removeAll() }
}

/// Serialized by its caller. All writes are confined to the shelf directory, never a source folder.
public final class ScreenshotShelfStore {
    public let directory: URL
    public private(set) var manifest = ScreenshotManifest()
    public private(set) var cleanupWarning: String?
    private let fm = FileManager.default
    private var indexURL: URL { directory.appendingPathComponent("index.json") }

    public init(directory: URL) throws {
        self.directory = directory.standardizedFileURL
        if let attrs = try attributesIfPresent(self.directory) {
            guard attrs[.type] as? FileAttributeType == .typeDirectory else { throw RelayError.invalid("Screenshot storage is not an ordinary directory.") }
        } else {
            try fm.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
        if let attrs = try attributesIfPresent(indexURL) {
            guard attrs[.type] as? FileAttributeType == .typeRegular, (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 1_000_000 else {
                throw RelayError.invalid("Screenshot index is not a small ordinary file.")
            }
            manifest = try JSONDecoder().decode(ScreenshotManifest.self, from: Data(contentsOf: indexURL))
            try manifest.validate()
            manifest.entries.sort(by: ScreenshotEntry.newestFirst)
        }
        // Only unreferenced, UUID-named files belonging to our own cache can be pruned.
        cleanupOrphans()
    }

    public func cachedURL(for entry: ScreenshotEntry) -> URL { directory.appendingPathComponent(entry.storageName) }
    public func readPNG(id: UUID) throws -> Data {
        guard let entry = manifest.entries.first(where: { $0.id == id }) else { throw RelayError.invalid("That screenshot is no longer on the shelf.") }
        let url = cachedURL(for: entry)
        guard let attrs = try attributesIfPresent(url), attrs[.type] as? FileAttributeType == .typeRegular,
              (attrs[.size] as? NSNumber)?.intValue == entry.byteCount else {
            throw RelayError.invalid("This cached screenshot is missing or changed. Choose a different screenshot or clear the shelf.")
        }
        let data = try Data(contentsOf: url)
        guard data.count == entry.byteCount else { throw RelayError.invalid("Cached screenshot changed while reading.") }
        return data
    }

    @discardableResult public func insert(_ entry: ScreenshotEntry, png: Data) throws -> Bool {
        try entry.validate()
        guard png.count == entry.byteCount else { throw RelayError.invalid("Screenshot byte count does not match its record.") }
        guard entry.capturedAt > manifest.ignoreBefore else { return false }
        if manifest.contains(sourceKey: entry.sourceKey, version: entry.sourceVersion) { return false }
        guard !manifest.entries.contains(where: { $0.id == entry.id }) else { throw RelayError.invalid("Screenshot identifier collision.") }
        var next = manifest
        next.entries.removeAll { $0.sourceKey == entry.sourceKey }
        next.entries.append(entry)
        next.entries = Array(next.entries.sorted(by: ScreenshotEntry.newestFirst).prefix(ScreenshotPolicy.capacity))
        guard next.entries.contains(where: { $0.id == entry.id }) else { return false }
        try next.validate()
        let destination = cachedURL(for: entry)
        guard try attributesIfPresent(destination) == nil else { throw RelayError.invalid("Refusing to replace an existing screenshot cache file.") }
        try atomicWrite(png, to: destination)
        do { try save(next) }
        catch { try? fm.removeItem(at: destination); throw error }
        manifest = next
        cleanupOrphans()
        return true
    }

    public func clear(at time: Date = Date()) throws {
        var next = ScreenshotManifest(); next.ignoreBefore = time
        try next.validate(); try save(next); manifest = next; cleanupOrphans()
    }

    private func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try fm.attributesOfItem(atPath: url.path) }
        catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) { return nil }
            throw error
        }
    }
    private func save(_ value: ScreenshotManifest) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicWrite(encoder.encode(value), to: indexURL)
    }
    private func atomicWrite(_ data: Data, to destination: URL) throws {
        if let attrs = try attributesIfPresent(destination), attrs[.type] as? FileAttributeType != .typeRegular {
            throw RelayError.invalid("Refusing to write through a substituted cache file.")
        }
        let temporary = directory.appendingPathComponent(".shot-\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw RelayError.invalid("Could not write screenshot storage. The previous index is unchanged.")
        }
        defer { try? fm.removeItem(at: temporary) }
        guard temporary.path.withCString({ src in destination.path.withCString { dst in rename(src, dst) } }) == 0 else {
            throw RelayError.invalid("Could not commit screenshot storage (error \(errno)).")
        }
    }
    private func cleanupOrphans() {
        cleanupWarning = nil
        let retained = Set(manifest.entries.map(\.storageName))
        do {
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let name = url.lastPathComponent
                let managedPNG = url.pathExtension == "png" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
                let managedTemporary = name.hasPrefix(".shot-") && name.hasSuffix(".tmp") && UUID(uuidString: String(name.dropFirst(6).dropLast(4))) != nil
                guard (managedPNG && !retained.contains(name)) || managedTemporary else { continue }
                guard let attrs = try attributesIfPresent(url), attrs[.type] as? FileAttributeType == .typeRegular else { continue }
                try fm.removeItem(at: url)
            }
        } catch { cleanupWarning = "Some old RelayBar cache files could not be removed: \(error.localizedDescription)" }
    }
}
