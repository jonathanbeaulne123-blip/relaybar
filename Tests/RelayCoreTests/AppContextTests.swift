import XCTest
@testable import RelayCore

final class AppContextTests: XCTestCase {
    let browser = "com.google.Chrome"
    let now: Double = 1000
    func receipt() -> BrowserReceipt {
        BrowserReceipt(sessionID: UUID().uuidString, browserBundle: browser, receivedAt: now,
            context: BrowserContext(kind: "sheets", focused: true, tabID: 7, windowID: 2,
                sheetID: "sheet_TEST_12345", pageToken: "12345678-1234-1234-1234-123456789abc", title: "Test workbook",
                actions: [.init(id: "menu:test", label: "Test script")]))
    }
    func testValidReceipt() throws { try receipt().validate() }
    func testNoneAllowed() throws { try BrowserContext().validate() }
    func testUnknownKindRejected() { XCTAssertThrowsError(try BrowserContext(kind: "runShell").validate()) }
    func testVersionRejected() { var r = receipt(); r.context.version = 2; XCTAssertThrowsError(try r.validate()) }
    func testFakeSheetIdentityRejected() { var r = receipt(); r.context.sheetID = "../../other"; XCTAssertThrowsError(try r.validate()) }
    func testMissingTokenRejected() { var r = receipt(); r.context.pageToken = ""; XCTAssertThrowsError(try r.validate()) }
    func testUnlinkedSheetAllowed() throws { var r = receipt(); r.context.pageToken = ""; r.context.actions = []; try r.validate() }
    func testUnsafeActionIDRejected() { var r = receipt(); r.context.actions[0].id = "run();evil"; XCTAssertThrowsError(try r.validate()) }
    func testControlCharactersRejected() { var r = receipt(); r.context.actions[0].label = "good\nbad"; XCTAssertThrowsError(try r.validate()) }
    func testDuplicateIDsRejected() { var r = receipt(); r.context.actions += r.context.actions; XCTAssertThrowsError(try r.validate()) }
    func testEmptyCaptionRejected() { var r = receipt(); r.context.actions[0].label = " "; XCTAssertThrowsError(try r.validate()) }
    func testOtherKindCannotCarryScripts() { var r = receipt(); r.context.kind = "browser"; XCTAssertThrowsError(try r.validate()) }
    func testUnknownBrowserRejected() { var r = receipt(); r.browserBundle = "evil.app"; XCTAssertThrowsError(try r.validate()) }
    func testNegativeTabRejected() { var r = receipt(); r.context.tabID = -2; XCTAssertThrowsError(try r.validate()) }
    func testFocusedNoneRejected() { XCTAssertThrowsError(try BrowserContext(focused: true).validate()) }
    func testOversizedManifestRejected() { var r = receipt(); r.context.actions = (0..<121).map { .init(id: "a\($0)", label: "A") }; XCTAssertThrowsError(try r.validate()) }
    func testExactSheetContextSelected() { let r = receipt(); XCTAssertEqual(AppContextPolicy.select([r], for: browser, now: now), r) }
    func testStaleContextIgnored() { XCTAssertNil(AppContextPolicy.select([receipt()], for: browser, now: now+3)) }
    func testFutureContextIgnored() { XCTAssertNil(AppContextPolicy.select([receipt()], for: browser, now: now-1)) }
    func testDifferentBrowserIgnored() { XCTAssertNil(AppContextPolicy.select([receipt()], for: "com.brave.Browser", now: now)) }
    func testTwoFocusedProfilesRejected() { XCTAssertNil(AppContextPolicy.select([receipt(), receipt()], for: browser, now: now)) }
    func testBackgroundProfileIgnored() { let r = receipt(); var b = receipt(); b.context.focused = false; XCTAssertEqual(AppContextPolicy.select([r,b], for: browser, now: now),r) }
    func testValidTapPermitted() { let r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); XCTAssertTrue(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)) }
    func testOldTabTapDenied() { var r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); r.context.tabID += 1; XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)) }
    func testOldWorkbookTapDenied() { var r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); r.context.sheetID = "different_SHEET_12345"; XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)) }
    func testOldSidebarTapDenied() { var r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); r.context.pageToken = UUID().uuidString; XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)) }
    func testOldConnectionTapDenied() { var r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); r.sessionID = UUID().uuidString; XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)) }
    func testExpiredTapDenied() { let r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now+3)) }
    func testAppSwitchDeniesTap() { let r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: "com.openai.chat", now: now)) }
    func testRemovedButtonDenied() { var r = receipt(); let c = BrowserCommand(receipt: r, actionID: "menu:test", now: now); r.context.actions = []; XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)) }
    func testUnknownActionDenied() { let r = receipt(); let c = BrowserCommand(receipt: r, actionID: "shell:rm", now: now); XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)) }
    func testNavigationPermittedOnlySameContext() { let r = receipt(); let c = BrowserCommand(receipt: r, actionID: "nav.back", now: now); XCTAssertTrue(AppContextPolicy.permits(c, receipt:r, frontmostBundle: browser, now: now)); XCTAssertFalse(AppContextPolicy.permits(c, receipt:r, frontmostBundle: "other", now: now)) }
    func testAllButtonsReachable() { let a = (0..<120).map { SheetButton(id:"a\($0)", label:"Action \($0)") }; let pages = (0..<AppContextPolicy.pageCount(a.count)).flatMap { AppContextPolicy.buttons(a,page:$0) }; XCTAssertEqual(a,pages) }
    func testPageBounds() { XCTAssertEqual(AppContextPolicy.buttons(receipt().context.actions,page:-1),[]); XCTAssertEqual(AppContextPolicy.buttons(receipt().context.actions,page:99),[]) }
    func testEmptyPageCount() { XCTAssertEqual(AppContextPolicy.pageCount(0),1) }
    func testInitialAppChangeResetsLayout() { var s=ContextLayoutState(); XCTAssertTrue(s.observe(appBundle:browser,browserIdentity:nil)) }
    func testFirstBrowserLinkDoesNotDismissScreenshot() { var s=ContextLayoutState(); _=s.observe(appBundle:browser,browserIdentity:nil); XCTAssertFalse(s.observe(appBundle:browser,browserIdentity:"a")) }
    func testLinkOutageDoesNotDismissScreenshot() { var s=ContextLayoutState(); _=s.observe(appBundle:browser,browserIdentity:"a"); XCTAssertFalse(s.observe(appBundle:browser,browserIdentity:nil)); XCTAssertFalse(s.observe(appBundle:browser,browserIdentity:"a")) }
    func testConfirmedTabSwitchResetsLayout() { var s=ContextLayoutState(); _=s.observe(appBundle:browser,browserIdentity:"a"); XCTAssertTrue(s.observe(appBundle:browser,browserIdentity:"b")) }
    func testRealAppSwitchResetsLayout() { var s=ContextLayoutState(); _=s.observe(appBundle:browser,browserIdentity:"a"); XCTAssertTrue(s.observe(appBundle:"com.openai.chat",browserIdentity:nil)) }
}
