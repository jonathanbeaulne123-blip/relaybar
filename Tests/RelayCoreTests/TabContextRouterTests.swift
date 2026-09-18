import XCTest
import Cocoa

final class TabContextRouterTests: XCTestCase {

    func testDetectContextSheets() {
        let sheetURL = "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit"
        XCTAssertEqual(TabContextRouter.detectContext(url: sheetURL, title: "Q3 Budget - Google Sheets"), .sheets)

        let scriptURL = "https://script.google.com/macros/d/abc/edit"
        XCTAssertEqual(TabContextRouter.detectContext(url: scriptURL, title: "Apps Script"), .sheets)
    }

    func testDetectContextDocs() {
        let docURL = "https://docs.google.com/document/d/1abc123/edit"
        XCTAssertEqual(TabContextRouter.detectContext(url: docURL, title: "Meeting Notes - Google Docs"), .docs)
    }

    func testDetectContextGitHub() {
        let ghURL = "https://github.com/swiftlang/swift/pull/1234"
        XCTAssertEqual(TabContextRouter.detectContext(url: ghURL, title: "Fix bug in compiler by dev · Pull Request #1234 · swiftlang/swift"), .github)
    }

    func testDetectContextGeneral() {
        let url = "https://news.ycombinator.com"
        XCTAssertEqual(TabContextRouter.detectContext(url: url, title: "Hacker News"), .general)

        let emptyURL = ""
        XCTAssertEqual(TabContextRouter.detectContext(url: emptyURL, title: "New Tab"), .general)
    }

    func testSheetsActions() {
        let actions = TabContextRouter.actions(for: .sheets)
        XCTAssertEqual(actions.count, 4)
        XCTAssertTrue(actions.contains(where: { $0.id == "sheets.menu" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "sheets.currency" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "sheets.filter" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "sheets.freeze" }))
    }

    func testGitHubActions() {
        let actions = TabContextRouter.actions(for: .github)
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(actions.contains(where: { $0.id == "github.prs" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "github.issues" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "github.actions" }))
    }

    func testDocsActions() {
        let actions = TabContextRouter.actions(for: .docs)
        XCTAssertEqual(actions.count, 3)
        XCTAssertTrue(actions.contains(where: { $0.id == "docs.menu" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "docs.bold" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "docs.note" }))
    }

    func testGeneralActions() {
        let actions = TabContextRouter.actions(for: .general)
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.contains(where: { $0.id == "general.clip" }))
        XCTAssertTrue(actions.contains(where: { $0.id == "general.shot" }))
    }
}
