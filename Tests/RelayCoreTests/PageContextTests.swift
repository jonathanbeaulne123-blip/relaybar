import XCTest
@testable import RelayCore

final class PageContextTests: XCTestCase {

    func testLinkModeUsesURLAndTitleWithoutAnyPermission() throws {
        let input = PageContextInput(url: "https://example.com/a?q=1", title: "An article")
        let reference = try PageContextPolicy.build(input, mode: .link)
        XCTAssertTrue(reference.text.contains("Page: An article"))
        XCTAssertTrue(reference.text.contains("URL: https://example.com/a?q=1"))
        XCTAssertTrue(reference.text.contains("Query: q=1"))
        XCTAssertEqual(reference.mode, .link)
        XCTAssertEqual(reference.host, "example.com")
        XCTAssertEqual(reference.origin, "Page: example.com")
        XCTAssertFalse(reference.text.contains("Selected passage"))
    }

    func testLinkModeNeverIncludesSelectionEvenWhenSupplied() throws {
        let input = PageContextInput(url: "https://example.com/", title: "T", selection: "secret passage", excerpt: "secret page")
        let reference = try PageContextPolicy.build(input, mode: .link)
        XCTAssertFalse(reference.text.contains("secret"))
    }

    func testUnidentifiableTargetIsRefused() {
        XCTAssertThrowsError(try PageContextPolicy.build(PageContextInput(), mode: .link)) { error in
            XCTAssertTrue(error.localizedDescription.contains("no page to reference"))
        }
    }

    func testTitleAloneIsEnoughForADesktopApplication() throws {
        let reference = try PageContextPolicy.build(PageContextInput(title: "Untitled chat"), mode: .link)
        XCTAssertTrue(reference.text.contains("Page: Untitled chat"))
        XCTAssertTrue(reference.text.contains("URL: (not available for this application)"))
    }

    func testOverlongTitleIsVisiblyElidedRatherThanSilentlyCut() throws {
        let reference = try PageContextPolicy.build(PageContextInput(title: String(repeating: "t", count: 500)), mode: .link)
        XCTAssertTrue(reference.text.contains("…"))
    }

    func testSelectionModeWithoutASelectionIsAnExplicitRefusal() {
        let input = PageContextInput(url: "https://example.com/", title: "T")
        XCTAssertThrowsError(try PageContextPolicy.build(input, mode: .selection)) { error in
            XCTAssertTrue(error.localizedDescription.contains("No text is selected"))
        }
    }

    func testSelectionModeIncludesThePassage() throws {
        let input = PageContextInput(url: "https://example.com/", title: "T", selection: "  A quoted line  ")
        let reference = try PageContextPolicy.build(input, mode: .selection)
        XCTAssertTrue(reference.text.contains("Selected passage:"))
        XCTAssertTrue(reference.text.contains("A quoted line"))
    }

    func testSelectionOverTheLimitIsRefusedInsteadOfTruncated() {
        let input = PageContextInput(url: "https://example.com/", title: "T",
                                     selection: String(repeating: "x", count: PageContextPolicy.maximumSelection + 1))
        XCTAssertThrowsError(try PageContextPolicy.build(input, mode: .selection)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Nothing was truncated"))
        }
    }

    func testExcerptModeNeedsAnIdentifiedPage() {
        XCTAssertThrowsError(try PageContextPolicy.build(PageContextInput(title: "Desktop app"), mode: .excerpt))
    }

    func testExcerptModeWithoutContentIsRefusedRatherThanDowngraded() {
        let input = PageContextInput(url: "https://example.com/", title: "T")
        XCTAssertThrowsError(try PageContextPolicy.build(input, mode: .excerpt)) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not read a bounded excerpt"))
        }
    }

    func testExcerptModeIncludesProse() throws {
        let input = PageContextInput(url: "https://example.com/", title: "T", excerpt: "First paragraph.")
        let reference = try PageContextPolicy.build(input, mode: .excerpt)
        XCTAssertTrue(reference.text.contains("Excerpt:"))
        XCTAssertTrue(reference.text.contains("First paragraph."))
    }

    func testSensitiveHostsAreRefusedForExcerpts() {
        for host in ["mychart.example.org", "bank.example.com", "irs.gov", "www.tax.service.gov.example",
                     "1password.com", "patient-portal.example"] {
            XCTAssertFalse(PageContextPolicy.allowsExcerpt(host: host), host)
            XCTAssertThrowsError(try PageContextPolicy.build(PageContextInput(url: "https://\(host)/", title: "T", excerpt: "x"),
                                                             mode: .excerpt), host)
        }
    }

    func testShortKeywordsMatchWholeLabelsOnly() {
        // "syntax" contains "tax" but is not the label "tax", so it stays usable.
        XCTAssertTrue(PageContextPolicy.allowsExcerpt(host: "syntax.example.com"))
        XCTAssertFalse(PageContextPolicy.allowsExcerpt(host: "tax.example.com"))
        XCTAssertTrue(PageContextPolicy.allowsExcerpt(host: "example.com"))
    }

    func testExcerptLimitIsEnforcedNotTrimmed() {
        let input = PageContextInput(url: "https://example.com/", title: "T",
                                     excerpt: String(repeating: "x", count: PageContextPolicy.maximumExcerpt + 1))
        XCTAssertThrowsError(try PageContextPolicy.build(input, mode: .excerpt))
    }

    func testControlCharactersAreStrippedFromEveryField() throws {
        let input = PageContextInput(url: "https://example.com/", title: "Ti\u{0}tle",
                                     selection: "se\u{7}lect")
        let reference = try PageContextPolicy.build(input, mode: .selection)
        XCTAssertFalse(reference.text.contains("\u{0}"))
        XCTAssertFalse(reference.text.contains("\u{7}"))
    }

    func testReferenceFitsTheExistingPromptLimit() throws {
        let input = PageContextInput(url: "https://example.com/", title: "T",
                                     selection: String(repeating: "y", count: PageContextPolicy.maximumSelection))
        let reference = try PageContextPolicy.build(input, mode: .selection)
        XCTAssertLessThanOrEqual(reference.text.count, Limits.reference)
        XCTAssertNoThrow(try Limits.validate(capture: Capture(text: reference.text, origin: reference.origin), task: ""))
    }

    func testModesAreStableForPersistence() {
        for mode in PageContextMode.allCases {
            XCTAssertEqual(PageContextMode(rawValue: mode.rawValue), mode)
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.help.isEmpty)
        }
    }
}
