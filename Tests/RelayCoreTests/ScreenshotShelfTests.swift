import Foundation
import XCTest
@testable import RelayCore

final class ScreenshotShelfTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("relaybar-shot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func makeStore() throws -> ScreenshotShelfStore { try ScreenshotShelfStore(directory: root.appendingPathComponent("Shelf")) }
    private func entry(_ number: Int, source: String? = nil, version: String? = nil, bytes: Int = 4) -> ScreenshotEntry {
        ScreenshotEntry(sourceKey: source ?? "source-\(number)", sourceVersion: version ?? "version-\(number)",
            name: "Screenshot 2026-09-17 at 10.00.\(number).png", capturedAt: Date(timeIntervalSince1970: Double(number)),
            addedAt: Date(timeIntervalSince1970: Double(number)), width: 1200, height: 800, byteCount: bytes)
    }
    private let data = Data([137, 80, 78, 71]) // Opaque bytes: real image decoding is a native test, not faked here.

    func testEnglishScreenshotFilename() {
        XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "Screenshot 2026-09-17 at 1.41.22 AM.png", markedAsScreenshot: false))
        XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "Screen Shot 2026-09-17 at 02.00.png", markedAsScreenshot: false))
    }
    func testUnicodeSpacesAndFrenchNames() {
        XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "Screenshot 2026-09-17 at 1.41.22 AM.png", markedAsScreenshot: false))
        XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "Capture d’écran 2026-09-17 à 10.00.00.png", markedAsScreenshot: false))
    }
    func testMarkedRenamedImage() { XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "revised-interface.png", markedAsScreenshot: true)) }
    func testCustomScreenshotPrefix() { XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "Hearth Shot 2026-09-17.png", markedAsScreenshot: false, customPrefix: "Hearth Shot")) }
    func testCustomPrefixRegexEscaped() {
        XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "Shot [A] 2026-09-17.png", markedAsScreenshot: false, customPrefix: "Shot [A]"))
        XCTAssertFalse(ScreenshotPolicy.isCandidate(filename: "Shot A 2026-09-17.png", markedAsScreenshot: false, customPrefix: "Shot [A]"))
    }
    func testUnrelatedImagesNotCollected() {
        for name in ["photo.png", "Screenshot project.png", "photo-2026-09-17.jpg", "Screenshot.png"] {
            XCTAssertFalse(ScreenshotPolicy.isCandidate(filename: name, markedAsScreenshot: false))
        }
    }
    func testHiddenAndUnsupportedFilesIgnoredEvenIfMarked() {
        for name in [".Screenshot 2026-09-17.png", "Screenshot 2026-09-17.pdf", "Screen Recording 2026-09-17.mov"] {
            XCTAssertFalse(ScreenshotPolicy.isCandidate(filename: name, markedAsScreenshot: true))
        }
    }
    func testUppercaseAndHEIFExtension() {
        XCTAssertTrue(ScreenshotPolicy.isCandidate(filename: "Screenshot 2026-09-17.HEIF", markedAsScreenshot: false))
    }
    func testExactlyFiveNewestAndOldestCacheEvicted() throws {
        let store = try makeStore()
        let all = (1...6).map { entry($0) }
        for item in all { XCTAssertTrue(try store.insert(item, png: data)) }
        XCTAssertEqual(store.manifest.entries.map(\.sourceKey), ["source-6", "source-5", "source-4", "source-3", "source-2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.cachedURL(for: all[0]).path))
        let pngs = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).filter { $0.hasSuffix(".png") }
        XCTAssertEqual(pngs.count, 5)
    }
    func testOutOfOrderArrivalsAreSortedByCaptureDate() throws {
        let store = try makeStore()
        for n in [3, 1, 6, 2, 5, 4] { _ = try store.insert(entry(n), png: data) }
        XCTAssertEqual(store.manifest.entries.map(\.sourceKey), ["source-6", "source-5", "source-4", "source-3", "source-2"])
    }
    func testRepeatedEventDoesNotDuplicateOrReorder() throws {
        let store = try makeStore()
        _ = try store.insert(entry(1), png: data); _ = try store.insert(entry(2), png: data)
        let before = store.manifest
        XCTAssertFalse(try store.insert(entry(1), png: data)); XCTAssertEqual(store.manifest, before)
    }
    func testEditedScreenshotReplacesOneSlot() throws {
        let store = try makeStore()
        let old = entry(1); _ = try store.insert(old, png: data)
        XCTAssertTrue(try store.insert(entry(1, version: "edited"), png: data))
        XCTAssertEqual(store.manifest.entries.count, 1)
        XCTAssertEqual(store.manifest.entries[0].sourceVersion, "edited")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.cachedURL(for: old).path))
    }
    func testOlderScreenshotCannotDisplaceFiveNewerOnes() throws {
        let store = try makeStore()
        for n in 10...14 { _ = try store.insert(entry(n), png: data) }
        let old = entry(1)
        XCTAssertFalse(try store.insert(old, png: data))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.cachedURL(for: old).path))
    }
    func testRetentionAndBytesSurviveRelaunch() throws {
        let store = try makeStore(); let first = entry(1)
        _ = try store.insert(first, png: data)
        let reopened = try ScreenshotShelfStore(directory: store.directory)
        XCTAssertEqual(reopened.manifest, store.manifest)
        XCTAssertEqual(try reopened.readPNG(id: first.id), data)
    }
    func testClearIsDurableAndOldFilesDoNotReturn() throws {
        let store = try makeStore(); _ = try store.insert(entry(1), png: data)
        try store.clear(at: Date(timeIntervalSince1970: 2))
        let reopened = try ScreenshotShelfStore(directory: store.directory)
        XCTAssertFalse(try reopened.insert(entry(1), png: data))
        XCTAssertFalse(try reopened.insert(entry(2), png: data))
        XCTAssertTrue(try reopened.insert(entry(3), png: data))
        XCTAssertEqual(reopened.manifest.entries.count, 1)
    }
    func testClearAndEvictionNeverTouchSourceOrUnrelatedFile() throws {
        let source = root.appendingPathComponent("Screenshot 2026-09-17.png"); try data.write(to: source)
        let store = try makeStore()
        let unrelated = store.directory.appendingPathComponent("user-note.txt"); try Data("leave me".utf8).write(to: unrelated)
        for n in 1...6 { _ = try store.insert(entry(n), png: data) }
        try store.clear()
        XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertEqual(try String(contentsOf: unrelated), "leave me")
    }
    func testReadingDoesNotReorderHistory() throws {
        let store = try makeStore(); let old = entry(1); _ = try store.insert(old, png: data); _ = try store.insert(entry(2), png: data)
        let order = store.manifest.entries
        XCTAssertEqual(try store.readPNG(id: old.id), data)
        XCTAssertEqual(store.manifest.entries, order)
    }
    func testMissingCachedFileReportsErrorNotWrongImage() throws {
        let store = try makeStore(); let shot = entry(1); _ = try store.insert(shot, png: data)
        try FileManager.default.removeItem(at: store.cachedURL(for: shot))
        XCTAssertThrowsError(try store.readPNG(id: shot.id))
    }
    func testCorruptIndexPreserved() throws {
        let store = try makeStore(); let index = store.directory.appendingPathComponent("index.json")
        try Data("not json".utf8).write(to: index)
        XCTAssertThrowsError(try ScreenshotShelfStore(directory: store.directory))
        XCTAssertEqual(try String(contentsOf: index), "not json")
    }
    func testCacheDirectorySymlinkRefused() throws {
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try ScreenshotShelfStore(directory: link))
    }
    func testIndexSymlinkRefused() throws {
        let store = try makeStore(); let external = root.appendingPathComponent("external.json")
        try Data("keep".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: store.directory.appendingPathComponent("index.json"), withDestinationURL: external)
        XCTAssertThrowsError(try ScreenshotShelfStore(directory: store.directory))
        XCTAssertEqual(try String(contentsOf: external), "keep")
    }
    func testCachedImageSymlinkRefused() throws {
        let store = try makeStore(); let shot = entry(1); _ = try store.insert(shot, png: data)
        let external = root.appendingPathComponent("external.png"); try data.write(to: external)
        try FileManager.default.removeItem(at: store.cachedURL(for: shot))
        try FileManager.default.createSymbolicLink(at: store.cachedURL(for: shot), withDestinationURL: external)
        XCTAssertThrowsError(try store.readPNG(id: shot.id))
        try store.clear()
        XCTAssertEqual(try Data(contentsOf: external), data)
    }
    func testFailedIndexCommitLeavesPreviousEntriesIntact() throws {
        let store = try makeStore(); let previous = entry(1); _ = try store.insert(previous, png: data)
        let index = store.directory.appendingPathComponent("index.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        let next = entry(2)
        XCTAssertThrowsError(try store.insert(next, png: data))
        XCTAssertEqual(store.manifest.entries, [previous])
        XCTAssertEqual(try store.readPNG(id: previous.id), data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.cachedURL(for: next).path))
    }
    func testPixelAndByteLimits() throws {
        let bad = ScreenshotEntry(sourceKey: "a", sourceVersion: "b", name: "bad", capturedAt: Date(), width: Int.max, height: Int.max, byteCount: 1)
        XCTAssertThrowsError(try bad.validate())
        XCTAssertThrowsError(try entry(1, bytes: ScreenshotPolicy.maximumBytes + 1).validate())
        XCTAssertThrowsError(try entry(1, bytes: 0).validate())
    }
    func testBytesMustMatchMetadata() throws { XCTAssertThrowsError(try makeStore().insert(entry(1, bytes: 5), png: data)) }
    func testPermissionsArePrivate() throws {
        let store = try makeStore(); let shot = entry(1); _ = try store.insert(shot, png: data)
        let fm = FileManager.default
        XCTAssertEqual((try fm.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        for url in [store.cachedURL(for: shot), store.directory.appendingPathComponent("index.json")] {
            XCTAssertEqual((try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }
    func testStableGateNeedsTwoObservationsAndQuietTime() {
        var gate = ScreenshotStabilityGate(); let t = Date(timeIntervalSince1970: 10)
        XCTAssertFalse(gate.isReady(key: "a", version: "v1", byteCount: 20, now: t, modifiedAt: t))
        XCTAssertFalse(gate.isReady(key: "a", version: "v1", byteCount: 20, now: t.addingTimeInterval(0.2), modifiedAt: t))
        XCTAssertTrue(gate.isReady(key: "a", version: "v1", byteCount: 20, now: t.addingTimeInterval(0.6), modifiedAt: t))
    }
    func testStableGateResetsWhenWriterChangesFile() {
        var gate = ScreenshotStabilityGate(); let t = Date(timeIntervalSince1970: 10)
        _ = gate.isReady(key: "a", version: "v1", byteCount: 20, now: t, modifiedAt: t)
        XCTAssertFalse(gate.isReady(key: "a", version: "v2", byteCount: 21, now: t.addingTimeInterval(1), modifiedAt: t))
        XCTAssertTrue(gate.isReady(key: "a", version: "v2", byteCount: 21, now: t.addingTimeInterval(2), modifiedAt: t))
    }
    func testStableGateRejectsEmptyAndOversize() {
        var gate = ScreenshotStabilityGate(); let t = Date()
        for count in [0, -1, ScreenshotPolicy.maximumBytes + 1] {
            XCTAssertFalse(gate.isReady(key: "a", version: "v", byteCount: count, now: t, modifiedAt: t.addingTimeInterval(-10)))
        }
    }
    func testManifestRejectsMoreThanFiveAndDuplicateIDs() throws {
        var index = ScreenshotManifest(); index.entries = (1...6).map { entry($0) }
        XCTAssertThrowsError(try index.validate())
        index.entries = [entry(1)]; index.entries.append(index.entries[0]); XCTAssertThrowsError(try index.validate())
    }
    func testOrphanCleanupDeletesOnlyOwnedUUIDPNGs() throws {
        let store = try makeStore(); let orphan = store.directory.appendingPathComponent(UUID().uuidString.lowercased() + ".png")
        try data.write(to: orphan)
        let other = store.directory.appendingPathComponent("my-image.png"); try data.write(to: other)
        _ = try ScreenshotShelfStore(directory: store.directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertEqual(try Data(contentsOf: other), data)
    }
}
