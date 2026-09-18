import XCTest
@testable import RelayCore

final class ScreenshotPresentationTests: XCTestCase {
    func testAutoOpenIsOnByDefault() {
        XCTAssertTrue(ScreenshotPresentationState().autoOpenEnabled)
    }
    func testCaptureSelectsViewerFromTools() {
        var state = ScreenshotPresentationState(); state.showTools()
        XCTAssertNotNil(state.screenshotAdded())
        XCTAssertEqual(state.page, .screenshots)
    }
    func testCaptureRequestsRealReopenNotCachedPresent() {
        var state = ScreenshotPresentationState(); state.screenshotAdded()
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .reopen)
    }
    func testSecondCaptureInViewerRequestsAnotherReopen() {
        var state = ScreenshotPresentationState(); state.screenshotAdded(); state.overlayPresented()
        state.screenshotAdded()
        XCTAssertEqual(state.page, .screenshots)
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .reopen)
    }
    func testDisabledCrossAppNeverOpensAnOverlay() {
        var state = ScreenshotPresentationState(); state.screenshotAdded()
        XCTAssertEqual(state.overlayAction(overlayEnabled: false, eligibleApp: true), .dismiss)
        XCTAssertEqual(state.page, .screenshots) // ready in the native panel, no focus change
    }
    func testScreenshotAppCannotBeOverridden() {
        var state = ScreenshotPresentationState(); state.screenshotAdded()
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: false), .dismiss)
        XCTAssertTrue(state.needsOverlayReopen)
    }
    func testReturnToEligibleAppFulfillsPendingReveal() {
        var state = ScreenshotPresentationState(); state.screenshotAdded()
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: false), .dismiss)
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .reopen)
        state.overlayPresented()
        XCTAssertFalse(state.needsOverlayReopen)
    }
    func testSuccessfulPresentationDoesNotReopenOnRoutineUpdates() {
        var state = ScreenshotPresentationState(); state.screenshotAdded(); state.overlayPresented()
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .present)
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .present)
    }
    func testRecoveryCanReopenSameBarAfterOSDisplacesIt() throws {
        var state = ScreenshotPresentationState(); let ticket = try XCTUnwrap(state.screenshotAdded())
        state.overlayPresented()
        XCTAssertTrue(state.requestRecovery(ticket: ticket))
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .reopen)
    }
    func testToolsCancelsPendingRecovery() throws {
        var state = ScreenshotPresentationState(); let ticket = try XCTUnwrap(state.screenshotAdded())
        state.showTools()
        XCTAssertFalse(state.requestRecovery(ticket: ticket))
        XCTAssertEqual(state.page, .tools)
    }
    func testNewCaptureAfterToolsStillAutoOpens() {
        var state = ScreenshotPresentationState(); state.screenshotAdded(); state.showTools()
        state.screenshotAdded()
        XCTAssertEqual(state.page, .screenshots)
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .reopen)
    }
    func testHideDisablesAllScheduledRecovery() throws {
        var state = ScreenshotPresentationState(); let ticket = try XCTUnwrap(state.screenshotAdded())
        state.overlayDisabled()
        XCTAssertFalse(state.requestRecovery(ticket: ticket))
        XCTAssertFalse(state.needsOverlayReopen)
        XCTAssertEqual(state.overlayAction(overlayEnabled: false, eligibleApp: true), .dismiss)
    }
    func testThumbnailTapCancelsRetryWithoutLeavingViewer() throws {
        var state = ScreenshotPresentationState(); let ticket = try XCTUnwrap(state.screenshotAdded())
        state.overlayPresented(); state.cancelRecovery()
        XCTAssertFalse(state.requestRecovery(ticket: ticket))
        XCTAssertEqual(state.page, .screenshots)
    }
    func testOlderCaptureTicketCannotOverrideNewerCapture() throws {
        var state = ScreenshotPresentationState()
        let old = try XCTUnwrap(state.screenshotAdded())
        let new = try XCTUnwrap(state.screenshotAdded())
        XCTAssertNotEqual(old, new)
        XCTAssertFalse(state.requestRecovery(ticket: old))
        XCTAssertTrue(state.requestRecovery(ticket: new))
    }
    func testAutoOpenOffKeepsToolsAndReturnsNoTicket() {
        var state = ScreenshotPresentationState(autoOpenEnabled: false); state.showTools(); state.overlayPresented()
        XCTAssertNil(state.screenshotAdded())
        XCTAssertEqual(state.page, .tools)
        XCTAssertFalse(state.needsOverlayReopen)
    }
    func testDisablingAutoOpenCancelsAlreadyScheduledRetries() throws {
        var state = ScreenshotPresentationState(); let ticket = try XCTUnwrap(state.screenshotAdded())
        state.setAutoOpenEnabled(false)
        XCTAssertFalse(state.requestRecovery(ticket: ticket))
        XCTAssertNil(state.recoveryTicket)
    }
    func testReenableWaitsForNextCapture() {
        var state = ScreenshotPresentationState(autoOpenEnabled: false); state.showTools(); state.overlayPresented()
        state.setAutoOpenEnabled(true)
        XCTAssertEqual(state.page, .tools)
        XCTAssertNil(state.recoveryTicket)
        XCTAssertFalse(state.needsOverlayReopen)
        state.screenshotAdded()
        XCTAssertEqual(state.page, .screenshots)
    }
    func testManualShotsWorksWithAutoOpenOff() {
        var state = ScreenshotPresentationState(autoOpenEnabled: false); state.showTools()
        state.showScreenshots()
        XCTAssertEqual(state.page, .screenshots)
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .reopen)
        XCTAssertNil(state.recoveryTicket)
    }
    func testManualShotsCancelsOldRecovery() throws {
        var state = ScreenshotPresentationState(); let ticket = try XCTUnwrap(state.screenshotAdded())
        state.showScreenshots()
        XCTAssertFalse(state.requestRecovery(ticket: ticket))
    }
    func testLayoutChangesRequestFreshPresentation() {
        var state = ScreenshotPresentationState(); state.overlayPresented(); state.layoutChanged()
        XCTAssertTrue(state.needsOverlayReopen)
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: true), .reopen)
    }
    func testLayoutChangeCannotEnableOverlay() {
        var state = ScreenshotPresentationState(); state.layoutChanged()
        XCTAssertEqual(state.overlayAction(overlayEnabled: false, eligibleApp: true), .dismiss)
        XCTAssertEqual(state.overlayAction(overlayEnabled: true, eligibleApp: false), .dismiss)
    }
    func testRecoveryIsBoundedAndOrdered() {
        XCTAssertEqual(ScreenshotPresentationState.recoveryDelays, [0.35, 1.0, 2.0])
        XCTAssertEqual(ScreenshotPresentationState.recoveryDelays.count, 3)
    }
    func testRandomRecoveryTicketHasNoEffect() {
        var state = ScreenshotPresentationState(); state.overlayPresented()
        XCTAssertFalse(state.requestRecovery(ticket: UUID()))
        XCTAssertFalse(state.needsOverlayReopen)
    }
    func testRapidBurstCoalescesOntoLatestCapture() throws {
        var state = ScreenshotPresentationState(); var tickets: [UUID] = []
        for _ in 0..<25 { tickets.append(try XCTUnwrap(state.screenshotAdded())) }
        for ticket in tickets.dropLast() { XCTAssertFalse(state.requestRecovery(ticket: ticket)) }
        XCTAssertTrue(state.requestRecovery(ticket: try XCTUnwrap(tickets.last)))
        XCTAssertEqual(state.page, .screenshots)
    }
}
