import XCTest
@testable import RelayCore

// Explicit service double. These tests exercise production traversal and action
// policy, NOT a real browser, macOS Accessibility, or physical Touch Bar.
private final class FakeAX: NativeMenuSource {
    typealias Node = Int
    struct Item {
        var text: [NativeAXAttribute:String] = [:]
        var flags: [NativeAXAttribute:Bool] = [.enabled:true]
        var links: [NativeAXAttribute:Int] = [:]
        var kids: [Int]? = []
        var frame: NativeRect? = NativeRect(x: 10, y: 10, width: 100, height: 28)
        var actionNames: [String] = ["AXPress"]
    }
    var tree: [Int:Item] = [:]
    var trusted = true
    var limited = false
    var now: Double = 100
    var pid: Int32 = 42
    var hit: Int? = 10
    var succeeds = true
    var reads: [(Int,NativeAXAttribute)] = []
    var childReads: [Int] = []
    var presses: [(Int,String)] = []
    var pointerClicks: [(Double,Double)] = []
    var beforeHit: (() -> Void)?
    var afterPerform: ((Int,String) -> Void)?
    var begin: (() -> Void)?
    func add(_ id: Int, _ role: String, _ label: String = "", children: [Int] = []) {
        tree[id] = Item(text: [.role:role,.title:label], kids:children)
        for child in children { tree[child, default:Item()].links[.parent] = id }
    }
    func fixParents() {
        for (id,item) in tree { for c in item.kids ?? [] { tree[c]?.links[.parent] = id } }
    }
    init(open: Bool = true) {
        add(0,"AXApplication"); tree[0]?.links = [.focusedWindow:1,.focusedElement:7]
        add(1,"AXWindow",children:[3]); tree[1]?.frame = NativeRect(x:0,y:0,width:1200,height:800)
        add(3,"AXWebArea",children:open ? [4,7,9] : [4,7])
        tree[3]?.text[.url] = "https://docs.google.com/spreadsheets/d/WORKBOOK_1/edit#gid=0"
        tree[3]?.frame = NativeRect(x:0,y:0,width:1200,height:800)
        add(4,"AXMenuBar",children:[5,6])
        add(5,"AXMenuItem","File")
        add(6,"AXMenuItem","My scripts")
        add(7,"AXTable",children:[8]); add(8,"AXCell","PRIVATE CELL CONTENT")
        if open {
            add(9,"AXMenu",children:[10,11])
            add(10,"AXMenuItem","Refresh preview")
            add(11,"AXMenuItem","Export")
        }
        fixParents()
    }
    func beginRead() { begin?() }
    func frontmostPID() -> Int32 { pid }
    func application(_ pid: Int32) -> Int { 0 }
    func element(_ node: Int, _ attribute: NativeAXAttribute) -> Int? { reads.append((node,attribute)); return tree[node]?.links[attribute] }
    func string(_ node: Int, _ attribute: NativeAXAttribute) -> String? { reads.append((node,attribute)); return tree[node]?.text[attribute] }
    func flag(_ node: Int, _ attribute: NativeAXAttribute) -> Bool? { reads.append((node,attribute)); return tree[node]?.flags[attribute] }
    func children(_ node: Int) -> [Int]? { childReads.append(node); return tree[node]?.kids }
    func rect(_ node: Int) -> NativeRect? { tree[node]?.frame }
    func actions(_ node: Int) -> [String] { tree[node]?.actionNames ?? [] }
    func hitTest(_ app: Int, x: Double, y: Double) -> Int? { beforeHit?(); return hit }
    func pointerClick(x: Double, y: Double) -> Bool {
        pointerClicks.append((x,y))
        if let hit { afterPerform?(hit,"PointerClick") }
        return succeeds
    }
    func perform(_ node: Int, action: String) -> Bool {
        presses.append((node,action)); afterPerform?(node,action); return succeeds
    }
}
final class NativeMenuTests: XCTestCase {
    private func scan(_ s: FakeAX) -> NativeMenuSnapshot<Int> { NativeMenuEngine(source:s).scan(pid:42,bundle:"com.google.Chrome") }
    private func action(_ s: FakeAX, _ expected: NativeMenuSnapshot<Int>) -> NativeDispatchResult {
        NativeMenuEngine(source:s).request(expected.openItems.first!, expected:expected)
    }
    private func refused(_ result: NativeDispatchResult, file: StaticString = #filePath, line: UInt = #line) {
        if case .refused = result {} else { XCTFail("Expected refusal, got \(result)",file:file,line:line) }
    }
    func testRealSheetsURLFormsAndIdentity() {
        for url in ["https://docs.google.com/spreadsheets/d/abc_DEF-123/edit#gid=0", "https://docs.google.com/spreadsheets/u/1/d/ABCD/edit?usp=sharing#gid=12"] {
            XCTAssertEqual(NativeMenuPolicy.site(url), .sheets)
        }
    }
    func testUntrustedURLFormsFail() {
        for url in ["http://docs.google.com/spreadsheets/d/a/edit", "https://docs.google.com.evil.test/spreadsheets/d/a/edit", "https://docs.google.com@evil.test/spreadsheets/d/a/edit", "https://user@docs.google.com/spreadsheets/d/a/edit", "https://docs.google.com:444/spreadsheets/d/a/edit", "https://docs.google.com/spreadsheets/d/e/a/pubhtml", "https://docs.google.com/spreadsheets/d/a/preview", "https://docs.google.com/spreadsheets/d/a%2fb/edit", "https://docs.google.com//spreadsheets/d/a/edit", "file:///spreadsheets/d/a/edit", "https://docs.google.com/spreadsheets/d/a/edit/extra"] {
            XCTAssertEqual(NativeMenuPolicy.site(url), .other, url)
        }
    }
    func testAssistantSitesWithoutReadingTheirContent() {
        for (url,site) in [("https://chatgpt.com/c/test",NativeSite.chatgpt),("https://claude.ai/chat/test",.claude)] {
            let s = FakeAX(); s.tree[3]?.text[.url] = url
            let r = scan(s); XCTAssertEqual(r.route?.site,site); XCTAssertTrue(r.roots.isEmpty)
            XCTAssertFalse(s.childReads.contains(3))
        }
    }
    func testMenuDiscoveryIsReadOnlyAndCustomMenusFirst() {
        let s = FakeAX(); let r = scan(s)
        XCTAssertTrue(r.ready); XCTAssertEqual(r.roots.map(\.label),["My scripts","File"])
        XCTAssertEqual(r.openItems.map(\.label),["Refresh preview","Export"])
        XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testNoGridChildrenOrCellStringsRead() {
        let s = FakeAX(); _ = scan(s)
        XCTAssertFalse(s.childReads.contains(7)); XCTAssertFalse(s.reads.contains { $0.0 == 8 })
        XCTAssertFalse(s.reads.contains { $0.0 == 7 && ($0.1 == .title || $0.1 == .description) })
    }
    func testAllContentRolesArePruned() {
        for role in NativeMenuPolicy.contentRoles {
            let s = FakeAX(); s.tree[7]?.text[.role] = role; _ = scan(s)
            XCTAssertFalse(s.childReads.contains(7),role); XCTAssertFalse(s.reads.contains { $0.0 == 8 },role)
        }
    }
    func testScrollAreaGridPruned() {
        let s = FakeAX(); s.tree[7]?.text[.role] = "AXScrollArea"; _ = scan(s)
        XCTAssertFalse(s.childReads.contains(7))
    }
    func testNoPermissionDoesNotInspect() {
        let s = FakeAX(); s.trusted = false; XCTAssertFalse(scan(s).ready)
        XCTAssertTrue(s.reads.isEmpty); XCTAssertTrue(s.childReads.isEmpty)
    }
    func testUnsupportedAppDoesNotInspect() {
        let s = FakeAX(); let r = NativeMenuEngine(source:s).scan(pid:42,bundle:"not.a.browser")
        XCTAssertFalse(r.ready); XCTAssertTrue(s.reads.isEmpty)
    }
    func testBackgroundAppDoesNotInspect() {
        let s = FakeAX(); s.pid = 99; XCTAssertFalse(scan(s).ready); XCTAssertTrue(s.reads.isEmpty)
    }
    func testMissingURLDoesNotGuessFromTitle() {
        let s = FakeAX(); s.tree[3]?.text[.url] = nil; s.tree[1]?.text[.title] = "Google Sheets Budget"
        XCTAssertNil(scan(s).route)
    }
    func testTwoWebAreasFailClosed() {
        let s = FakeAX(); s.add(99,"AXWebArea"); let url = s.tree[3]?.text[.url]; s.tree[99]?.text[.url] = url; s.tree[1]?.kids?.append(99)
        XCTAssertNil(scan(s).route)
    }
    func testIframeNeverContributesActions() {
        let s = FakeAX(); s.add(90,"AXWebArea",children:[91]); s.add(91,"AXMenuBar",children:[92]); s.add(92,"AXMenuItem","Injected iframe")
        s.tree[3]?.kids?.append(90); s.fixParents()
        XCTAssertEqual(scan(s).roots.count,2); XCTAssertFalse(s.childReads.contains(90))
    }
    func testHiddenMenuNotListed() {
        let s = FakeAX(); s.tree[9]?.flags[.hidden] = true; XCTAssertTrue(scan(s).openItems.isEmpty)
    }
    func testZeroSizedMenuNotListed() {
        let s = FakeAX(); s.tree[9]?.frame = NativeRect(x:0,y:0,width:0,height:0); XCTAssertTrue(scan(s).openItems.isEmpty)
    }
    func testDisabledAndMissingEnabledRemainDisabled() {
        let s = FakeAX(); s.tree[10]?.flags[.enabled] = false; s.tree[11]?.flags[.enabled] = nil
        let r = scan(s); XCTAssertEqual(r.openItems.count,2); XCTAssertTrue(r.openItems.allSatisfy { !$0.enabled })
    }
    func testMenuTriggerMayOmitEnabledWhenActionIsExposed() {
        let s = FakeAX(open:false); s.tree[6]?.flags[.enabled] = nil; s.hit = 6
        let r = scan(s); guard let menu = r.roots.first(where: { $0.label == "My scripts" }) else { return XCTFail() }
        XCTAssertTrue(menu.isMenu); XCTAssertTrue(menu.enabled)
        XCTAssertEqual(NativeMenuEngine(source:s).request(menu, expected:r), .requested)
        XCTAssertEqual(s.pointerClicks.count,1); XCTAssertTrue(s.presses.isEmpty)
    }
    func testExpansionScanFindsMenuItemsUnderGenericPopupWrapper() {
        let s = FakeAX(open:false)
        s.add(9,"AXGroup",children:[10,11]); s.add(10,"AXMenuItem","Tool one"); s.add(11,"AXMenuItem","Tool two")
        s.tree[3]?.kids?.append(9); s.fixParents()
        XCTAssertTrue(scan(s).openItems.isEmpty)
        let expanded = NativeMenuEngine(source:s).scan(pid:42,bundle:"com.google.Chrome",expandingMenu:true)
        XCTAssertEqual(expanded.openItems.map(\.label), ["Tool one","Tool two"])
        s.hit=10
        XCTAssertEqual(NativeMenuEngine(source:s).request(expanded.openItems[0],expected:expanded),.requested)
        XCTAssertEqual(s.pointerClicks.count,1)
    }
    func testExpansionScanTraversesListPopupButNormalScanPrunesIt() {
        let s = FakeAX(open:false)
        s.add(9,"AXList",children:[10]); s.add(10,"AXMenuItem","Lazy tool")
        s.tree[3]?.kids?.append(9); s.fixParents()
        XCTAssertTrue(scan(s).openItems.isEmpty)
        let expanded = NativeMenuEngine(source:s).scan(pid:42,bundle:"com.google.Chrome",expandingMenu:true)
        XCTAssertEqual(expanded.openItems.map(\.label), ["Lazy tool"])
    }
    func testLiveSizedSheetTreeCanReachLazyMenuBeyondOldNodeBound() {
        let s = FakeAX(open:false)
        var fillers: [Int] = []
        for id in 1000..<2200 { s.add(id,"AXGroup"); fillers.append(id) }
        s.add(9,"AXGroup",children:[10,11]); s.add(10,"AXMenuItem","Hearth tool one"); s.add(11,"AXMenuItem","Hearth tool two")
        s.tree[3]?.kids = [4] + fillers + [9,7]
        s.fixParents()
        let expanded = NativeMenuEngine(source:s).scan(pid:42,bundle:"com.google.Chrome",expandingMenu:true)
        XCTAssertTrue(expanded.ready)
        XCTAssertEqual(expanded.failure,.none)
        XCTAssertEqual(expanded.openItems.map(\.label), ["Hearth tool one","Hearth tool two"])
        XCTAssertGreaterThan(expanded.nodesVisited, 900)
    }
    func testUnsupportedActionCannotRun() {
        let s = FakeAX(); s.tree[10]?.actionNames = []
        let r = scan(s); refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testNativeDialogBlocksAllActions() {
        let s = FakeAX(); s.add(30,"AXSheet"); s.tree[1]?.kids?.append(30)
        XCTAssertFalse(scan(s).ready)
    }
    func testSheetDialogBlocksAllActions() {
        let s = FakeAX(); s.add(30,"AXGroup"); s.tree[30]?.text[.subrole] = "AXDialog"; s.tree[3]?.kids?.append(30)
        let r=scan(s); XCTAssertTrue(r.roots.isEmpty); XCTAssertTrue(r.openItems.isEmpty)
    }
    func testOversizedOrFailedChildrenFailClosed() {
        let s = FakeAX(); s.tree[4]?.kids = nil; let r=scan(s)
        XCTAssertFalse(r.ready); XCTAssertTrue(r.roots.isEmpty)
    }
    func testSourceDeadlineFailsClosed() {
        let s = FakeAX(); s.limited = true; XCTAssertFalse(scan(s).ready)
    }
    func testCyclicTreeTerminates() {
        let s = FakeAX(); s.tree[4]?.kids?.append(3); let r=scan(s)
        XCTAssertLessThan(r.nodesVisited,40); XCTAssertTrue(r.ready)
    }
    func testTraversalDepthBoundFailsClosed() {
        let s = FakeAX(); s.tree[3]?.kids?.append(100)
        for n in 100...130 { s.add(n,"AXGroup",children:n == 130 ? [] : [n+1]) }
        XCTAssertFalse(scan(s).ready)
    }
    func testMenuWithNoFunctionsCreatesNoFakeActions() {
        let s=FakeAX(open:false); let r=scan(s)
        XCTAssertEqual(r.roots.count,2); XCTAssertTrue(r.openItems.isEmpty); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testNestedSubmenuUsesShowMenuWhenOffered() {
        let s=FakeAX(); s.tree[10]?.actionNames=["AXPress","AXShowMenu"]
        let r=scan(s); XCTAssertTrue(r.openItems[0].isMenu)
        XCTAssertEqual(action(s,r),.requested); XCTAssertEqual(s.pointerClicks.count,1); XCTAssertTrue(s.presses.isEmpty)
    }
    func testExpandedAttributeMarksSubmenu() {
        let s=FakeAX(); s.tree[10]?.flags[.expanded]=false
        XCTAssertTrue(scan(s).openItems[0].isMenu)
    }
    func testSubmenuChildrenListedBeforeParentItems() {
        let s=FakeAX(); s.add(20,"AXMenu",children:[21]); s.add(21,"AXMenuItem","Nested action"); s.tree[11]?.kids=[20]; s.fixParents()
        let r=scan(s); XCTAssertEqual(r.openItems.first?.label,"Nested action")
        XCTAssertTrue(r.openItems.contains { $0.label == "Export" && $0.isMenu })
    }
    func testSingleVerifiedNativeAction() {
        let s=FakeAX(); let r=scan(s)
        XCTAssertEqual(action(s,r),.requested); XCTAssertEqual(s.pointerClicks.count,1)
        XCTAssertTrue(s.presses.isEmpty)
    }
    func testSafariKeepsAccessibilityActionInsteadOfPointerClick() {
        let s=FakeAX(); let r=NativeMenuEngine(source:s).scan(pid:42,bundle:"com.apple.Safari")
        XCTAssertEqual(NativeMenuEngine(source:s).request(r.openItems[0], expected:r), .requested)
        XCTAssertEqual(s.presses.count,1); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testHitTestChildOfTargetAccepted() {
        let s=FakeAX(); s.add(40,"AXStaticText"); s.tree[40]?.links[.parent]=10; s.hit=40
        let r=scan(s); XCTAssertEqual(action(s,r),.requested)
    }
    func testCoveredTargetRefused() {
        let s=FakeAX(); let r=scan(s); s.hit=7
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testMissingHitTestRefused() {
        let s=FakeAX(); let r=scan(s); s.hit=nil
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testChangedWorkbookAndWorksheetRefused() {
        for change in ["https://docs.google.com/spreadsheets/d/OTHER/edit#gid=0", "https://docs.google.com/spreadsheets/d/WORKBOOK_1/edit#gid=9"] {
            let s=FakeAX(); let r=scan(s); s.tree[3]?.text[.url]=change
            refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
        }
    }
    func testChangedWindowRefused() {
        let s=FakeAX(); let r=scan(s); s.add(30,"AXWindow",children:[3]); s.tree[0]?.links[.focusedWindow]=30
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testChangedTabEvenSameURLRefused() {
        let s=FakeAX(); let r=scan(s); s.tree[30]=s.tree[3]; s.tree[1]?.kids=[30]
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testChangedSelectionFocusRefused() {
        let s=FakeAX(); let r=scan(s); s.tree[0]?.links[.focusedElement]=8
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testStaleAndFutureSnapshotRefused() {
        for delta in [3.0,-1.0] {
            let s=FakeAX(); let r=scan(s); s.now += delta
            refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
        }
    }
    func testChangedTargetRefused() {
        let s=FakeAX(); let r=scan(s); s.tree[10]?.text[.title]="Delete all data"
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testTargetMoveRefused() {
        let s=FakeAX(); let r=scan(s); s.tree[10]?.frame=NativeRect(x:50,y:80,width:100,height:28)
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testLastMomentForegroundChangeRefused() {
        let s=FakeAX(); let r=scan(s); s.beforeHit = { s.pid=99 }
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testLastMomentPermissionRevocationRefused() {
        let s=FakeAX(); let r=scan(s); s.beforeHit = { s.trusted=false }
        refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testUncertainVerifiedClickNeverRetriesOrFallsBack() {
        let s=FakeAX(); s.succeeds=false; let r=scan(s)
        XCTAssertEqual(action(s,r),.uncertain); XCTAssertEqual(s.pointerClicks.count,1); XCTAssertTrue(s.presses.isEmpty)
    }
    func testDuplicateCaptionsKeepExactNodeBinding() {
        let s=FakeAX(); s.tree[11]?.text[.title]="Refresh preview"; let r=scan(s)
        XCTAssertEqual(r.openItems.count,2); XCTAssertNotEqual(r.openItems[0].node,r.openItems[1].node)
        s.hit=11; refused(action(s,r)); XCTAssertTrue(s.presses.isEmpty); XCTAssertTrue(s.pointerClicks.isEmpty)
    }
    func testLabelsRejectControlCharacters() {
        for label in ["", "  ", "Run\nDelete", "x\u{202E}abc",String(repeating:"x",count:257)] { XCTAssertNil(NativeMenuPolicy.label(label)) }
        XCTAssertEqual(NativeMenuPolicy.label("  Refresh  "),"Refresh")
    }
    func testGeometryValidation() {
        XCTAssertFalse(NativeRect(x:.nan,y:0,width:10,height:10).valid)
        XCTAssertFalse(NativeRect(x:0,y:0,width:-1,height:10).valid)
        XCTAssertTrue(NativeRect(x:-100,y:-200,width:80,height:20).valid)
    }
    func testAllPagesReachable() {
        XCTAssertEqual(NativeMenuPolicy.pageCount(0),1); XCTAssertEqual(NativeMenuPolicy.pageCount(4),1)
        XCTAssertEqual(NativeMenuPolicy.pageCount(5),2); XCTAssertEqual(NativeMenuPolicy.pageCount(121),31)
    }
    func testLeafNeedsConfirmationAndSingleDispatch() {
        var g=NativeTapGate()
        guard case .confirm = g.tap(index:0,revision:1,now:100,isMenu:false,ask:true) else { return XCTFail() }
        XCTAssertNil(g.executing)
        guard case .execute(let req) = g.confirm(revision:1,now:101) else { return XCTFail() }
        XCTAssertEqual(g.confirm(revision:1,now:101),.ignore)
        XCTAssertEqual(g.tap(index:0,revision:1,now:101,isMenu:false,ask:false),.ignore)
        g.finish(req.id); XCTAssertNil(g.executing)
    }
    func testMenuAndExplicitOneTapSkipConfirmation() {
        for (menu,ask) in [(true,true),(false,false)] {
            var g=NativeTapGate(); guard case .execute = g.tap(index:0,revision:1,now:100,isMenu:menu,ask:ask) else { return XCTFail() }
            XCTAssertNil(g.pending)
        }
    }
    func testConfirmationExpiresOrInvalidates() {
        for (rev,clock) in [(2,101.0),(1,108),(1,99),(1,Double.nan)] {
            var g=NativeTapGate(); _=g.tap(index:0,revision:1,now:100,isMenu:false,ask:true)
            XCTAssertEqual(g.confirm(revision:rev,now:clock),.ignore); XCTAssertNil(g.executing)
        }
    }
    func testPauseScreenshotOrHideCancelsConfirmation() {
        var g=NativeTapGate(); _=g.tap(index:0,revision:1,now:100,isMenu:false,ask:true); g.cancel()
        XCTAssertEqual(g.confirm(revision:1,now:101),.ignore)
    }
    func testOldCompletionCannotUnlockNewRequest() {
        var g=NativeTapGate()
        guard case .execute(let old)=g.tap(index:0,revision:1,now:100,isMenu:true,ask:true) else {return XCTFail()}
        g.cancel()
        guard case .execute(let new)=g.tap(index:1,revision:2,now:101,isMenu:true,ask:true) else {return XCTFail()}
        g.finish(old.id); XCTAssertEqual(g.executing,new)
    }
    func testHeartbeatDoesNotChangeControlBinding() {
        let s=FakeAX(); let a=scan(s); s.now=101; let b=scan(s)
        XCTAssertTrue(a.sameContent(as:b)); XCTAssertNotEqual(a.sampledAt,b.sampledAt)
    }
    func testLeanScanFormattingToolbarPrunedBeforeChildren() {
        let s=FakeAX(); s.add(90,"AXToolbar",children:[91]); s.add(91,"AXGroup"); s.tree[90]?.kids=nil
        s.tree[3]?.kids?.insert(90,at:0)
        let r=scan(s); XCTAssertTrue(r.ready); XCTAssertEqual(r.prunedChromeNodes,1)
        XCTAssertFalse(s.childReads.contains(90))
    }
    func testLeanScanToolbarWithinMenuIsStillTraversed() {
        let s=FakeAX(); s.add(90,"AXToolbar",children:[91]); s.add(91,"AXMenuItem","Nested toolbar item")
        s.tree[9]?.kids?.append(90); s.fixParents()
        let r=scan(s); XCTAssertTrue(r.openItems.contains { $0.label == "Nested toolbar item" })
        XCTAssertTrue(s.childReads.contains(90))
    }
    func testLeanScanNoContentLabelReadWhilePruning() {
        let s=FakeAX(); s.add(90,"AXLink","PRIVATE LINK"); s.tree[3]?.kids?.append(90)
        XCTAssertTrue(scan(s).ready)
        XCTAssertFalse(s.childReads.contains(90))
        XCTAssertFalse(s.reads.contains { $0.0 == 90 && ($0.1 == .title || $0.1 == .description) })
    }
    func testLeanScanDepthFailureIsExplicit() {
        let s=FakeAX(); s.tree[3]?.kids?.append(100)
        for n in 100...130 { s.add(n,"AXGroup",children:n == 130 ? [] : [n+1]) }
        let r=scan(s); XCTAssertEqual(r.failure,.depth); XCTAssertTrue(r.status.contains("depth"))
        XCTAssertEqual(r.scanPhase,"Sheet menu discovery"); XCTAssertFalse(r.ready)
    }
    func testLeanScanUnreadableMenuFailsExplicitlyWithoutPartialActions() {
        let s=FakeAX(); s.tree[9]?.kids=nil
        let r=scan(s); XCTAssertEqual(r.failure,.readFailed); XCTAssertFalse(r.ready)
        XCTAssertGreaterThan(r.candidatesSeen,0); XCTAssertTrue(r.roots.isEmpty); XCTAssertTrue(r.openItems.isEmpty)
    }
    func testLeanScanMetricsHeartbeatDoesNotInvalidateButtons() {
        let s=FakeAX(); let a=scan(s); var b=a
        b.readMetrics.queries=123; b.readMetrics.milliseconds=456; b.prunedContentNodes=99
        XCTAssertTrue(a.sameContent(as:b))
    }
    func testLeanScanHardNodeBoundRetained() {
        let s=FakeAX(); s.tree[3]?.kids?.append(1000)
        for n in 1000..<2700 { let k=3*(n-1000)+1001; s.add(n,"AXGroup",children:(0..<3).map { k+$0 }.filter { $0<2700 }) }
        let r=scan(s); XCTAssertEqual(r.failure,.nodes); XCTAssertFalse(r.ready)
        XCTAssertTrue(r.roots.isEmpty); XCTAssertTrue(r.openItems.isEmpty)
    }
}
