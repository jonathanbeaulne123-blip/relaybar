import Cocoa
import Foundation
import SQLite3

@MainActor
public final class FaviconProvider {
    public static let shared = FaviconProvider()
    
    private var cache: [String: NSImage] = [:]
    private let queue = DispatchQueue(label: "local.relaybar.favicon-loader", qos: .userInitiated)
    
    private init() {}
    
    public func favicon(for urlString: String, domain: String? = nil) -> NSImage {
        let key = domain?.lowercased() ?? urlString.lowercased()
        if let cached = cache[key] {
            return cached
        }
        
        // 1. Try reading from Chrome's SQLite Favicons database
        if let image = loadFromChromeDB(for: urlString, domain: domain) {
            let resized = resize(image: image, to: NSSize(width: 16, height: 16))
            cache[key] = resized
            return resized
        }
        
        // 2. Generate high-fidelity domain icon
        let generated = generateDomainIcon(for: urlString, domain: domain)
        cache[key] = generated
        return generated
    }
    
    private func loadFromChromeDB(for urlString: String, domain: String?) -> NSImage? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbCandidates = [
            "\(home)/Library/Application Support/Google/Chrome/Default/Favicons",
            "\(home)/Library/Application Support/Google/Chrome/Profile 1/Favicons",
            "\(home)/Library/Application Support/Google/Chrome/Profile 2/Favicons",
            "\(home)/Library/Application Support/BraveSoftware/Brave-Browser/Default/Favicons"
        ]
        
        let searchTerm = domain ?? urlString
        guard !searchTerm.isEmpty else { return nil }
        
        for path in dbCandidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let uri = "file:\(path)?immutable=1"
            var db: OpaquePointer?
            guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
                continue
            }
            defer { sqlite3_close(db) }
            
            var stmt: OpaquePointer?
            let query = """
            SELECT b.image_data FROM icon_mapping m 
            JOIN favicon_bitmaps b ON m.icon_id = b.icon_id 
            WHERE m.page_url LIKE ? 
            ORDER BY b.width DESC, b.last_updated DESC LIMIT 1;
            """
            
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                let bindPattern = "%\(searchTerm)%"
                sqlite3_bind_text(stmt, 1, (bindPattern as NSString).utf8String, -1, nil)
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let bytes = sqlite3_column_bytes(stmt, 0)
                    if let blob = sqlite3_column_blob(stmt, 0), bytes > 0 {
                        let data = Data(bytes: blob, count: Int(bytes))
                        sqlite3_finalize(stmt)
                        if let img = NSImage(data: data) {
                            return img
                        }
                    }
                }
                sqlite3_finalize(stmt)
            }
        }
        return nil
    }
    
    private func generateDomainIcon(for urlString: String, domain: String?) -> NSImage {
        let lower = (domain ?? urlString).lowercased()
        
        if lower.contains("docs.google.com/spreadsheets") || lower.contains("sheets") {
            return drawBadge(symbolName: "tablecells.fill", tintColor: NSColor(calibratedRed: 0.06, green: 0.62, blue: 0.35, alpha: 1.0))
        } else if lower.contains("docs.google.com/document") || lower.contains("docs") {
            return drawBadge(symbolName: "doc.text.fill", tintColor: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.0))
        } else if lower.contains("docs.google.com/presentation") || lower.contains("slides") {
            return drawBadge(symbolName: "rectangle.fill.on.rectangle.fill", tintColor: NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.11, alpha: 1.0))
        } else if lower.contains("drive.google.com") {
            return drawBadge(symbolName: "shippingbox.fill", tintColor: NSColor(calibratedRed: 0.26, green: 0.52, blue: 0.96, alpha: 1.0))
        } else if lower.contains("github.com") {
            return drawBadge(symbolName: "chevron.left.forwardslash.chevron.right", tintColor: .white)
        } else if lower.contains("youtube.com") {
            return drawBadge(symbolName: "play.rectangle.fill", tintColor: NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        } else if lower.contains("chatgpt.com") || lower.contains("openai.com") {
            return drawBadge(symbolName: "bubble.left.and.bubble.right.fill", tintColor: NSColor(calibratedRed: 0.06, green: 0.65, blue: 0.53, alpha: 1.0))
        } else if lower.contains("claude.ai") || lower.contains("anthropic.com") {
            return drawBadge(symbolName: "sparkles", tintColor: NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.18, alpha: 1.0))
        } else if lower.contains("reddit.com") {
            return drawBadge(symbolName: "message.circle.fill", tintColor: NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.0, alpha: 1.0))
        } else if lower.contains("stackoverflow.com") {
            return drawBadge(symbolName: "square.stack.3d.down.right.fill", tintColor: NSColor(calibratedRed: 0.95, green: 0.50, blue: 0.13, alpha: 1.0))
        } else if lower.contains("twitter.com") || lower.contains("x.com") {
            return drawBadge(symbolName: "xmark", tintColor: .white)
        }
        
        // Default clean globe
        return drawBadge(symbolName: "globe", tintColor: NSColor(calibratedWhite: 0.85, alpha: 1.0))
    }
    
    private func drawBadge(symbolName: String, tintColor: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        
        if #available(macOS 11.0, *) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                tintColor.set()
                let rect = NSRect(x: 1, y: 1, width: 14, height: 14)
                symbol.draw(in: rect)
                image.unlockFocus()
                image.isTemplate = false
                return image
            }
        }
        
        // Fallback drawing if SF symbol not available
        tintColor.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12))
        path.fill()
        
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
    
    private func resize(image: NSImage, to newSize: NSSize) -> NSImage {
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        resized.isTemplate = false
        return resized
    }
}
