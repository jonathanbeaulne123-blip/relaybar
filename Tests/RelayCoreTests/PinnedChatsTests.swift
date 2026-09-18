import XCTest
@testable import RelayCore

final class PinnedChatsTests: XCTestCase {
    let gpt = "https://chatgpt.com/c/12345678-abcd-1234-abcd-123456789abc"
    let claude = "https://claude.ai/chat/12345678-abcd-1234-abcd-123456789abc"
    func chat(_ id: String = "a", _ title: String = "Hearth work", url: String? = nil, enabled: Bool = true, selected: Bool = false) -> PinNode {
        PinNode(token: id, role: "AXLink", label: title, url: url ?? gpt, enabled: enabled, pressable: true, selected: selected)
    }
    func section(_ children: [PinNode], label: String = "Pinned", token: String = "section") -> PinNode {
        PinNode(token: token, label: label, children: children)
    }
    func sidebar(_ children: [PinNode]) -> PinNode { PinNode(token: "sidebar", label: "Sidebar", children: children) }
    func inv(_ children: [PinNode], provider: PinProvider = .chatgpt, native: Bool = false) -> PinInventory {
        PinnedChatPolicy.inventory(sidebar: sidebar(children), provider: provider, native: native)
    }
    func testGPTSection() { XCTAssertEqual(inv([section([chat()])]).chats.map(\.title), ["Hearth work"]) }
    func testClaudeStarred() { XCTAssertEqual(inv([section([chat(url: claude)], label: "Starred")], provider: .claude).chats.count, 1) }
    func testPinHeadingFollowedByList() {
        let h = PinNode(token: "heading", role: "AXHeading", label: "Pinned chats")
        let list = PinNode(token: "list", role: "AXList", children: [chat()])
        XCTAssertEqual(inv([h, list]).chats.count, 1)
    }
    func testPinStaticHeadingFollowedByList() {
        XCTAssertEqual(inv([PinNode(token: "h", role: "AXStaticText", label: "Pinned"), chat()]).chats.count, 1)
    }
    func testRecentHeadingStopsPinSection() {
        let recents = PinNode(token: "recents", role: "AXHeading", label: "Recents")
        XCTAssertEqual(inv([PinNode(token: "h", role: "AXHeading", label: "Pinned"), chat(), recents, chat("b", "Recent", url: gpt + "-b")]).chats.count, 1)
    }
    func testSectionContainerDoesNotPinFollowingUnmarkedSiblings() {
        XCTAssertEqual(inv([section([chat()]), chat("b", "Recent", url: gpt + "-b")]).chats.count, 1)
    }
    func testUnknownHeadingStopsPinSection() {
        XCTAssertEqual(inv([PinNode(token: "h", role: "AXHeading", label: "Pinned"), chat(), PinNode(token: "other", role: "AXHeading", label: "Archive"), chat("b", url: gpt + "-b")]).chats.count, 1)
    }
    func testNestedRecentGroupNotPinned() {
        let recent = PinNode(token: "recent", children: [PinNode(token: "rh", role: "AXHeading", label: "Recents"), chat("b", url: gpt + "-b")])
        XCTAssertEqual(inv([section([chat()]), recent]).chats.count, 1)
    }
    func testNoPinsDoesNotUseRecent() { XCTAssertTrue(inv([chat()]).chats.isEmpty) }
    func testNoPinsIsUnknownNotEmptyAccountClaim() { XCTAssertFalse(inv([chat()]).recognizedSection) }
    func testEmptySectionRecognized() { XCTAssertTrue(inv([section([])]).recognizedSection) }
    func testProjectLinksNotChats() {
        XCTAssertTrue(inv([section([chat(url: "https://claude.ai/project/12345678-project")], label: "Starred")], provider: .claude).chats.isEmpty)
    }
    func testSharedLinkNotPrivateChat() { XCTAssertNil(PinProvider.chatgpt.conversationURL("https://chatgpt.com/share/12345678-abcd")) }
    func testClaudePublicLinkNotPrivateChat() { XCTAssertNil(PinProvider.claude.conversationURL("https://claude.ai/share/12345678-abcd")) }
    func testHTTPSRequired() { XCTAssertNil(PinProvider.site("http://chatgpt.com/c/12345678")) }
    func testHostSuffixRejected() { XCTAssertNil(PinProvider.site("https://chatgpt.com.attacker.test/c/12345678")) }
    func testCredentialsRejected() { XCTAssertNil(PinProvider.site("https://user:password@chatgpt.com/c/12345678")) }
    func testNonStandardPortRejected() { XCTAssertNil(PinProvider.site("https://claude.ai:444/chat/12345678")) }
    func testStandardPortNormalized() { XCTAssertEqual(PinProvider.claude.conversationURL("https://claude.ai:443/chat/12345678"), "https://claude.ai/chat/12345678") }
    func testJavascriptRejected() { XCTAssertNil(PinProvider.chatgpt.conversationURL("javascript:alert(1)")) }
    func testFileRejected() { XCTAssertNil(PinProvider.site("file:///tmp/chatgpt.com")) }
    func testEncodedPathRejected() { XCTAssertNil(PinProvider.chatgpt.conversationURL("https://chatgpt.com/c/%31%32%33%34%35%36%37%38")) }
    func testWrongProviderRejected() { XCTAssertNil(PinProvider.chatgpt.conversationURL(claude)) }
    func testCustomGPTConversationAccepted() { XCTAssertEqual(PinProvider.chatgpt.conversationURL("https://chatgpt.com/g/g-example/c/12345678"), "https://chatgpt.com/g/g-example/c/12345678") }
    func testQueryAndFragmentRemovedFromIdentity() { XCTAssertEqual(PinProvider.chatgpt.conversationURL(gpt + "?private=value#secret"), gpt) }
    func testLegacyOfficialHostAccepted() { XCTAssertEqual(PinProvider.site("https://chat.openai.com/c/12345678"), .chatgpt) }
    func testShortNonConversationPathRejected() { XCTAssertNil(PinProvider.chatgpt.conversationURL("https://chatgpt.com/c/x")) }
    func testSidebarBoundaryMandatory() {
        let body = PinNode(token: "body", label: "Main content", children: [section([chat()])])
        XCTAssertTrue(PinnedChatPolicy.inventory(sidebar: body, provider: .chatgpt, native: false).chats.isEmpty)
    }
    func testNavigationLandmarkAccepted() { XCTAssertTrue(PinnedChatPolicy.isSidebar(role: "AXGroup", subrole: "AXLandmarkNavigation", label: "", identifier: "")) }
    func testSidebarIdentifierAccepted() { XCTAssertTrue(PinnedChatPolicy.isSidebar(role: "AXGroup", subrole: "", label: "", identifier: "history-sidebar")) }
    func testMessageNamedSidebarNotAccepted() { XCTAssertFalse(PinnedChatPolicy.isSidebar(role: "AXStaticText", subrole: "", label: "Sidebar", identifier: "")) }
    func testHiddenSectionIgnored() {
        var s = section([chat()]); s.hidden = true
        XCTAssertTrue(inv([s]).chats.isEmpty)
    }
    func testHiddenChatIgnored() { var c = chat(); c.hidden = true; XCTAssertTrue(inv([section([c])]).chats.isEmpty) }
    func testDisabledChatVisibleButUnavailable() { XCTAssertFalse(inv([section([chat(enabled: false)])]).chats[0].enabled) }
    func testDisabledAncestorDisablesNavigation() {
        var s = section([chat()]); s.enabled = false
        XCTAssertFalse(inv([s]).chats[0].enabled)
    }
    func testNonPressableLinkIsNotPresentedAsWorking() {
        var c = chat(); c.pressable = false
        XCTAssertTrue(inv([section([c])]).chats.isEmpty)
    }
    func testPinMarkerInSingleConversationRow() {
        let row = PinNode(token: "row", children: [chat(), PinNode(token: "mark", role: "AXImage", label: "Pinned")])
        XCTAssertEqual(inv([row]).chats.first?.evidence, "row-marker")
    }
    func testMarkerWithinLink() {
        var link = chat(); link.children = [PinNode(token: "mark", role: "AXImage", label: "Pinned")]
        XCTAssertEqual(inv([link]).chats.count, 1)
    }
    func testMarkerDoesNotPinMultipleSiblingChats() {
        let row = PinNode(token: "row", children: [chat(), chat("b", url: gpt + "-b"), PinNode(token: "mark", role: "AXImage", label: "Pinned")])
        XCTAssertTrue(inv([row]).chats.isEmpty)
    }
    func testPinActionIsNotPinEvidence() {
        let action = PinNode(token: "action", role: "AXButton", label: "Pin chat", pressable: true)
        XCTAssertTrue(inv([PinNode(token: "row", children: [chat(), action])]).chats.isEmpty)
    }
    func testOverflowNotChatTarget() {
        let action = PinNode(token: "action", role: "AXButton", label: "More options", pressable: true)
        XCTAssertTrue(inv([section([action])], native: true).chats.isEmpty)
    }
    func testDeleteAndUnpinNeverTargets() {
        for title in ["Delete chat", "Unpin chat", "Rename chat", "Share chat"] {
            let action = PinNode(token: title, role: "AXButton", label: title, pressable: true)
            XCTAssertTrue(inv([section([action])], native: true).chats.isEmpty)
        }
    }
    func testComposerNotTraversed() {
        let composer = PinNode(token: "composer", role: "AXTextArea", children: [section([chat()])])
        XCTAssertTrue(inv([composer]).chats.isEmpty)
    }
    func testSecureFieldNotTraversed() {
        XCTAssertTrue(inv([PinNode(token: "password", role: "AXSecureTextField", children: [section([chat()])])]).chats.isEmpty)
    }
    func testMenuNotTraversed() {
        XCTAssertTrue(inv([PinNode(token: "menu", role: "AXMenu", children: [section([chat()])])]).chats.isEmpty)
    }
    func testNativeGPTTitleRow() {
        let row = PinNode(token: "n", role: "AXButton", label: "Local thread", pressable: true)
        XCTAssertEqual(inv([section([row], label: "Pinned chats")], native: true).chats.count, 1)
    }
    func testBrowserRequiresConversationLink() {
        let row = PinNode(token: "n", role: "AXButton", label: "Local thread", pressable: true)
        XCTAssertTrue(inv([section([row])]).chats.isEmpty)
    }
    func testClaudeNativeUnknownStarredItemNotAssumedChat() {
        let row = PinNode(token: "n", role: "AXButton", label: "Could be a project", pressable: true)
        XCTAssertTrue(inv([section([row], label: "Starred")], provider: .claude, native: true).chats.isEmpty)
    }
    func testClaudeNativeChatIdentifierAccepted() {
        let row = PinNode(token: "n", role: "AXButton", label: "Claude thread", identifier: "chat-123", pressable: true)
        XCTAssertEqual(inv([section([row], label: "Starred")], provider: .claude, native: true).chats.count, 1)
    }
    func testDuplicateURLsDisabled() {
        let result = inv([section([chat(), chat("b")])]); XCTAssertEqual(result.ambiguous, 2); XCTAssertTrue(result.chats.allSatisfy { !$0.enabled })
    }
    func testSameTitlesDifferentURLsAreDistinct() {
        let result = inv([section([chat(), chat("b", url: gpt + "-b")])]); XCTAssertEqual(result.ambiguous, 0); XCTAssertEqual(result.chats.count, 2)
    }
    func testDuplicateNativeTitlesDisabled() {
        let a = PinNode(token: "a", role: "AXButton", label: "Same", pressable: true)
        let b = PinNode(token: "b", role: "AXButton", label: "Same", pressable: true)
        XCTAssertEqual(inv([section([a,b], label: "Pinned chats")], native: true).ambiguous, 2)
    }
    func testOriginalOrderPreserved() {
        XCTAssertEqual(inv([section([chat("z", "Z", url: gpt + "-z"), chat("a", "A")])]).chats.map(\.title), ["Z", "A"])
    }
    func testSelectionPreserved() { XCTAssertTrue(inv([section([chat(selected: true)])]).chats[0].selected) }
    func testControlsInTitleRejected() { XCTAssertNil(PinnedChatPolicy.cleanTitle("Hearth\nDelete")) }
    func testBidiTitleRejected() { XCTAssertNil(PinnedChatPolicy.cleanTitle("Hearth\u{202e}txt")) }
    func testEmptyTitleRejected() { XCTAssertNil(PinnedChatPolicy.cleanTitle("  ")) }
    func testLongTitleRejectedNotSilentlyRetargeted() { XCTAssertNil(PinnedChatPolicy.cleanTitle(String(repeating:"a",count:241))) }
    func testUnicodeTitlePreserved() { XCTAssertEqual(PinnedChatPolicy.cleanTitle("  Mandevilla 🌺 café  "), "Mandevilla 🌺 café") }
    func testCapacityExplicitlyLimited() {
        let chats = (0..<65).map { chat("c\($0)", "Chat \($0)", url: gpt + "-\($0)") }
        let result = inv([section(chats)]); XCTAssertEqual(result.chats.count,60); XCTAssertTrue(result.limited)
    }
    func testThreePerPageAndAllReachable() {
        let chats = (0..<17).map { chat("c\($0)", "Chat \($0)", url: gpt + "-\($0)") }
        let inventory = inv([section(chats)])
        let flattened = (0..<PinnedChatPolicy.pageCount(17)).flatMap { PinnedChatPolicy.page(inventory.chats, index: $0) }
        XCTAssertEqual(flattened, inventory.chats); XCTAssertEqual(PinnedChatPolicy.pageCount(17),6)
    }
    func testInvalidPageSafe() { XCTAssertTrue(PinnedChatPolicy.page(inv([section([chat()])]).chats, index: -1).isEmpty) }
    func testEmptyPagination() { XCTAssertEqual(PinnedChatPolicy.pageCount(0),1) }
    func testDepthLimitStopsTraversal() {
        var n = section([chat()])
        for i in 0..<30 { n = PinNode(token: "d\(i)", children: [n]) }
        let result = inv([n]); XCTAssertTrue(result.limited); XCTAssertTrue(result.chats.isEmpty)
    }
    func testRepeatedNodeTokenLimited() {
        let result = inv([section([chat(),chat()])]); XCTAssertTrue(result.limited)
    }

