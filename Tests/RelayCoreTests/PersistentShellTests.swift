import XCTest
@testable import RelayCore

final class PersistentShellTests: XCTestCase {
    func testDefaultsToPersistentRelayMode() {
        let state = PersistentShellState()
        XCTAssertTrue(state.relayVisible)
        XCTAssertTrue(state.shouldPresent(frontmostIsRelay: false, captureHelper: false))
    }

    func testMacModeHandsBackBarUntilExplicitReturn() {
        var state = PersistentShellState()
        state.enterMacMode()
        XCTAssertEqual(state.mode, .mac)
        XCTAssertFalse(state.relayVisible)
        XCTAssertFalse(state.shouldPresent(frontmostIsRelay: false, captureHelper: false))
        state.returnToRelayBar()
        XCTAssertEqual(state.mode, .relay)
        XCTAssertTrue(state.relayVisible)
    }

    func testPauseDoesNotBecomeMacModeAndResumeReturnsShell() {
        var state = PersistentShellState()
        state.pause()
        XCTAssertTrue(state.paused)
        XCTAssertEqual(state.mode, .relay)
        XCTAssertFalse(state.relayVisible)
        state.resume()
        XCTAssertFalse(state.paused)
        XCTAssertTrue(state.relayVisible)
    }

    func testRelayAndScreenshotHelpersDoNotReceiveModalOverlay() {
        let state = PersistentShellState()
        XCTAssertFalse(state.shouldPresent(frontmostIsRelay: true, captureHelper: false))
        XCTAssertFalse(state.shouldPresent(frontmostIsRelay: false, captureHelper: true))
    }

    func testShellAppsHaveStableBundleIdentities() {
        XCTAssertEqual(PersistentShellApp.chrome.bundleIdentifiers, ["com.google.Chrome"])
        XCTAssertEqual(PersistentShellApp.claude.bundleIdentifiers, ["com.anthropic.claudefordesktop"])
        XCTAssertEqual(PersistentShellApp.chatgpt.bundleIdentifiers, ["com.openai.chat"])
        XCTAssertEqual(PersistentShellApp.allCases.map(\.displayName), ["Chrome", "Claude", "ChatGPT"])
    }

    func testRunningAppsFilterAndDisappearance() {
        var state = PersistentShellState()
        XCTAssertTrue(state.runningApps.isEmpty)
        XCTAssertTrue(state.visibleShellApps.isEmpty)

        // Only Chrome running
        state.updateRunning(chrome: true, claude: false, chatgpt: false)
        XCTAssertEqual(state.visibleShellApps, [.chrome])

        // Chrome and ChatGPT running (Claude not running, disappears)
        state.updateRunning(chrome: true, claude: false, chatgpt: true)
        XCTAssertEqual(state.visibleShellApps, [.chrome, .chatgpt])
        XCTAssertFalse(state.visibleShellApps.contains(.claude))

        // None running -> all disappear
        state.updateRunning(chrome: false, claude: false, chatgpt: false)
        XCTAssertTrue(state.visibleShellApps.isEmpty)

        // All running
        state.updateRunning(chrome: true, claude: true, chatgpt: true)
        XCTAssertEqual(state.visibleShellApps, [.chrome, .claude, .chatgpt])
    }
}
