import Foundation

public struct BrowserTab: Identifiable, Equatable, Codable {
    public let id: Int
    public let index: Int
    public let title: String
    public let url: String
    public let isSelected: Bool
    
    public init(id: Int, index: Int, title: String, url: String, isSelected: Bool = false) {
        self.id = id
        self.index = index
        self.title = title
        self.url = url
        self.isSelected = isSelected
    }
    
    public var cleanTitle: String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            if let host = domain, !host.isEmpty { t = host }
            else { t = "New Tab" }
        }
        
        // Strip common browser title suffixes
        let commonSuffixes = [
            " - Google Chrome", " - Google Search", " - GitHub", " — Mozilla Firefox",
            " - YouTube", " - Wikipedia", " - Stack Overflow", " - Google Sheets", " - Google Docs"
        ]
        for s in commonSuffixes {
            if let range = t.range(of: s, options: .backwards) {
                t.removeSubrange(range)
                break
            }
        }
        
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 16 {
            return String(t.prefix(15)) + "…"
        }
        return t.isEmpty ? "Tab" : t
    }
    
    public var domain: String? {
        guard let u = URL(string: url), let host = u.host else { return nil }
        return host.lowercased()
    }
}
