import XCTest
@testable import RelayCore

final class ButtonHierarchyTests: XCTestCase {
    func testHomeIsFiveFamiliesInStableOrder() { XCTAssertEqual(RelayHierarchy.items(on: .home), [.page(.prompting), .page(.context), .page(.chats), .page(.workspace), .page(.settings)]) }
    func testRootContainsNoExecutionActions() { XCTAssertTrue(RelayHierarchy.items(on: .home).allSatisfy { if case .page = $0 { return true }; return false }) }
    func testRequestedPromptTrioIsDirect() { XCTAssertEqual(Array(RelayHierarchy.items(on: .prompting).prefix(3)), [.command(.prompt(.nextSlice)), .command(.prompt(.challenge)), .command(.prompt(.handoff))]) }
    func testAllNinePromptsHaveExactlyOneHome() {
        let actions = RelayPage.allCases.flatMap { RelayHierarchy.items(on: $0) }.compactMap { item -> PromptAction? in
            if case .command(.prompt(let a)) = item { return a }; return nil
        }
        XCTAssertEqual(Set(actions), Set(PromptAction.allCases)); XCTAssertEqual(actions.count, PromptAction.allCases.count)
    }
    func testWritingPromptsAreSiblings() { XCTAssertEqual(RelayHierarchy.items(on: .writePrompts), [.command(.prompt(.tighten)), .command(.prompt(.expand))]) }
    func testTechnicalPromptsAreSiblings() { XCTAssertEqual(RelayHierarchy.items(on: .buildPrompts).count, 4) }
    func testAllPagesReachableFromHome() {
        var seen = Set<RelayPage>()
        func walk(_ p: RelayPage) { guard seen.insert(p).inserted else { return }; for i in RelayHierarchy.items(on: p) { if case .page(let child) = i { walk(child) } } }
        walk(.home); XCTAssertEqual(seen, Set(RelayPage.allCases))
    }
    func testEveryChildHasCorrectParent() { for p in RelayPage.allCases { for i in RelayHierarchy.items(on: p) { if case .page(let c) = i { XCTAssertEqual(c.parent, p) } } } }
    func testNoDuplicateItemIDsOnPage() { for p in RelayPage.allCases { let ids=RelayHierarchy.items(on:p).map(\.id); XCTAssertEqual(ids.count, Set(ids).count, p.rawValue) } }
    func testEveryPageHasUniqueAcyclicPath() { for p in RelayPage.allCases { XCTAssertEqual(p.path.first,.home);XCTAssertEqual(p.path.last,p);XCTAssertEqual(Set(p.path).count,p.path.count);XCTAssertLessThanOrEqual(p.path.count,4) } }
    func testBreadcrumbsAreUnambiguous() { XCTAssertEqual(RelayPage.stackOptions.breadcrumb,"Home › Context › Context Stack › Stack options") }
    func testNoEmptyDisplayLabels() { for p in RelayPage.allCases { XCTAssertFalse(p.title.isEmpty); for i in RelayHierarchy.items(on:p) { XCTAssertFalse(i.title.isEmpty);XCTAssertFalse(i.id.isEmpty) } } }
    func testContextOwnsCaptureStackAndScreenshots() { XCTAssertEqual(RelayHierarchy.items(on:.context),[.page(.capture),.page(.stack),.page(.screenshots)]) }
    func testChatsOwnsPinsAndDestinations() { XCTAssertEqual(RelayPage.pins.parent,.chats);XCTAssertEqual(RelayPage.destinations.parent,.chats) }
    func testWorkspaceOwnsProjectAndApps() { XCTAssertEqual(RelayPage.projects.parent,.workspace);XCTAssertEqual(RelayPage.appControls.parent,.workspace);XCTAssertEqual(RelayPage.checkpoints.parent,.workspace) }
    func testCaptureCommandsDoNotContainPromptGeneration() { for item in RelayHierarchy.items(on:.capture) { if case .command(.prompt) = item { XCTFail("Prompt under capture") } } }
    func testScreenshotsOptionsHaveAllFiveTools() { XCTAssertEqual(RelayHierarchy.items(on:.screenshotOptions).count,5) }
    func testSettingsDontAppearOnHomeAsCommands() { XCTAssertEqual(RelayPage.connections.parent,.settings);XCTAssertEqual(RelayPage.layout.parent,.settings) }
    func testStaticPagesNeverHaveMoreThanFiveItems() { for p in RelayPage.allCases { XCTAssertLessThanOrEqual(RelayHierarchy.items(on:p).count,5) } }
    func testNavigationStartsHome() { XCTAssertEqual(RelayNavigation().page,.home) }
    func testHomeHasNoParent() { XCTAssertNil(RelayNavigation().backDestination) }
    func testOpenNestedPageUsesCanonicalParent() { var n=RelayNavigation();n.open(.pins);XCTAssertEqual(n.backDestination,.chats) }
    func testBackReturnsOneLevel() { var n=RelayNavigation();n.open(.buildPrompts);n.back();XCTAssertEqual(n.page,.promptLibrary);n.back();XCTAssertEqual(n.page,.prompting);n.back();XCTAssertEqual(n.page,.home) }
    func testBackAtHomeIsSafe() { var n=RelayNavigation();n.back();XCTAssertEqual(n.page,.home) }
    func testHomeFromAnyPage() { for p in RelayPage.allCases { var n=RelayNavigation();n.open(p);n.home();XCTAssertEqual(n.page,.home);XCTAssertNil(n.screenshotReturn) } }
    func testOldNavigationTicketRejected() { var n=RelayNavigation();let t=n.generation;n.open(.context);XCTAssertFalse(n.accepts(t)) }
    func testCurrentTicketAccepted() { let n=RelayNavigation();XCTAssertTrue(n.accepts(n.generation)) }
    func testSamePageExplicitNavigationRetiresOldTicket() { var n=RelayNavigation();let t=n.generation;n.home();XCTAssertFalse(n.accepts(t)) }
    func testOrdinaryReadingDoesNotRetireTicket() { let n=RelayNavigation();let t=n.generation;_ = n.page;_ = n.backDestination;XCTAssertTrue(n.accepts(t)) }
    func testScreenshotTemporarilyInterruptsDraft() { var n=RelayNavigation();n.open(.draft);n.screenshotArrived(autoOpen:true);XCTAssertEqual(n.page,.screenshots);XCTAssertEqual(n.backDestination,.draft);n.back();XCTAssertEqual(n.page,.draft) }
    func testBurstOfScreenshotsKeepsOriginalReturn() { var n=RelayNavigation();n.open(.buildPrompts);for _ in 0..<20 { n.screenshotArrived(autoOpen:true) };n.back();XCTAssertEqual(n.page,.buildPrompts) }
    func testScreenshotAutoOffDoesNotNavigateOrRetireTicket() { var n=RelayNavigation();n.open(.stack);let t=n.generation;n.screenshotArrived(autoOpen:false);XCTAssertEqual(n.page,.stack);XCTAssertTrue(n.accepts(t)) }
    func testManualScreenshotsReturnsToContext() { var n=RelayNavigation();n.open(.screenshots);n.back();XCTAssertEqual(n.page,.context) }
    func testScreenshotArrivalRetiresPriorControls() { var n=RelayNavigation();let t=n.generation;n.screenshotArrived(autoOpen:true);XCTAssertFalse(n.accepts(t)) }
    func testScreenshotOptionsBackRestoresViewerAndThenInterruptedPage() { var n=RelayNavigation();n.open(.stackClips);n.screenshotArrived(autoOpen:true);n.open(.screenshotOptions);n.back();XCTAssertEqual(n.page,.screenshots);n.back();XCTAssertEqual(n.page,.stackClips) }
    func testExplicitHomeDismissesScreenshotReturn() { var n=RelayNavigation();n.open(.draft);n.screenshotArrived(autoOpen:true);n.home();n.open(.screenshots);n.back();XCTAssertEqual(n.page,.context) }
    func testOtherFamilyDismissesScreenshotReturn() { var n=RelayNavigation();n.screenshotArrived(autoOpen:true);n.open(.chats);XCTAssertNil(n.screenshotReturn) }
    func testExternalAppChangePreservesOrdinaryGroup() { for p in RelayPage.allCases where p != .screenshots && p != .screenshotOptions { var n=RelayNavigation();n.open(p);let t=n.generation;n.externalContextChanged(appAware:true);XCTAssertEqual(n.page,p);XCTAssertTrue(n.accepts(t)) } }
    func testExternalChangeDismissesScreenshotToInterruptedPage() { var n=RelayNavigation();n.open(.appControls);n.screenshotArrived(autoOpen:true);n.externalContextChanged(appAware:true);XCTAssertEqual(n.page,.appControls) }
    func testAppAwareOffDoesNotDismissViewer() { var n=RelayNavigation();n.screenshotArrived(autoOpen:true);n.externalContextChanged(appAware:false);XCTAssertEqual(n.page,.screenshots) }
    func testUnrelatedAppLeavesPinsAtChats() { var n=RelayNavigation();n.open(.pins);n.leaveUnavailablePins();XCTAssertEqual(n.page,.chats) }
    func testUnavailablePinsDoNotDisturbPrompting() { var n=RelayNavigation();n.open(.prompting);n.leaveUnavailablePins();XCTAssertEqual(n.page,.prompting) }
    func testUnavailablePinReturnIsDowngraded() { var n=RelayNavigation();n.open(.pins);n.screenshotArrived(autoOpen:true);n.leaveUnavailablePins();n.back();XCTAssertEqual(n.page,.chats) }
    func testStackSubpagesStayInStackFamily() { var n=RelayNavigation();for p in [RelayPage.stack,.stackClips,.stackOptions] { n.open(p);XCTAssertTrue(n.isStackPage) };n.open(.context);XCTAssertFalse(n.isStackPage) }
    func testProjectPageCounts() { XCTAssertEqual(RelayHierarchy.projectPageCount(0),1);XCTAssertEqual(RelayHierarchy.projectPageCount(4),1);XCTAssertEqual(RelayHierarchy.projectPageCount(5),2);XCTAssertEqual(RelayHierarchy.projectPageCount(100),25) }
    func testProjectRangesCoverAllHundredExactlyOnce() { let indices=(0..<25).flatMap { Array(RelayHierarchy.projectRange(count:100,page:$0)) };XCTAssertEqual(indices,Array(0..<100)) }
    func testNegativeProjectInputsAreSafe() { XCTAssertEqual(RelayHierarchy.projectRange(count:-4,page:-1),0..<0) }
    func testProjectPageClampsAfterRemoval() { var n=RelayNavigation();n.setProjectPage(24,count:100);n.setProjectPage(n.projectPage,count:2);XCTAssertEqual(n.projectPage,0) }
    func testProjectPaginationRetiresOldControls() { var n=RelayNavigation();n.open(.projects);let t=n.generation;n.setProjectPage(1,count:8);XCTAssertFalse(n.accepts(t)) }
    func testProjectPaginationSurvivesVisitingSibling() { var n=RelayNavigation();n.open(.projects);n.setProjectPage(3,count:20);n.open(.projectOptions);n.back();XCTAssertEqual(n.projectPage,3) }
    func testNativeBackCancelsConfirmationFirst() { XCTAssertEqual(RelayHierarchy.nativeBack(pending:true,showingOpenMenu:true),.cancelConfirmation) }
    func testNativeBackShowsRootsBeforeLeaving() { XCTAssertEqual(RelayHierarchy.nativeBack(pending:false,showingOpenMenu:true),.menuRoots) }
    func testNativeBackLeavesRootPage() { XCTAssertEqual(RelayHierarchy.nativeBack(pending:false,showingOpenMenu:false),.parent) }
    func testDeepNavigationAndBackNeverMutateProjectSettings() { let config=AppConfiguration();var n=RelayNavigation();for p in RelayPage.allCases { n.open(p);n.back() };XCTAssertEqual(config.selectedProjectID,"hearth");XCTAssertEqual(config.target,.chatgpt) }
}
