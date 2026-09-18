import XCTest
@testable import RelayCore

final class BrowserMailboxTests: XCTestCase {
    var base: URL!
    var box: BrowserMailbox!
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("RelayBridge-" + UUID().uuidString)
        box = try BrowserMailbox(root: base.appendingPathComponent("Sessions"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }
    func receipt() -> BrowserReceipt {
        BrowserReceipt(sessionID:UUID().uuidString,browserBundle:"com.google.Chrome",receivedAt:1000,
            context:BrowserContext(kind:"browser",focused:true,tabID:1,windowID:1))
    }
    func testRoundTrip() throws { let r=receipt(); try box.save(r); XCTAssertEqual(box.receipts(),[r]) }
    func testPrivatePermissions() throws {
        let r=receipt(); try box.save(r)
        let root = try FileManager.default.attributesOfItem(atPath:box.root.path)
        let file = try FileManager.default.attributesOfItem(atPath:box.root.appendingPathComponent(r.sessionID+"/context.json").path)
        XCTAssertEqual((root[.posixPermissions] as? NSNumber)?.intValue,0o700)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue,0o600)
    }
    func testCommandConsumedExactlyOnce() throws { let r=receipt(); try box.save(r); let c=BrowserCommand(receipt:r,actionID:"nav.back",now:1000); try box.queue(c); XCTAssertEqual(box.consume(sessionID:r.sessionID),c); XCTAssertNil(box.consume(sessionID:r.sessionID)) }
    func testSecondQueuedCommandRejected() throws { let r=receipt(); try box.save(r); let c=BrowserCommand(receipt:r,actionID:"nav.back",now:1000); try box.queue(c); XCTAssertThrowsError(try box.queue(c)) }
    func testNoCommandsForUncreatedSessions() { XCTAssertThrowsError(try box.queue(BrowserCommand(receipt:receipt(),actionID:"nav.back",now:1000))) }
    func testTraversalRejected() { var r=receipt(); r.sessionID="../evil"; XCTAssertThrowsError(try box.save(r)) }
    func testRemoveOnlyManagedSession() throws { let r=receipt(); try box.save(r); let outside=base.appendingPathComponent("unrelated.txt"); try "keep".write(to:outside,atomically:true,encoding:.utf8); box.remove(sessionID:r.sessionID); XCTAssertEqual(box.receipts(),[]); XCTAssertTrue(FileManager.default.fileExists(atPath:outside.path)) }
    func testExpiredCleanup() throws { let r=receipt(); var fresh=receipt(); fresh.receivedAt=1200; try box.save(r); try box.save(fresh); box.clearExpired(now:1201); XCTAssertEqual(box.receipts(),[fresh]) }
    func testCorruptContextIgnored() throws { let r=receipt(); try box.save(r); try Data("{".utf8).write(to:box.root.appendingPathComponent(r.sessionID+"/context.json")); XCTAssertEqual(box.receipts(),[]) }
    func testRootSymlinkRejected() throws { let link=base.appendingPathComponent("Link"); try FileManager.default.createSymbolicLink(at:link,withDestinationURL:box.root); XCTAssertThrowsError(try BrowserMailbox(root:link)) }
    func testContextSymlinkIgnored() throws { let r=receipt(); try box.save(r); let file=box.root.appendingPathComponent(r.sessionID+"/context.json"); let other=base.appendingPathComponent("original"); try FileManager.default.moveItem(at:file,to:other); try FileManager.default.createSymbolicLink(at:file,withDestinationURL:other); XCTAssertEqual(box.receipts(),[]); XCTAssertTrue(FileManager.default.fileExists(atPath:other.path)) }
    func testWorldReadableContextIgnored() throws { let r=receipt(); try box.save(r); try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:box.root.appendingPathComponent(r.sessionID+"/context.json").path); XCTAssertEqual(box.receipts(),[]) }
}
