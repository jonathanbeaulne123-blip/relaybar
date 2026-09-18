import XCTest
@testable import RelayCore

final class BrowserTabTests: XCTestCase {
    func testBrowserTabCleanTitle() {
        let tab1 = BrowserTab(id: 1, index: 1, title: "Q3 Budget & Forecast - Google Sheets", url: "https://docs.google.com/spreadsheets/d/123/edit", isSelected: true)
        XCTAssertEqual(tab1.cleanTitle, "Q3 Budget & For…")

        let tab2 = BrowserTab(id: 2, index: 2, title: "GitHub - Google Chrome", url: "https://github.com", isSelected: false)
        XCTAssertEqual(tab2.cleanTitle, "GitHub")

        let tab3 = BrowserTab(id: 3, index: 3, title: "", url: "https://news.ycombinator.com/item?id=1", isSelected: false)
        XCTAssertEqual(tab3.cleanTitle, "news.ycombinato…")
    }

    func testBrowserTabDomain() {
        let tab = BrowserTab(id: 1, index: 1, title: "Docs", url: "https://Docs.Google.Com/spreadsheets/d/abc", isSelected: true)
        XCTAssertEqual(tab.domain, "docs.google.com")
    }

    func testWebsiteDispatcherRouting() {
        let sheetsURL = "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit"
        XCTAssertEqual(WebsiteDispatcher.target(for: sheetsURL), .sheets)

        let githubURL = "https://github.com/apple/swift"
        XCTAssertEqual(WebsiteDispatcher.target(for: githubURL), .none)

        let searchURL = "https://www.google.com/search?q=swift"
        XCTAssertEqual(WebsiteDispatcher.target(for: searchURL), .none)

        let emptyURL = ""
        XCTAssertEqual(WebsiteDispatcher.target(for: emptyURL), .none)
    }

    func testAppsScriptMenuClassification() {
        struct DummyNode: Hashable {}
        let dummy = DummyNode()
        let rect = NativeRect(x: 0, y: 0, width: 50, height: 20)

        // Custom Apps Script menu added to menu bar
        let customMenu = NativeControl(node: dummy, label: "Invoice Generator", path: "", role: "AXMenuBarItem", isMenu: true, action: "AXPress", enabled: true, frame: rect)
        XCTAssertTrue(customMenu.isAppsScript)

        // Standard File menu
        let fileMenu = NativeControl(node: dummy, label: "File", path: "", role: "AXMenuBarItem", isMenu: true, action: "AXPress", enabled: true, frame: rect)
        XCTAssertFalse(fileMenu.isAppsScript)

        // Item under Extensions menu
        let extTool = NativeControl(node: dummy, label: "Macros", path: "Extensions › Macros", role: "AXMenuItem", isMenu: false, action: "AXPress", enabled: true, frame: rect)
        XCTAssertTrue(extTool.isAppsScript)
    }

    func testRelayPageHierarchyForWebsiteAndSheets() {
        XCTAssertEqual(RelayPage.websiteTabs.parent, .home)
        XCTAssertEqual(RelayPage.sheetsTools.parent, .appControls)
        XCTAssertEqual(RelayPage.websiteTabs.title, "Tabs")
        XCTAssertEqual(RelayPage.sheetsTools.title, "Sheets Tools")
    }

    func testTabReorderingPreservesIdentity() {
        let tabA = BrowserTab(id: 1977175587, index: 1, title: "GitHub", url: "https://github.com", isSelected: true)
        let tabB = BrowserTab(id: 1977175591, index: 2, title: "Google Sheets", url: "https://docs.google.com/spreadsheets/d/123/edit", isSelected: false)
        let original = [tabA, tabB]

        // Reorder in Chrome: tabB dragged to first position
        let reordered = [
            BrowserTab(id: tabB.id, index: 1, title: tabB.title, url: tabB.url, isSelected: false),
            BrowserTab(id: tabA.id, index: 2, title: tabA.title, url: tabA.url, isSelected: true)
        ]

        XCTAssertNotEqual(original, reordered)
        XCTAssertEqual(reordered[0].id, 1977175591)
        XCTAssertEqual(reordered[1].id, 1977175587)
        XCTAssertEqual(reordered[0].cleanTitle, "Google Sheets")
        XCTAssertEqual(reordered[1].cleanTitle, "GitHub")
    }
}