    func testMixedGPTPinsRequireChatEvidence() {
        let row = PinNode(token: "n", role: "AXButton", label: "Could be a project", pressable: true)
        XCTAssertTrue(inv([section([row])], native: true).chats.isEmpty)
    }
    func testGPTNativeChatIdentifierAccepted() {
        let row = PinNode(token: "n", role: "AXButton", label: "Native work", identifier: "conversation-123", pressable: true)
        XCTAssertEqual(inv([section([row])], native: true).chats.count, 1)
    }
    func testProjectIdentifierNotNativeChat() {
        let row = PinNode(token: "n", role: "AXButton", label: "Project", identifier: "project-chat-123", pressable: true)
        XCTAssertTrue(inv([section([row])], native: true).chats.isEmpty)
    }
    func testHeadingWithStaticChildPinsFollowingSiblings() {
        let h = PinNode(token: "h", role: "AXHeading", label: "Pinned", children: [PinNode(token: "text", role: "AXStaticText", label: "Pinned")])
        XCTAssertEqual(inv([h, chat()]).chats.count, 1)
    }
    func testDisclosureWithStaticChildPinsFollowingSiblings() {
        let h = PinNode(token: "h", role: "AXDisclosureTriangle", label: "Pinned", children: [PinNode(token: "text", role: "AXStaticText", label: "Pinned")])
        XCTAssertEqual(inv([h, chat()]).chats.count, 1)
    }
    func testChatOnlyHeadingAllowsNativeTitleRows() {
        let row = PinNode(token: "n", role: "AXButton", label: "Native work", pressable: true)
        XCTAssertEqual(inv([PinNode(token: "h", role: "AXHeading", label: "Pinned chats"), row], native: true).chats.count, 1)
    }
    func testMixedHeadingResetsChatOnlyScope() {
        let row = PinNode(token: "n", role: "AXButton", label: "Project?", pressable: true)
        XCTAssertTrue(inv([PinNode(token: "h", role: "AXHeading", label: "Pinned chats"), PinNode(token: "h2", role: "AXHeading", label: "Pinned"), row], native: true).chats.isEmpty)
    }
    func testGPTPinnedProjectLinkRejected() {
        XCTAssertTrue(inv([section([chat(url: "https://chatgpt.com/g/g-p-12345678/project")])], native: true).chats.isEmpty)
    }

