import XCTest
import Cocoa
@testable import RelayCore

final class AppSwitcherTests: XCTestCase {

    @MainActor
    func testCanonicalOrder() {
        let running = AppSwitcher.runningApps()
        // If any are returned, they must strictly follow canonical order: chrome, claude, chatgpt
        var lastIndex = -1
        let canonicalOrder: [PersistentShellApp] = [.chrome, .claude, .chatgpt]
        for app in running {
            let index = canonicalOrder.firstIndex(of: app) ?? -1
            XCTAssertGreaterThan(index, lastIndex)
            lastIndex = index
        }
    }

    @MainActor
    func testIsRunningWithNonExistentApp() {
        // App that is not installed/running under a dummy URL should return false
        let dummyURL = URL(fileURLWithPath: "/NonExistent/Path/To/App.app")
        XCTAssertFalse(AppSwitcher.isRunning(.chatgpt, configuredAssistantURL: dummyURL))
    }
}
