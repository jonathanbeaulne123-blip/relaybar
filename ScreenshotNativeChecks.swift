import Cocoa
import ImageIO

/// Run only on a Mac: isolated fixtures and a named pasteboard, not the user's screenshots/clipboard.
@MainActor
enum ScreenshotNativeChecks {
    static func run() -> Int32 {
        var failed = 0; var passed = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { passed += 1; print("PASS: \(name)") }
            else { failed += 1; print("FAIL: \(name)") }
        }
        func wait(_ condition: () -> Bool, seconds: Double = 12) -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while !condition() && Date() < deadline {
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.08))
            }
            return condition()
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("RelayBar-Screenshot-SelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let rgb = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw RelayError.invalid("Cannot create synthetic image fixture.")
            }
            context.setFillColor(CGColor(gray: 0.18, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
            context.setFillColor(CGColor(red: 0.3, green: 0.65, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 40, y: 40, width: 230, height: 220))
            guard let image = context.makeImage() else { throw RelayError.invalid("Cannot finish test fixture.") }
            let rawPNG = try ScreenshotImages.encode(image, type: "public.png")
            let prepared = try ScreenshotImages.prepare(rawPNG)
            check(prepared.png == rawPNG, "native PNG bytes preserved exactly")
            check(prepared.width == 640 && prepared.height == 400, "full image dimensions preserved")
            let thumbSource = CGImageSourceCreateWithData(prepared.thumbnailPNG as CFData, nil)!
            let thumb = CGImageSourceCreateImageAtIndex(thumbSource, 0, nil)!
            check(max(thumb.width, thumb.height) <= 240, "thumbnail is bounded independently of full image")
            let jpeg = try ScreenshotImages.encode(image, type: "public.jpeg")
            let converted = try ScreenshotImages.prepare(jpeg)
            check(converted.width == 640 && converted.height == 400, "JPEG imports without downscaling")
            do { _ = try ScreenshotImages.prepare(Data("not an image".utf8)); check(false, "invalid image rejected") }
            catch { check(true, "invalid image rejected") }
            let payload = try ScreenshotImages.clipboardPayload(prepared.png)
            let board = NSPasteboard(name: NSPasteboard.Name(rawValue: "local.relaybar.screenshot-selftest.\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            check(ScreenshotShelfController.write(payload, id: UUID(), to: board), "write PNG/TIFF to isolated pasteboard")
            check(board.data(forType: .png) == rawPNG, "clipboard contains full PNG, not thumbnail")
            check(board.data(forType: .tiff) != nil, "TIFF compatibility representation present")
            check(board.string(forType: .string) == nil && board.data(forType: .fileURL) == nil,
                  "clipboard contains image data, not a filename or file URL")

            let driver = TouchBarDriver(); var tapped = false
            driver.update([.init(key: "fixture", title: "1", help: "Synthetic screenshot", image: NSImage(data: prepared.thumbnailPNG), width: 78) { tapped = true }])
            let item = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.fixture")) as? NSCustomTouchBarItem
            let button = item?.view as? NSButton
            check(button?.image != nil, "native thumbnail Touch Bar button constructed")
            button?.performClick(nil); check(tapped, "thumbnail button invokes its action")
            var updatedAction = false
            driver.update([.init(key: "fixture", title: "2", help: "Updated screenshot", image: NSImage(data: prepared.thumbnailPNG), width: 78) { updatedAction = true }])
            button?.performClick(nil); check(updatedAction && button?.title == "2", "existing Touch Bar item refreshes image/action state")

            let retiredBar = driver.bar
            driver.update([.init(key: "new-fixture", title: "1", help: "New screenshot", image: NSImage(data: prepared.thumbnailPNG), width: 78) {}])
            check(driver.bar !== retiredBar, "new image/page gets a fresh native bar")
            check(button?.isEnabled == false && button?.image == nil, "retired thumbnail is disabled and releases image")
            check(driver.touchBar(retiredBar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.new-fixture")) == nil,
                  "retired bar cannot create active controls")
            let newItem = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.new-fixture")) as? NSCustomTouchBarItem
            check((newItem?.view as? NSButton)?.image != nil, "fresh bar constructs the new screenshot thumbnail")
            let stableBar = driver.bar
            driver.update([.init(key: "new-fixture", title: "✓", help: "Copied screenshot", image: NSImage(data: prepared.thumbnailPNG), width: 78) {}])
            check(driver.bar === stableBar, "copy feedback keeps the same native bar")
            // Returning to an earlier key must not revive its retired disabled item.
            driver.update([.init(key: "fixture", title: "1", help: "Returned screenshot", image: NSImage(data: prepared.thumbnailPNG), width: 78) {}])
            let returned = driver.touchBar(driver.bar, makeItemForIdentifier: NSTouchBarItem.Identifier("local.relaybar.fixture")) as? NSCustomTouchBarItem
            check((returned?.view as? NSButton)?.isEnabled == true, "returning to a screenshot page gives live controls")

            let input = root.appendingPathComponent("Screenshots", isDirectory: true)
            try fm.createDirectory(at: input, withIntermediateDirectories: true)
            let file = input.appendingPathComponent("Screenshot 2026-09-17 test-1.png")
            try rawPNG.write(to: file)
            check(try ScreenshotImages.readStableFile(file, expectedSize: rawPNG.count) == rawPNG, "descriptor-based source read")
            let link = input.appendingPathComponent("Screenshot 2026-09-17 linked.png")
            try fm.createSymbolicLink(at: link, withDestinationURL: file)
            do { _ = try ScreenshotImages.readStableFile(link, expectedSize: rawPNG.count); check(false, "source symlink rejected") }
            catch { check(true, "source symlink rejected") }
            try fm.removeItem(at: link)
            // Six original files, distinct capture times, actual directory monitoring and settle delays.
            let start = Date().addingTimeInterval(-40)
            for n in 1...6 {
                let url = input.appendingPathComponent("Screenshot 2026-09-17 test-\(n).png")
                try rawPNG.write(to: url)
                try fm.setAttributes([.creationDate: start.addingTimeInterval(Double(n)), .modificationDate: start.addingTimeInterval(Double(n))], ofItemAtPath: url.path)
            }
            var state: ScreenshotWorker.State?
            var presentation = ScreenshotPresentationState(); presentation.showTools()
            var addedEvents = 0
            let worker = ScreenshotWorker(directory: root.appendingPathComponent("Cache")) {
                state = $0
                if $0.didAdd { addedEvents += 1; presentation.screenshotAdded() }
            }
            defer { worker.stop() }
            worker.start(folder: input)
            check(wait { state?.entries.count == 5 }, "folder watcher imports five completed screenshot files")
            let names = state?.entries.map(\.name) ?? []
            check(names == (2...6).reversed().map { "Screenshot 2026-09-17 test-\($0).png" }, "watcher retains newest five in capture order")
            check(try fm.contentsOfDirectory(atPath: input.path).count == 6, "watcher leaves all six original files intact")
            check(state?.thumbnails.count == 5, "watcher supplies five real thumbnail images")
            check(presentation.page == .screenshots && addedEvents > 0,
                  "real watcher image-commit event selects the screenshot viewer")
            check(presentation.overlayAction(overlayEnabled: true, eligibleApp: true) == .reopen,
                  "image-commit event requests overlay reopen")
            if let id = state?.entries.first?.id {
                var fetched: Result<ScreenshotImages.ClipboardPayload, Error>?
                worker.payload(id: id) { fetched = $0 }
                check(wait { fetched != nil }, "image copy payload prepared off the main thread")
                switch fetched {
                case .success(let result): check(result.png == rawPNG, "copy payload matches selected full screenshot")
                default: check(false, "copy payload matches selected full screenshot")
                }
            }
            presentation.showTools()
            worker.clear()
            check(wait { state?.entries.isEmpty == true }, "clear empties shelf")
            check(presentation.page == .tools, "clear status does not auto-open viewer")
            _ = wait({ false }, seconds: 3.5)
            check(state?.entries.isEmpty == true, "later scans do not refill cleared screenshots")
            let newFile = input.appendingPathComponent("Screenshot 2026-09-17 after-clear.png")
            try rawPNG.write(to: newFile)
            check(wait { state?.entries.count == 1 }, "new file event refills shelf after clear")
            check(presentation.page == .screenshots, "new capture auto-opens after returning to Tools")
            worker.stop()
            check(wait { state?.watching == false }, "watcher stops and releases directory event source")
        } catch { check(false, "native test setup/operation: \(error.localizedDescription)") }
        print("\nScreenshot native self-test: \(passed) passed; \(failed) failed.")
        print("Used only synthetic files and an isolated named pasteboard. General clipboard was not touched.")
        print("Physical Touch Bar visibility and image pasting into ChatGPT/Claude still require a manual test.")
        return failed == 0 ? 0 : 1
    }
}