    func gateFixture() -> (PinNavigationGate, PinSession, [PinnedChat]) {
        let session = PinSession(pid: 42, bundle:"test.assistant", window:"w", document:"d", provider:.chatgpt)
        let chats = inv([section([chat()])]).chats
        var gate = PinNavigationGate(); gate.update(session:session,chats:chats,now:100)
        return (gate,session,chats)
    }
    func testFreshTicketDispatchesOnce() {
        var (gate,session,chats)=gateFixture(); let ticket=gate.ticket(token:"a",now:100.5)!
        XCTAssertTrue(gate.consume(ticket,liveSession:session,liveChats:chats,now:101))
        XCTAssertFalse(gate.consume(ticket,liveSession:session,liveChats:chats,now:101.1))
    }
    func testStaleSampleDoesNotIssueTicket() { let (gate,_,_)=gateFixture(); XCTAssertNil(gate.ticket(token:"a",now:105)) }
    func testFutureSampleDoesNotIssueTicket() { let (gate,_,_)=gateFixture(); XCTAssertNil(gate.ticket(token:"a",now:99)) }
    func testUnknownTokenDoesNotIssueTicket() { let (gate,_,_)=gateFixture(); XCTAssertNil(gate.ticket(token:"gone",now:101)) }
    func testExpiredDispatchRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:103))
    }
    func testChangedAppRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; s.pid=43
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testChangedWindowRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; s.window="other"
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testChangedTabRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; s.document="other"
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testChangedProviderRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; s.provider = .claude
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testChangedTargetLabelRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; c[0].title="different"
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testUnpinnedTargetRejected() {
        var (gate,s,_)=gateFixture(); let t=gate.ticket(token:"a",now:100)!
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:[],now:101))
    }
    func testDisabledTargetRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; c[0].enabled=false
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testClearCancelsTickets() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; gate.clear()
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testUnchangedHeartbeatPreservesGeneration() {
        var (gate,s,c)=gateFixture(); let generation=gate.generation; gate.update(session:s,chats:c,now:101)
        XCTAssertEqual(generation,gate.generation)
    }
    func testChangedInventoryRetiresGeneration() {
        var (gate,s,c)=gateFixture(); let generation=gate.generation; c[0].title="New title"; gate.update(session:s,chats:c,now:101)
        XCTAssertNotEqual(generation,gate.generation)
    }
    func testRecreatedNativeElementRejected() {
        var (gate,s,c)=gateFixture(); let t=gate.ticket(token:"a",now:100)!; c[0].token="replacement"
        XCTAssertFalse(gate.consume(t,liveSession:s,liveChats:c,now:101))
    }
    func testNonFiniteClockRejected() { let (gate,_,_)=gateFixture(); XCTAssertNil(gate.ticket(token:"a",now:.nan)) }
}
