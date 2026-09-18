import Foundation

// Ask about this page: turns the page RelayBar can already identify into the
// reference text used by the existing prompt pipeline. Nothing here sends,
// copies or pastes anything. Link mode needs no extra permission at all.

public enum PageContextMode: String, Codable, CaseIterable, Equatable {
    /// URL and title only. Available wherever a page identity is available.
    case link
    /// The link plus the text you have selected, read once, when you ask.
    case selection
    /// The link plus a bounded read-only text excerpt from the page.
    case excerpt

    public var title: String {
        switch self {
        case .link: return "Link only"
        case .selection: return "Link + selection"
        case .excerpt: return "Link + excerpt"
        }
    }

    public var help: String {
        switch self {
        case .link: return "Use the page URL and title. No additional macOS permission is involved."
        case .selection: return "Add the passage currently selected in the page, read only when you ask."
        case .excerpt: return "Add a bounded read-only text excerpt from the page. Refused on sites RelayBar treats as sensitive."
        }
    }
}

public struct PageContextInput: Equatable {
    public var url: String
    public var title: String
    public var selection: String
    public var excerpt: String

    public init(url: String = "", title: String = "", selection: String = "", excerpt: String = "") {
        self.url = url; self.title = title; self.selection = selection; self.excerpt = excerpt
    }
}

public struct PageContextReference: Equatable {
    public var text: String
    public var origin: String
    public var mode: PageContextMode
    public var host: String

    public init(text: String, origin: String, mode: PageContextMode, host: String) {
        self.text = text; self.origin = origin; self.mode = mode; self.host = host
    }
}

public enum PageContextPolicy {
    public static let maximumTitle = 300
    public static let maximumSelection = SiteControlsPolicy.maximumSelection
    public static let maximumExcerpt = 8000

    /// Sites where RelayBar refuses to read page text, independently of the
    /// user's own mode setting. Short keywords match a whole host label so
    /// "tax" cannot silence an unrelated host that merely contains those
    /// letters; longer keywords match a label substring.
    public static let sensitiveKeywords: [String] = [
        "bank", "paypal", "venmo", "coinbase", "binance", "kraken", "schwab", "fidelity",
        "vanguard", "robinhood", "revolut", "wealthsimple", "1password", "lastpass",
        "bitwarden", "dashlane", "health", "patient", "medical", "medicare", "medicaid",
        "mychart", "irs", "tax", "wallet", "insurance"
    ]

    public static func allowsExcerpt(host: String) -> Bool {
        guard !host.isEmpty else { return false }
        let labels = host.lowercased().split(separator: ".").map(String.init)
        for keyword in sensitiveKeywords {
            for label in labels {
                if keyword.count <= 4 {
                    if label == keyword { return false }
                } else if label.contains(keyword) {
                    return false
                }
            }
        }
        return true
    }

    /// Builds the reference text for the prompt pipeline. Failure is explicit:
    /// a requested mode that cannot be honored is reported, never silently
    /// downgraded to a weaker reference.
    public static func build(_ input: PageContextInput, mode: PageContextMode) throws -> PageContextReference {
        let page = SitePageIdentity.parse(input.url)
        let rawTitle = normalize(input.title)
        let title = rawTitle.count <= maximumTitle
            ? rawTitle
            : String(rawTitle.prefix(maximumTitle - 1)) + "…"
        guard page != nil || !title.isEmpty else {
            throw RelayError.invalid("Focus a browser tab or a supported assistant first; there is no page to reference.")
        }
        var lines: [String] = []
        lines.append("Page: " + (title.isEmpty ? (page?.host ?? "Unknown page") : title))
        if let page = page {
            lines.append("URL: " + input.url.trimmingCharacters(in: .whitespacesAndNewlines))
            if !page.query.isEmpty { lines.append("Query: " + normalize(page.query)) }
        } else {
            lines.append("URL: (not available for this application)")
        }
        switch mode {
        case .link:
            break
        case .selection:
            let selection = try bounded(input.selection, atMost: maximumSelection,
                                        message: "The selection exceeds \(maximumSelection) characters. Shorten it, or switch this context to Link only. Nothing was truncated.")
            guard !selection.isEmpty else {
                throw RelayError.invalid("No text is selected in the page. Select a passage, or switch this context to Link only.")
            }
            lines.append("")
            lines.append("Selected passage:")
            lines.append(selection)
        case .excerpt:
            guard let host = page?.host else {
                throw RelayError.invalid("Excerpt mode needs an identified https page in a supported browser.")
            }
            guard allowsExcerpt(host: host) else {
                throw RelayError.invalid("RelayBar refuses to read page text on \(host). Switch this context to Link only, or use Link + selection.")
            }
            let excerpt = try bounded(input.excerpt, atMost: maximumExcerpt,
                                      message: "The page excerpt exceeds \(maximumExcerpt) characters. RelayBar will not truncate it silently; switch this context to Link only.")
            guard !excerpt.isEmpty else {
                throw RelayError.invalid("RelayBar could not read a bounded excerpt from this page. Nothing was truncated or guessed.")
            }
            lines.append("")
            lines.append("Excerpt:")
            lines.append(excerpt)
        }
        let text = lines.joined(separator: "\n")
        guard text.count <= Limits.reference else {
            throw RelayError.invalid("This page reference exceeds \(Limits.reference) characters. Switch to Link only, or shorten the selection. Nothing was truncated.")
        }
        let origin = "Page: " + (page?.host ?? title)
        return PageContextReference(text: text, origin: String(origin.prefix(300)), mode: mode, host: page?.host ?? "")
    }

    private static func normalize(_ text: String) -> String {
        String(text.filter { scalar in
            scalar.unicodeScalars.allSatisfy { ($0.value >= 32 || $0.value == 10) && $0.value != 127 }
        }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bounded(_ text: String, atMost limit: Int, message: String) throws -> String {
        let cleaned = normalize(text)
        guard cleaned.count <= limit else { throw RelayError.invalid(message) }
        return cleaned
    }
}
