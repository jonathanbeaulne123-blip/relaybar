import Foundation

public enum WebsiteTarget: String, CaseIterable, Codable {
    case sheets   // Google Sheets spreadsheet editor
    case none     // Fallback to Website Tabs view
}

public enum WebsiteDispatcher {
    public static func target(for url: String) -> WebsiteTarget {
        let lower = url.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("docs.google.com/spreadsheets") || lower.contains("script.google.com") {
            return .sheets
        }
        let site = NativeMenuPolicy.site(url)
        if site == .sheets {
            return .sheets
        }
        return .none
    }
}
