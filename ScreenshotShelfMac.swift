import Cocoa
import ImageIO
import CryptoKit
import Darwin

/// No screen capture, key logging or clipboard polling. Reads only the selected folder.
enum ScreenshotImages {
    struct Prepared { let png: Data; let thumbnailPNG: Data; let width: Int; let height: Int }
    struct ClipboardPayload { let png: Data; let tiff: Data? }

    static func prepare(_ data: Data) throws -> Prepared {
        guard !data.isEmpty, data.count <= ScreenshotPolicy.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source).rawValue == 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= ScreenshotPolicy.maximumPixels / height else {
            throw RelayError.invalid("Not a complete supported image, or it exceeds 80 MB / 50 million pixels.")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 240,
                                       kCGImageSourceShouldCacheImmediately: true]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw RelayError.invalid("Could not decode a screenshot thumbnail. The file may still be saving.")
        }
        let thumbnailPNG = try encode(thumb, type: "public.png")
        let png: Data
        if CGImageSourceGetType(source) as String? == "public.png" {
            png = data // Native PNG screenshots are kept byte-for-byte, not downscaled.
        } else {
            // Preserve image orientation for imported JPEG/HEIC/TIFF without reducing dimensions.
            var fullOptions = options
            fullOptions[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, fullOptions as CFDictionary) else {
                throw RelayError.invalid("Could not decode the full screenshot.")
            }
            png = try encode(image, type: "public.png")
        }
        guard png.count <= ScreenshotPolicy.maximumBytes,
              let normalized = CGImageSourceCreateWithData(png as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(normalized, 0, nil) as? [CFString: Any],
              let normalizedWidth = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let normalizedHeight = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            throw RelayError.invalid("The full-resolution PNG exceeds the cache safety limit.")
        }
        return Prepared(png: png, thumbnailPNG: thumbnailPNG, width: normalizedWidth, height: normalizedHeight)
    }
    static func clipboardPayload(_ png: Data) throws -> ClipboardPayload {
        guard png.count <= ScreenshotPolicy.maximumBytes,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source).rawValue == 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= ScreenshotPolicy.maximumPixels / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RelayError.invalid("Could not decode the cached screenshot; clipboard left unchanged.")
        }
        // PNG is the original full image. TIFF is an additional compatibility representation.
        let tiff = try? encode(image, type: "public.tiff")
        return ClipboardPayload(png: png, tiff: tiff)
    }
    static func encode(_ image: CGImage, type: String) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type as CFString, 1, nil) else {
            throw RelayError.invalid("Could not prepare image data.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RelayError.invalid("Image encoding failed.") }
        return output as Data
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Reads a fixed-size ordinary file through O_NOFOLLOW; rejects a writer changing it mid-read.
    static func readStableFile(_ url: URL, expectedSize: Int) throws -> Data {
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
        guard fd >= 0 else { throw RelayError.invalid("Screenshot file is unavailable or is a symbolic link.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
              before.st_size == expectedSize, expectedSize > 0, expectedSize <= ScreenshotPolicy.maximumBytes else {
            throw RelayError.invalid("Screenshot is still changing or is not an ordinary file.")
        }
        var data = Data()
        while data.count <= expectedSize {
            let chunk = try handle.read(upToCount: min(1_048_576, expectedSize + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }; data.append(chunk)
        }
        var after = stat()
        guard fstat(fd, &after) == 0, data.count == expectedSize,
              after.st_size == before.st_size, after.st_ino == before.st_ino,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else {
            throw RelayError.invalid("Screenshot changed while being read. It will be retried.")
        }
        return data
    }
}

/// Serial worker; all file IO, image decoding and retention run off the UI thread.
final class ScreenshotWorker {
    struct State {
        let entries: [ScreenshotEntry]
        let thumbnails: [UUID: Data]
        let message: String
        let watching: Bool
        let didAdd: Bool
    }
    private struct Candidate {
        let url: URL; let key: String; let version: String; let name: String
        let capturedAt: Date; let modifiedAt: Date; let byteCount: Int
    }
    private let queue = DispatchQueue(label: "local.relaybar.screenshots", qos: .utility)
    private let callback: @MainActor (State) -> Void
    private var store: ScreenshotShelfStore?
    private var folder: URL?
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var pendingScan: DispatchWorkItem?
    private var gate = ScreenshotStabilityGate()
    private var thumbnails: [UUID: Data] = [:]
    private var customPrefix: String?
    private var lastPublished = ""
    private var failureCounts: [String: Int] = [:]

    init(directory: URL, callback: @escaping @MainActor (State) -> Void) {
        self.callback = callback
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                self.store = try ScreenshotShelfStore(directory: directory)
                self.loadThumbnails()
                self.publish("Choose your screenshot save folder to begin.")
            } catch { self.publish("Screenshot storage could not be loaded: \(error.localizedDescription)") }
        }
    }
    func start(folder: URL) {
        queue.async { [weak self] in self?.startOnQueue(folder: folder) }
    }
    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue(); self?.publish("Screenshot collection is stopped. Saved thumbnails remain available.")
        }
    }
    func clear() {
        queue.async { [weak self] in
            guard let self = self, let store = self.store else { return }
            do {
                try store.clear(); self.thumbnails.removeAll(); self.gate.reset()
                self.publish("Shelf cleared. Original files and the system clipboard are unchanged.")
            } catch { self.publish("Could not clear screenshot shelf: \(error.localizedDescription)") }
        }
    }
    func importClipboard(_ data: Data) {
        queue.async { [weak self] in
            guard let self = self, let store = self.store else { return }
            do {
                let prepared = try ScreenshotImages.prepare(data)
                let key = "clipboard-" + ScreenshotImages.digest(prepared.png)
                let now = Date()
                let entry = ScreenshotEntry(sourceKey: key, sourceVersion: key, name: "Image explicitly added from clipboard",
                                            capturedAt: now, width: prepared.width, height: prepared.height, byteCount: prepared.png.count)
                let added = try store.insert(entry, png: prepared.png)
                if added { self.thumbnails[entry.id] = prepared.thumbnailPNG; self.pruneThumbnails() }
                self.publish(added ? "Clipboard image saved. Tap its thumbnail to copy it later." : "That clipboard image is already on the shelf.", didAdd: added)
            } catch { self.publish("Could not add clipboard image: \(error.localizedDescription)") }
        }
    }
    func payload(id: UUID, completion: @escaping @MainActor (Result<ScreenshotImages.ClipboardPayload, Error>) -> Void) {
        queue.async { [weak self] in
            let result: Result<ScreenshotImages.ClipboardPayload, Error>
            do {
                guard let store = self?.store else { throw RelayError.invalid("Screenshot storage is unavailable.") }
                result = .success(try ScreenshotImages.clipboardPayload(store.readPNG(id: id)))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    private func startOnQueue(folder requested: URL) {
        stopOnQueue()
        guard store != nil else { publish("Screenshot storage is unavailable. Existing data was left alone."); return }
        let url = requested.standardizedFileURL.resolvingSymlinksInPath()
        // No recursive scan and never watch the cache itself or a parent that directly is the cache.
        if let own = store?.directory.resolvingSymlinksInPath(), url == own {
            publish("Choose the folder where macOS saves screenshots, not RelayBar's cache."); return
        }
        do { _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) }
        catch { publish("Cannot read screenshot folder. Choose it again from RB → Screenshot Shelf. \(error.localizedDescription)"); return }
        let fd = url.path.withCString { Darwin.open($0, O_EVTONLY) }
        guard fd >= 0 else { publish("Cannot watch that folder. Choose your screenshot save folder again."); return }
        folder = url
        customPrefix = CFPreferencesCopyAppValue("name" as CFString, "com.apple.screencapture" as CFString) as? String
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke], queue: queue)
        watcher.setEventHandler { [weak self] in
            guard let self = self, let event = self.source?.data else { return }
            if !event.intersection([.rename, .delete, .revoke]).isEmpty {
                self.stopOnQueue(); self.publish("The screenshot folder moved or became unavailable. Choose it again.")
            } else { self.scheduleScan(after: 0.05) }
        }
        watcher.setCancelHandler { Darwin.close(fd) }
        source = watcher; watcher.resume()
        // Fallback catches file content changes, metadata arriving late, and wake-from-sleep gaps.
        let periodic = DispatchSource.makeTimerSource(queue: queue)
        periodic.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        periodic.setEventHandler { [weak self] in self?.scan() }
        timer = periodic; periodic.resume()
        publish("Watching \(url.lastPathComponent). Waiting for complete screenshot files…")
        scan()
    }
    private func stopOnQueue() {
        pendingScan?.cancel(); pendingScan = nil
        source?.cancel(); source = nil; timer?.cancel(); timer = nil; folder = nil
        gate.reset(); failureCounts.removeAll()
    }
    private func scheduleScan(after delay: Double) {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work; queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func markedScreenshot(_ url: URL) -> Bool {
        let isCaptureAttr = "com.apple.metadata:kMDItemIsScreenCapture"
        let captureTypeAttr = "com.apple.metadata:kMDItemScreenCaptureType"
        return url.path.withCString { path in
            // Check kMDItemScreenCaptureType first (present on native macOS captures)
            if getxattr(path, captureTypeAttr, nil, 0, 0, XATTR_NOFOLLOW) > 0 { return true }
            // Check kMDItemIsScreenCapture
            let length = getxattr(path, isCaptureAttr, nil, 0, 0, XATTR_NOFOLLOW)
            guard length > 0, length <= 4096 else { return false }
            var data = Data(count: length)
            let count = data.withUnsafeMutableBytes { getxattr(path, isCaptureAttr, $0.baseAddress, length, 0, XATTR_NOFOLLOW) }
            guard count == length else { return false }
            if let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
                if let number = value as? NSNumber { return number.boolValue }
                if let text = value as? String { return ["1", "true", "yes"].contains(text.lowercased()) }
            }
            if data.count >= 9 && data.starts(with: [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30]) {
                let tag = data[8]
                if tag == 0x09 { return true }
                if tag == 0x08 { return false }
            }
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if ["1", "true", "yes"].contains(text.lowercased()) { return true }
            }
            return false
        }
    }
    private func candidates(in folder: URL) throws -> [Candidate] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsHiddenFiles])
        var result: [Candidate] = []
        for url in urls {
            let name = url.lastPathComponent
            guard ScreenshotPolicy.extensions.contains(url.pathExtension.lowercased()),
                  let attrs = try? fm.attributesOfItem(atPath: url.path), attrs[.type] as? FileAttributeType == .typeRegular,
                  let bytes = (attrs[.size] as? NSNumber)?.intValue, bytes > 0, bytes <= ScreenshotPolicy.maximumBytes,
                  let modified = attrs[.modificationDate] as? Date else { continue }
            let created = attrs[.creationDate] as? Date ?? modified
            if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
               values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded { continue }
            let named = ScreenshotPolicy.isCandidate(filename: name, markedAsScreenshot: false, customPrefix: customPrefix)
            guard named || ScreenshotPolicy.isCandidate(filename: name, markedAsScreenshot: markedScreenshot(url)) else { continue }
            let identity = "\(url.path)|\(created.timeIntervalSince1970)|\(attrs[.systemFileNumber] ?? "")"
            let key = ScreenshotImages.digest(Data(identity.utf8))
            let version = ScreenshotImages.digest(Data("\(key)|\(modified.timeIntervalSince1970)|\(bytes)".utf8))
            result.append(Candidate(url: url, key: key, version: version, name: name, capturedAt: created, modifiedAt: modified, byteCount: bytes))
        }
        // Only the newest 32 possible screenshots need decoding/settling. This is not a library scan.
        return Array(result.sorted {
            if $0.capturedAt != $1.capturedAt { return $0.capturedAt > $1.capturedAt }
            return $0.name > $1.name
        }.prefix(32))
    }
    private func scan() {
        guard let folder = folder, let store = store else { return }
        do {
            let items = try candidates(in: folder)
            gate.retain(keys: Set(items.map(\.key)))
            failureCounts = failureCounts.filter { key, _ in items.contains { $0.version == key } }
            var added = false; var needsSettling = false; var imageFailure: String?
            for item in items {
                if item.capturedAt <= store.manifest.ignoreBefore || store.manifest.contains(sourceKey: item.key, version: item.version) { continue }
                if store.manifest.entries.count == ScreenshotPolicy.capacity,
                   let oldest = store.manifest.entries.last, item.capturedAt < oldest.capturedAt,
                   !store.manifest.entries.contains(where: { $0.sourceKey == item.key }) { continue }
                if (failureCounts[item.version] ?? 0) >= 3 {
                    imageFailure = "An unreadable screenshot was skipped after three attempts. Save it again or add a complete image explicitly."
                    continue
                }
                guard gate.isReady(key: item.key, version: item.version, byteCount: item.byteCount, now: Date(), modifiedAt: item.modifiedAt) else {
                    needsSettling = true; continue
                }
                do {
                    let data = try ScreenshotImages.readStableFile(item.url, expectedSize: item.byteCount)
                    let prepared = try ScreenshotImages.prepare(data)
                    let entry = ScreenshotEntry(sourceKey: item.key, sourceVersion: item.version, name: item.name,
                        capturedAt: item.capturedAt, width: prepared.width, height: prepared.height, byteCount: prepared.png.count)
                    if try store.insert(entry, png: prepared.png) {
                        thumbnails[entry.id] = prepared.thumbnailPNG; added = true
                    }
                } catch {
                    failureCounts[item.version, default: 0] += 1
                    imageFailure = "A screenshot could not be imported: \(error.localizedDescription)"
                }
            }
            pruneThumbnails()
            let normal = "Watching \(folder.lastPathComponent) · \(store.manifest.entries.count)/5 screenshots · tap to copy; ⌘V to paste."
            publish(imageFailure ?? normal, didAdd: added)
            if needsSettling { scheduleScan(after: 0.25) }
        } catch {
            publish("Screenshot folder is unreadable. Choose it again from RB → Screenshot Shelf. \(error.localizedDescription)")
        }
    }
    private func loadThumbnails() {
        guard let store = store else { return }
        for entry in store.manifest.entries {
            if let bytes = try? store.readPNG(id: entry.id), let prepared = try? ScreenshotImages.prepare(bytes) {
                thumbnails[entry.id] = prepared.thumbnailPNG
            }
        }
    }
    private func pruneThumbnails() {
        let ids = Set(store?.manifest.entries.map(\.id) ?? [])
        thumbnails = thumbnails.filter { ids.contains($0.key) }
    }
    private func publish(_ message: String, didAdd: Bool = false) {
        let records = store?.manifest.entries ?? []
        let fullMessage = [message, store?.cleanupWarning].compactMap { $0 }.joined(separator: " ")
        let signature = "\(folder?.path ?? "")|\(records.map { $0.id.uuidString }.joined())|\(fullMessage)"
        guard signature != lastPublished || didAdd else { return }
        lastPublished = signature
        let state = State(entries: records, thumbnails: thumbnails, message: fullMessage, watching: source != nil, didAdd: didAdd)
        DispatchQueue.main.async { [callback] in callback(state) }
    }
}

