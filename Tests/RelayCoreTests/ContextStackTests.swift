import XCTest
@testable import RelayCore

final class StackBoardDouble: ContextStackPasteboard {
    var changeCount = 0
    var types = ["public.utf8-plain-text"]
    var count = 1
    var text: String? = "pre-existing clipboard"
    var payloadReads = 0
    var metadataReads = 0
    var writes: [String] = []
    var failWrite = false
    var duringRead: (() -> Void)?
    var duringMetadata: (() -> Void)?
    var typeNames: [String] { metadataReads += 1; duringMetadata?(); return types }
    var itemCount: Int { metadataReads += 1; return count }
    func readPlainText() -> String? { payloadReads += 1; let result = text; duringRead?(); return result }
    func writePlainText(_ text: String) -> Bool {
        guard !failWrite else { return false }
        writes.append(text); self.text = text; types = ["public.utf8-plain-text", ContextStackPolicy.ownType]; changeCount += 1; return true
    }
    func copied(_ text: String?, types: [String] = ["public.utf8-plain-text"], count: Int = 1) {
        self.text = text; self.types = types; self.count = count; changeCount += 1
    }
}

final class ContextStackTests: XCTestCase {
    func make(_ board: StackBoardDouble = StackBoardDouble()) -> ContextStackSession {
        ContextStackSession(pasteboard: board, projectID: "hearth", projectName: "Hearth")
    }
    @discardableResult func poll(_ session: ContextStackSession, _ now: Double = 1) -> Bool {
        session.poll(now: now, appBundle: "com.example.editor", appName: "Editor")
    }
    func testLaunchNeverReadsPayloadOrMetadata() {
        let board = StackBoardDouble(); let s = make(board)
        XCTAssertFalse(s.collecting); XCTAssertEqual(board.payloadReads, 0); XCTAssertEqual(board.metadataReads, 0)
        XCTAssertFalse(poll(s)); XCTAssertEqual(board.payloadReads, 0); XCTAssertEqual(board.metadataReads, 0)
    }
    func testStartDoesNotImportExistingClipboard() {
        let board = StackBoardDouble(); let s = make(board)
        XCTAssertTrue(s.start(now: 0)); XCTAssertFalse(poll(s))
        XCTAssertTrue(s.stack.clips.isEmpty); XCTAssertEqual(board.payloadReads, 0)
    }
    func testFirstNewCopyCollectsWithoutWritingClipboard() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("one")
        XCTAssertTrue(poll(s)); XCTAssertEqual(s.stack.clips.map(\.text), ["one"]); XCTAssertTrue(b.writes.isEmpty)
    }
    func testUnchangedPasteboardIsNotReadTwice() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("one"); poll(s)
        XCTAssertFalse(poll(s, 2)); XCTAssertEqual(b.payloadReads, 1)
    }
    func testPauseStopsAllMetadataAndPayloadReads() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); s.pause(); b.copied("private")
        XCTAssertFalse(poll(s)); XCTAssertEqual(b.payloadReads, 0); XCTAssertEqual(b.metadataReads, 0)
    }
    func testResumeIgnoresCopiesMadeWhilePaused() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); s.pause(); b.copied("during pause")
        s.start(now: 1); poll(s, 2); XCTAssertTrue(s.stack.clips.isEmpty)
        b.copied("after resume"); poll(s, 3); XCTAssertEqual(s.stack.clips.map(\.text), ["after resume"])
    }
    func testTimeLimitPausesBeforeAnyPayloadRead() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0)
        for n in 1..<900 { poll(s, Double(n)) }
        b.copied("after deadline"); poll(s, 900)
        XCTAssertFalse(s.collecting); XCTAssertEqual(b.payloadReads, 0)
    }
    func testSleepGapPausesAndDoesNotReadPendingClipboard() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("after sleep"); poll(s, 6)
        XCTAssertFalse(s.collecting); XCTAssertEqual(b.payloadReads, 0)
    }
    func testClockRollbackAndInvalidClockFailClosed() {
        for t in [-1.0, Double.nan, Double.infinity] {
            let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("x"); poll(s, t)
            XCTAssertFalse(s.collecting); XCTAssertEqual(b.payloadReads, 0)
        }
        XCTAssertFalse(make().start(now: .infinity))
    }
    func testAllPrivateTransientRemoteFileMarkersSkipBeforePayloadRead() {
        for type in ContextStackPolicy.ignoredTypes {
            let b = StackBoardDouble(); let s = make(b); s.start(now: 0)
            b.copied("potentially private", types: ["public.utf8-plain-text", type]); poll(s)
            XCTAssertEqual(b.payloadReads, 0, type); XCTAssertTrue(s.stack.clips.isEmpty, type)
        }
    }
    func testImagesRTFAndUnknownTypesAreNotCollected() {
        for type in ["public.png", "public.tiff", "public.rtf", "com.example.custom"] {
            let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("not actually plain", types: [type]); poll(s)
            XCTAssertEqual(b.payloadReads, 0)
        }
    }
    func testMultiplePasteboardItemsAreNotSilentlyFlattened() {
        for count in [0, 2, 10] {
            let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("first", count: count); poll(s)
            XCTAssertTrue(s.stack.clips.isEmpty); XCTAssertEqual(b.payloadReads, 0)
        }
    }
    func testURLAndPlainTextAreEligible() {
        for type in ContextStackPolicy.textTypes {
            XCTAssertTrue(ContextStackPolicy.permitsTypes([type], itemCount: 1))
        }
    }
    func testSensitiveAndOwnAppsSkipBeforeReading() {
        let apps = ["com.agilebits.onepassword7", "com.1password.1password", "com.bitwarden.desktop", "org.keepassxc", "com.dashlane", "com.apple.Passwords", "com.apple.keychainaccess", "local.relaybar", ""]
        for app in apps {
            let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("credential")
            s.poll(now: 1, appBundle: app, appName: "app"); XCTAssertEqual(b.payloadReads, 0, app)
        }
    }
    func testSkippedCopyDoesNotAppearAfterLeavingExcludedApp() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("credential")
        s.poll(now: 1, appBundle: "com.apple.Passwords", appName: "Passwords"); poll(s, 2)
        XCTAssertTrue(s.stack.clips.isEmpty); XCTAssertEqual(b.payloadReads, 0)
    }
    func testPrivateKeyAndCommonTokenHeuristics() {
        let examples = ["-----BEGIN PRIVATE KEY-----\nx", "-----BEGIN RSA PRIVATE KEY-----", "ghp_" + String(repeating: "A", count: 32), "api_key=abcdefghijk", "Authorization: Bearer abcdefghijk", "AKIA" + String(repeating: "A", count: 16)]
        for text in examples { XCTAssertTrue(ContextStackPolicy.looksSensitive(text), text) }
        for text in ["Use a password manager.", "const apiKey = process.env.API_KEY", "let greeting = 'hello'", "Build the next feature."] { XCTAssertFalse(ContextStackPolicy.looksSensitive(text), text) }
    }
    func testSensitiveTextNotRetainedOrEchoedInStatus() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0)
        let text = "password=neverlogthisvalue"; b.copied(text); poll(s)
        XCTAssertTrue(s.stack.clips.isEmpty); XCTAssertFalse(s.message.contains("neverlogthisvalue")); XCTAssertTrue(b.writes.isEmpty)
    }
    func testNilReadPausesRatherThanPromptingContinuously() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied(nil); poll(s)
        XCTAssertFalse(s.collecting); b.copied(nil); poll(s, 2); XCTAssertEqual(b.payloadReads, 1)
    }
    func testChangeDuringMetadataPreventsPayloadRead() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("old")
        b.duringMetadata = { b.changeCount += 1 }; poll(s)
        XCTAssertEqual(b.payloadReads, 0); XCTAssertTrue(s.stack.clips.isEmpty)
    }
    func testChangeDuringPayloadRejectsMixedSnapshot() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("old")
        b.duringRead = { b.copied("new") }; poll(s); XCTAssertTrue(s.stack.clips.isEmpty)
        b.duringRead = nil; poll(s, 2); XCTAssertEqual(s.stack.clips.map(\.text), ["new"])
    }
    func testPauseDuringReentrantReadPreventsCommit() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("late")
        b.duringRead = { s.pause() }; poll(s); XCTAssertTrue(s.stack.clips.isEmpty)
    }
    func testProjectSwitchDuringReentrantReadPreventsCommit() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0); b.copied("late")
        b.duringRead = { s.switchProject(id: "new", name: "New") }; poll(s)
        XCTAssertTrue(s.stack.clips.isEmpty); XCTAssertEqual(s.stack.projectID, "new")
    }
    func testExactDuplicateKeepsOrderAndExcludedState() throws {
        var stack = ContextStack(projectID: "x", projectName: "X")
        let first = try XCTUnwrap(stack.add("first", observedApp: "One"))
        _ = try stack.add("second", observedApp: "Two"); stack.toggle(first)
        let revision = stack.revision
        XCTAssertNil(try stack.add("first", observedApp: "Another"))
        XCTAssertEqual(stack.clips.map(\.text), ["first", "second"])
        XCTAssertFalse(stack.clips[0].included); XCTAssertEqual(stack.revision, revision)
    }
    func testWhitespaceAndCanonicallyEqualButByteDifferentCopiesStayDistinct() throws {
        var stack = ContextStack(projectID: "x", projectName: "X")
        for text in ["a", " a", "a\n", "\u{00e9}", "e\u{0301}"] { _ = try stack.add(text, observedApp: "Test") }
        XCTAssertEqual(stack.clips.count, 5)
    }
    func testSingleClipCopyPreservesExactUnicodeAndCodeBytes() {
        let b = StackBoardDouble(); let s = make(b)
        let text = "\tfunction f() {\r\n    return '🌿 café';\r\n}\n "
        s.addManualText(text)
        XCTAssertTrue(s.copyClip(s.stack.clips[0].id))
        XCTAssertEqual(Array(b.writes[0].utf8), Array(text.utf8))
    }
    func testCapacityStopsWithoutEvictingOrTruncating() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0)
        for i in 1...20 { b.copied("clip \(i)"); poll(s, Double(i)) }
        XCTAssertEqual(s.stack.clips.count, 20); XCTAssertFalse(s.collecting)
        XCTAssertFalse(s.start(now: 21)); XCTAssertEqual(s.stack.clips[0].text, "clip 1")
        s.remove(s.stack.clips[0].id); XCTAssertTrue(s.start(now: 22))
    }
    func testTooLargeClipIsRejectedWholeAndExistingStackIntact() {
        let s = make(); s.addManualText("keep"); s.addManualText(String(repeating: "é", count: 32_769))
        XCTAssertEqual(s.stack.clips.map(\.text), ["keep"])
    }
    func testExactClipByteLimitAccepted() {
        let s = make(); s.addManualText(String(repeating: "é", count: 32_768))
        XCTAssertEqual(s.stack.totalBytes, 65_536)
    }
    func testTotalByteLimitRejectsWholePassage() {
        let b = StackBoardDouble(); let s = make(b)
        for letter in ["a", "b", "c"] { s.addManualText(String(repeating: letter, count: 65_536)) }
        s.addManualText(String(repeating: "d", count: 65_530)); s.start(now: 0)
        b.copied("too much text"); poll(s)
        XCTAssertEqual(s.stack.clips.count, 4); XCTAssertFalse(s.collecting); XCTAssertEqual(s.stack.totalBytes, 262_138)
    }
    func testExactTotalLimitPausesCollection() {
        let b = StackBoardDouble(); let s = make(b); s.start(now: 0)
        for (i, letter) in ["a", "b", "c", "d"].enumerated() { b.copied(String(repeating: letter, count: 65_536)); poll(s, Double(i+1)) }
        XCTAssertEqual(s.stack.totalBytes, 262_144); XCTAssertFalse(s.collecting)
    }
    func testEmptyTextNeverAdded() {
        let s = make(); for text in ["", " \n\t\r"] { s.addManualText(text) }; XCTAssertTrue(s.stack.clips.isEmpty)
    }
    func testPacketPreservesOrderAndBoundariesForCodeFences() throws {
        var stack = ContextStack(projectID: "x", projectName: "Hearth")
        let first = "before\n```swift\nlet x = 1\n```\nafter"
        _ = try stack.add(first, observedApp: "Observed in Editor")
        _ = try stack.add("second", observedApp: "Manual")
        let packet = try stack.packet(expectedRevision: stack.revision)
        XCTAssertTrue(packet.contains("````text\n" + first + "\n````"))
        XCTAssertLessThan(try XCTUnwrap(packet.range(of: first)?.lowerBound), try XCTUnwrap(packet.range(of: "second")?.lowerBound))
        XCTAssertTrue(packet.contains("not verified authorship"))
    }
    func testExcludeReorderAndReincludeChangeOnlyRequestedClips() throws {
        var stack = ContextStack(projectID: "x", projectName: "X")
        let a = try XCTUnwrap(stack.add("alpha", observedApp: "A"))
        let b = try XCTUnwrap(stack.add("beta", observedApp: "B"))
        _ = try stack.add("gamma", observedApp: "C")
        stack.toggle(b); stack.move(a, by: 1)
        var output = try stack.packet(expectedRevision: stack.revision)
        XCTAssertFalse(output.contains("beta")); XCTAssertEqual(stack.included.map(\.text), ["alpha", "gamma"])
        stack.toggle(b); output = try stack.packet(expectedRevision: stack.revision)
        XCTAssertTrue(output.contains("beta")); XCTAssertEqual(stack.included.map(\.text), ["beta", "alpha", "gamma"])
    }
    func testInvalidMoveAndRemoveDoNotMutateRevision() throws {
        var stack = ContextStack(projectID: "x", projectName: "X")
        let a = try XCTUnwrap(stack.add("alpha", observedApp: "A")); let version = stack.revision
        stack.move(a, by: -1); stack.move(a, by: 3); stack.remove(UUID()); stack.toggle(UUID())
        XCTAssertEqual(stack.revision, version)
    }
    func testStaleHandoffTapDoesNotWrite() {
        let b = StackBoardDouble(); let s = make(b); s.addManualText("first"); let old = s.stack.revision
        s.addManualText("second"); XCTAssertFalse(s.copyPacket(expectedRevision: old)); XCTAssertTrue(b.writes.isEmpty)
    }
    func testStaleClipIDDoesNotCopyDifferentClip() {
        let b = StackBoardDouble(); let s = make(b); s.addManualText("first"); let old = s.stack.clips[0].id
        s.remove(old); s.addManualText("second"); XCTAssertFalse(s.copyClip(old)); XCTAssertTrue(b.writes.isEmpty)
    }
    func testCopyPacketPausesAndKeepsStackForReuse() {
        let b = StackBoardDouble(); let s = make(b); s.addManualText("one"); s.start(now: 0)
        XCTAssertTrue(s.copyPacket(expectedRevision: s.stack.revision)); XCTAssertFalse(s.collecting)
        XCTAssertEqual(s.stack.clips.count, 1); XCTAssertEqual(b.writes.count, 1)
    }
    func testCopyClipDoesNotRecordItselfOrReorder() {
        let b = StackBoardDouble(); let s = make(b); s.addManualText("one"); s.addManualText("two"); s.start(now: 0)
        XCTAssertTrue(s.copyClip(s.stack.clips[0].id)); XCTAssertTrue(s.collecting); poll(s)
        XCTAssertEqual(s.stack.clips.map(\.text), ["one", "two"]); XCTAssertEqual(b.payloadReads, 0)
    }
    func testWriteFailurePausesButDoesNotDestroyStack() {
        let b = StackBoardDouble(); let s = make(b); s.addManualText("one"); s.start(now: 0); b.failWrite = true
        XCTAssertFalse(s.copyPacket(expectedRevision: s.stack.revision)); XCTAssertFalse(s.collecting)
        XCTAssertEqual(s.stack.clips[0].text, "one"); XCTAssertTrue(b.writes.isEmpty)
    }
    func testCopyNothingSelectedDoesNotWrite() {
        let b = StackBoardDouble(); let s = make(b)
        XCTAssertFalse(s.copyPacket(expectedRevision: s.stack.revision))
        s.addManualText("one"); s.toggle(s.stack.clips[0].id)
        XCTAssertFalse(s.copyPacket(expectedRevision: s.stack.revision)); XCTAssertTrue(b.writes.isEmpty)
    }
    func testClearDoesNotTouchGeneralClipboard() {
        let b = StackBoardDouble(); let s = make(b); s.addManualText("one"); s.start(now: 0)
        let before = b.changeCount; s.clear()
        XCTAssertFalse(s.collecting); XCTAssertTrue(s.stack.clips.isEmpty); XCTAssertEqual(b.changeCount, before); XCTAssertTrue(b.writes.isEmpty)
    }
    func testManualPasteIsExplicitAndLeavesCollectionPaused() {
        let b = StackBoardDouble(); let s = make(b)
        XCTAssertTrue(s.pasteClip()); XCTAssertFalse(s.collecting)
        XCTAssertEqual(s.stack.clips[0].text, "pre-existing clipboard"); XCTAssertEqual(b.payloadReads, 1)
    }
    func testManualPasteStillRespectsConcealedMarker() {
        let b = StackBoardDouble(); let s = make(b); b.copied("private", types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"])
        s.pasteClip(); XCTAssertTrue(s.stack.clips.isEmpty); XCTAssertEqual(b.payloadReads, 0)
    }
    func testLabelsDoNotAlterPayloadAndDoNotRenderBidiControls() throws {
        let original = "\u{202e}hello\n\tworld\u{2066}"
        var stack = ContextStack(projectID: "x", projectName: "X\nFake header")
        _ = try stack.add(original, observedApp: "App\n\u{202e}Label")
        XCTAssertEqual(stack.clips[0].text, original); XCTAssertEqual(stack.clips[0].title, "hello world")
        XCTAssertEqual(stack.projectName, "X Fake header")
    }
    func testWorkspaceSeparatesProjectsAndRestoresTheirClips() {
        let b = StackBoardDouble(); let w = ContextStackWorkspace(pasteboard: b, projectID: "a", projectName: "A")
        let a = w.current; a.addManualText("alpha"); a.start(now: 0)
        XCTAssertTrue(w.activate(projectID: "b", projectName: "B")); XCTAssertFalse(a.collecting); XCTAssertTrue(w.current.stack.clips.isEmpty)
        w.current.addManualText("beta"); w.current.start(now: 1)
        XCTAssertTrue(w.activate(projectID: "a", projectName: "A")); XCTAssertTrue(w.current === a)
        XCTAssertEqual(w.current.stack.clips.map(\.text), ["alpha"]); XCTAssertFalse(w.current.collecting)
        XCTAssertEqual(b.payloadReads, 0)
    }
    func testWorkspaceRenameInvalidatesOldHandoffRevision() {
        let w = ContextStackWorkspace(pasteboard: StackBoardDouble(), projectID: "a", projectName: "A")
        w.current.addManualText("alpha"); let old = w.current.stack.revision
        XCTAssertTrue(w.activate(projectID: "a", projectName: "New A")); XCTAssertNotEqual(w.current.stack.revision, old)
        XCTAssertFalse(w.current.copyPacket(expectedRevision: old))
    }
    func testWorkspaceLimitsRejectWithoutChangingOrEvicting() {
        let w = ContextStackWorkspace(pasteboard: StackBoardDouble(), projectID: "0", projectName: "Zero")
        w.current.addManualText("keep")
        for i in 1..<100 { XCTAssertTrue(w.activate(projectID: String(i), projectName: "P")) }
        let old = w.current
        XCTAssertFalse(w.activate(projectID: "100", projectName: "Too many")); XCTAssertTrue(w.current === old)
        XCTAssertFalse(w.activate(projectID: "", projectName: "Empty")); XCTAssertTrue(w.current === old)
        XCTAssertTrue(w.activate(projectID: "0", projectName: "Zero")); XCTAssertEqual(w.current.stack.clips[0].text, "keep")
    }
    func testWorkspaceClearAllRemovesInactiveProjectClipsToo() {
        let w = ContextStackWorkspace(pasteboard: StackBoardDouble(), projectID: "a", projectName: "A")
        let a = w.current; a.addManualText("alpha")
        w.activate(projectID: "b", projectName: "B"); w.current.addManualText("beta"); w.clearAll()
        XCTAssertTrue(a.stack.clips.isEmpty); XCTAssertTrue(w.current.stack.clips.isEmpty)
        w.activate(projectID: "a", projectName: "A"); XCTAssertTrue(w.current.stack.clips.isEmpty)
    }
    func testNewSessionDoesNotRestoreAnyHistory() {
        let b = StackBoardDouble(); let old = make(b); old.addManualText("old"); let fresh = make(b)
        XCTAssertTrue(fresh.stack.clips.isEmpty); XCTAssertFalse(fresh.collecting)
    }
    func testRandomOperationsMaintainBoundsAndUniqueIdentities() {
        var stack = ContextStack(projectID: "test", projectName: "Test")
        var seed: UInt64 = 20260917
        for i in 0..<3000 {
            seed = seed &* 6364136223846793005 &+ 1
            let op = Int((seed >> 32) % 6)
            if op <= 2 { _ = try? stack.add("clip \(i % 55)\n" + String(repeating: "🌿", count: i % 33), observedApp: "Test") }
            else if let id = stack.clips.first?.id {
                if op == 3 { stack.remove(id) } else if op == 4 { stack.toggle(id) } else { stack.move(id, by: 1) }
            }
            XCTAssertLessThanOrEqual(stack.clips.count, 20)
            XCTAssertLessThanOrEqual(stack.totalBytes, 262_144)
            XCTAssertEqual(Set(stack.clips.map(\.id)).count, stack.clips.count)
            XCTAssertEqual(stack.included.map(\.id), stack.clips.filter(\.included).map(\.id))
        }
    }
}
