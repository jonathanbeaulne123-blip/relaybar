import Cocoa

/// Actual AppKit/pasteboard/Touch Bar component checks, runnable only on macOS.
/// This never opens, reads, or writes NSPasteboard.general; no source app is inspected.
@MainActor
enum ContextStackNativeChecks {
    static func run() -> Int32 {
        var passed = 0, failed = 0
        func check(_ result: Bool, _ label: String) {
            if result { passed += 1; print("PASS: \(label)") }
            else { failed += 1; print("FAIL: \(label)") }
        }
        let board = NSPasteboard(name: NSPasteboard.Name("local.relaybar.stack-selftest.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let adapter = ContextStackMacPasteboard(board)
        func externalCopy(_ text: String, privateMarker: Bool = false, fileMarker: Bool = false) {
            let item = NSPasteboardItem(); item.setString(text, forType: .string)
            if privateMarker { item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
            if fileMarker { item.setString("file:///tmp/synthetic.txt", forType: .fileURL) }
            board.clearContents(); _ = board.writeObjects([item])
        }
        externalCopy("already copied")
        let controller = ContextStackController(projectID: "fixture", projectName: "Synthetic project", board: board)
        defer { controller.stopForTermination() }
        let session = controller.session
        check(!session.collecting && session.stack.clips.isEmpty, "launch is empty and collection is off")
        session.start(now: 0)
        _ = session.poll(now: 1, appBundle: "local.fixture.editor", appName: "Fixture editor")
        check(session.stack.clips.isEmpty, "Start does not ingest an old named-pasteboard value")
        let code = "\tfunction hello() {\r\n  return '🌿';\r\n}\n"
        externalCopy(code)
        _ = session.poll(now: 2, appBundle: "local.fixture.editor", appName: "Fixture editor")
        check(session.stack.clips.count == 1, "native plain text collected through production coordinator")
        check(session.stack.clips.first?.text.utf8.elementsEqual(code.utf8) == true, "Unicode / indentation / CRLF preserved")
        check(board.string(forType: .string) == code, "collecting does not overwrite pasteboard")
        externalCopy("concealed fixture", privateMarker: true)
        _ = session.poll(now: 3, appBundle: "local.fixture.editor", appName: "Fixture editor")
        check(session.stack.clips.count == 1, "native ConcealedType copy skipped")
        externalCopy("filename fixture", fileMarker: true)
        _ = session.poll(now: 4, appBundle: "local.fixture.editor", appName: "Fixture editor")
        check(session.stack.clips.count == 1, "native file URL plus text skipped")
        externalCopy("second excerpt")
        _ = session.poll(now: 5, appBundle: "local.fixture.editor", appName: "Fixture editor")
        guard session.stack.clips.count == 2 else { print("FAIL: fixture setup failed"); return 1 }
        check(session.copyClip(session.stack.clips[0].id), "native exact-clip output succeeds")
        check(board.string(forType: .string)?.utf8.elementsEqual(code.utf8) == true, "native output contains full text, not title")
        check(adapter.typeNames.contains(ContextStackPolicy.ownType), "own output marker atomically published")
        check(adapter.itemCount == 1 && !adapter.typeNames.contains("public.file-url"), "output is one text item, not a file")
        _ = session.poll(now: 6, appBundle: "local.fixture.editor", appName: "Fixture editor")
        check(session.stack.clips.count == 2, "own native output does not loop into the stack")
        session.pause()
        let driver = TouchBarDriver()
        var back = false, hidden = false
        let slots = controller.slots(back: { back = true }, hide: { hidden = true })
        check(slots.count == 8, "native stack has eight bounded slots")
        check(slots.reduce(CGFloat(0)) { $0 + ($1.width ?? 0) } + CGFloat(slots.count - 1) * 8 <= 685, "declared widths plus estimated gaps fit 685pt budget (not hardware measurement)")
        driver.update(slots)
        for slot in slots {
            let item = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.\(slot.key)")) as? NSCustomTouchBarItem
            check(item?.view is NSButton, "construct actual Touch Bar item: \(slot.key.hasPrefix("stack-clip") ? "clip" : slot.title)")
        }
        let firstKey = "local.relaybar.stack-clip-\(session.stack.clips[0].id.uuidString)"
        let firstItem = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier(firstKey)) as? NSCustomTouchBarItem
        let firstButton = firstItem?.view as? NSButton
        firstButton?.performClick(nil)
        check(board.string(forType: .string)?.utf8.elementsEqual(code.utf8) == true, "physical-component action copies its stable-ID text")
        let oldBar = driver.bar
        session.remove(session.stack.clips[0].id)
        driver.update(controller.slots(back: { back = true }, hide: { hidden = true }))
        check(firstButton?.isEnabled == false, "retired native clip button is disabled")
        check(driver.bar !== oldBar, "changed clip identities create a fresh native bar")
        check(driver.touchBar(oldBar, makeItemForIdentifier: NSTouchBarItem.Identifier(firstKey)) == nil, "retired bar cannot recreate active items")
        let revision = session.stack.revision
        check(session.copyPacket(expectedRevision: revision), "native complete packet output succeeds")
        check(board.string(forType: .string)?.contains("second excerpt") == true, "packet contains included original excerpt")
        check(!session.collecting, "copy packet pauses collection")
        let oldCount = board.changeCount; session.clear()
        check(board.changeCount == oldCount, "clear does not erase or replace the OS pasteboard")
        check(!session.copyPacket(expectedRevision: revision), "cleared/retired packet revision refused")
        let review = controller.constructReviewForSelfTest()
        controller.bindTouchBar(driver.bar)
        check(review?.contentView != nil && review?.isVisible == false, "real review panel constructed without showing it")
        check(review?.touchBar === driver.bar, "review responder bound to current native Touch Bar")
        check(!back && !hidden, "construction did not trigger navigation or hide actions")
        print("\n\(passed) native checks passed; \(failed) failed. Named pasteboard only. No physical Touch Bar, OS permissions, or real app switching verified by this self-test.")
        return failed == 0 ? 0 : 1
    }
}