@MainActor
final class ScreenshotShelfController {
    private(set) var entries: [ScreenshotEntry] = []
    private(set) var thumbnails: [UUID: NSImage] = [:]
    private(set) var message = "Set up your screenshot folder. Five full-resolution images, stored locally."
    private(set) var watching = false
    private(set) var copiedID: UUID?
    var onChange: ((_ didAdd: Bool) -> Void)?
    private var worker: ScreenshotWorker?
    private let defaults = UserDefaults.standard
    private var copyRequest = UUID()
    private let folderKey = "screenshotShelf.folder"
    private let enabledKey = "screenshotShelf.enabled"

    init(directory: URL) {
        worker = ScreenshotWorker(directory: directory) { [weak self] state in
            guard let self = self else { return }
            self.entries = state.entries; self.watching = state.watching; self.message = state.message
            self.thumbnails = state.thumbnails.compactMapValues { NSImage(data: $0) }
            self.onChange?(state.didAdd)
        }
        let explicitlyDisabled = defaults.object(forKey: enabledKey) != nil && !defaults.bool(forKey: enabledKey)
        if !explicitlyDisabled {
            let targetFolder = folderURL ?? suggestedFolder
            if defaults.string(forKey: folderKey) == nil {
                defaults.set(targetFolder.path, forKey: folderKey)
            }
            defaults.set(true, forKey: enabledKey)
            worker?.start(folder: targetFolder)
        }
    }
    var folderURL: URL? { defaults.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } }
    var suggestedFolder: URL {
        if let existing = folderURL { return existing }
        if let configured = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }
    func chooseFolder() {
        let picker = NSOpenPanel()
        picker.title = "Choose the folder where your screenshots are saved"
        picker.message = "RelayBar will read screenshots in this folder and keep the five most recent full-resolution images in its local cache. Originals are never changed. Screenshots stay until replaced by newer ones or you clear the shelf."
        picker.prompt = "Watch screenshots"
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        picker.directoryURL = suggestedFolder
        guard picker.runModal() == .OK, let url = picker.url else { return }
        defaults.set(url.path, forKey: folderKey); defaults.set(true, forKey: enabledKey)
        worker?.start(folder: url)
    }
    func toggleWatching() {
        if watching { defaults.set(false, forKey: enabledKey); worker?.stop() }
        else if let folder = folderURL { defaults.set(true, forKey: enabledKey); worker?.start(folder: folder) }
        else { chooseFolder() }
    }
    func clear() {
        let alert = NSAlert(); alert.messageText = "Clear the five-screenshot shelf?"
        alert.informativeText = "This removes RelayBar's cached images only. Your original screenshot files and the current system clipboard are unchanged. Old files will not refill the shelf; new screenshots will still appear when watching is on."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear shelf")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        copyRequest = UUID(); copiedID = nil; worker?.clear()
    }
    func addClipboardImage() {
        let board = NSPasteboard.general
        let marker = NSPasteboard.PasteboardType("local.relaybar.screenshot-id")
        if let id = board.string(forType: marker), entries.contains(where: { $0.id.uuidString == id }) {
            message = "That screenshot is already on the shelf."; onChange?(false); return
        }
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
        guard let type = board.availableType(from: types), let data = board.data(forType: type), data.count <= ScreenshotPolicy.maximumBytes else {
            message = "No supported clipboard image. Take a screenshot first, then choose Add clipboard image."; onChange?(false); return
        }
        worker?.importClipboard(data)
    }
    func copy(id: UUID) {
        let request = UUID(); copyRequest = request
        message = "Preparing full-resolution screenshot…"; onChange?(false)
        worker?.payload(id: id) { [weak self] result in
            guard let self = self, self.copyRequest == request else { return } // A later tap wins.
            switch result {
            case .success(let payload):
                let board = NSPasteboard.general
                guard Self.write(payload, id: id, to: board) else {
                    self.message = "Could not write the system clipboard. Please tap again."; NSSound.beep(); self.onChange?(false); return
                }
                self.copiedID = id
                self.message = "Image copied at full resolution. Press ⌘V in the intended app. Nothing was pasted or sent."
                self.onChange?(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                    guard let self = self, self.copyRequest == request else { return }
                    self.copiedID = nil; self.onChange?(false)
                }
            case .failure(let error):
                self.message = error.localizedDescription; NSSound.beep(); self.onChange?(false)
            }
        }
    }
    /// Takes an explicit pasteboard so native self-tests use an isolated named board, never General.
    static func write(_ payload: ScreenshotImages.ClipboardPayload, id: UUID, to board: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        guard item.setData(payload.png, forType: .png) else { return false }
        if let tiff = payload.tiff { _ = item.setData(tiff, forType: .tiff) }
        item.setString(id.uuidString, forType: NSPasteboard.PasteboardType("local.relaybar.screenshot-id"))
        board.clearContents()
        return board.writeObjects([item])
    }
    func stopForTermination() { worker?.stop() }
}
