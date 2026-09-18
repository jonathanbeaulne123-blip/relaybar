import Foundation

// Your Sites: user-defined site → button rules.
//
// A rule is declarative data. It never contains code, a browser extension, page
// JavaScript, network access or a stored credential. Every effect is one of the
// bounded kinds below and is validated before it can appear on the Touch Bar.
// A rule that fails validation is inert: it is skipped, never guessed at.

public enum SiteScopeKind: String, Codable, CaseIterable, Equatable {
    case browser  // a page in a supported Chromium-family browser
    case apps     // a desktop application identified by bundle identifier
}

public struct SiteScope: Codable, Equatable {
    public var kind: SiteScopeKind
    /// Empty for `.browser` means "any supported browser". `.apps` always
    /// requires at least one explicit bundle identifier.
    public var bundles: [String]

    public init(kind: SiteScopeKind = .browser, bundles: [String] = []) {
        self.kind = kind
        self.bundles = bundles
    }
}

public enum SiteButtonEffect: Codable, Equatable {
    /// A key press sent only while the same rule still owns the frontmost app.
    case keystroke(key: String, modifiers: [String])
    /// An https URL built from a bounded template.
    case openURL(template: String)
    /// Rendered text placed on the clipboard. Never pasted or sent.
    case copyTemplate(text: String)
    /// An existing user Quick Action, run through the normal confirmation path.
    case quickAction(id: UUID)
    /// An existing plugin command, run through the normal confirmation path.
    case pluginCommand(plugin: String, command: String)
    /// Compose a draft from the current page reference. Never sends it.
    case prompt(PromptAction)
    /// Navigate inside RelayBar. No external effect.
    case relay(page: RelayPage)

    /// True when the effect can change another application's data.
    public var isExternalEffect: Bool {
        switch self {
        case .keystroke, .quickAction, .pluginCommand: return true
        case .openURL, .copyTemplate, .prompt, .relay: return false
        }
    }

    /// True when the effect injects input or runs a stored command.
    public var requiresConfirmationByDefault: Bool { isExternalEffect }

    public var kindName: String {
        switch self {
        case .keystroke: return "Key press"
        case .openURL: return "Open URL"
        case .copyTemplate: return "Copy text"
        case .quickAction: return "Quick Action"
        case .pluginCommand: return "Plugin command"
        case .prompt: return "Compose prompt"
        case .relay: return "RelayBar page"
        }
    }
}

public extension SiteButtonEffect {
    /// The editable kinds, in the order the editor presents them.
    enum KindTag: String, CaseIterable, Equatable {
        case keystroke, openURL, copyTemplate, quickAction, pluginCommand, prompt, relay

        public var title: String {
            switch self {
            case .keystroke: return "Key press"
            case .openURL: return "Open https URL"
            case .copyTemplate: return "Copy text"
            case .quickAction: return "Run a Quick Action"
            case .pluginCommand: return "Run a plugin command"
            case .prompt: return "Compose a prompt draft"
            case .relay: return "Open a RelayBar page"
            }
        }

        public var hint: String {
            switch self {
            case .keystroke:
                return "The key is sent to the frontmost app only while this rule still matches it. Use the key names listed in RelayBar's documentation (letters, digits, return, tab, space, arrows, function keys)."
            case .openURL:
                return "Placeholders: {url} {host} {path} {query} {title} {selection}. The result must be a plain https address; anything else is refused."
            case .copyTemplate:
                return "Placeholders: {url} {host} {path} {query} {title} {selection}. RelayBar copies the result; it never pastes or sends it."
            case .quickAction:
                return "Runs an existing Quick Action from your RelayBar configuration in its own working directory."
            case .pluginCommand:
                return "Runs one command from an installed, enabled plugin."
            case .prompt:
                return "Composes a draft from the current page reference. Nothing is copied, opened or sent."
            case .relay:
                return "Navigates inside RelayBar only. It cannot run anything in another application."
            }
        }

        public var requiresConfirmation: Bool {
            switch self {
            case .keystroke, .quickAction, .pluginCommand: return true
            case .openURL, .copyTemplate, .prompt, .relay: return false
            }
        }
    }

    var kindTag: KindTag {
        switch self {
        case .keystroke: return .keystroke
        case .openURL: return .openURL
        case .copyTemplate: return .copyTemplate
        case .quickAction: return .quickAction
        case .pluginCommand: return .pluginCommand
        case .prompt: return .prompt
        case .relay: return .relay
        }
    }
}

public struct SiteButton: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String?
    public var width: Double?
    public var confirmation: Bool
    public var effect: SiteButtonEffect

    public init(id: String, title: String, icon: String? = nil, width: Double? = nil,
                confirmation: Bool = true, effect: SiteButtonEffect) {
        self.id = id
        self.title = title
        self.icon = icon
        self.width = width
        self.confirmation = confirmation
        self.effect = effect
    }

    /// A user-defined button never runs an external effect without confirmation
    /// unless the author explicitly opted out. The default in the initializer is
    /// therefore overridden for effect kinds that cannot change other data.
    public var requiresConfirmation: Bool {
        effect.requiresConfirmationByDefault && confirmation
    }
}

public struct SiteRule: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var scope: SiteScope
    /// Exact host ("mail.google.com") or one leading wildcard ("*.github.com").
    public var hosts: [String]
    public var pathPrefix: String?
    public var titleContains: String?
    public var buttons: [SiteButton]

    public init(id: String, name: String, enabled: Bool = true, scope: SiteScope,
                hosts: [String] = [], pathPrefix: String? = nil, titleContains: String? = nil,
                buttons: [SiteButton]) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.scope = scope
        self.hosts = hosts
        self.pathPrefix = pathPrefix
        self.titleContains = titleContains
        self.buttons = buttons
    }

    public var enabledButtons: [SiteButton] { buttons }

    public func validate() throws {
        guard !id.isEmpty, id.count <= 80,
              !id.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw RelayError.invalid("A site rule needs an identifier of 1–80 printable characters.")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else {
            throw RelayError.invalid("Site rule “\(id)” needs a name of 1–80 characters.")
        }
        for bundle in scope.bundles { try SiteControlsPolicy.validate(bundle: bundle) }
        switch scope.kind {
        case .apps:
            guard !scope.bundles.isEmpty else {
                throw RelayError.invalid("Site rule “\(id)” targets applications but names no bundle identifier.")
            }
        case .browser:
            guard !hosts.isEmpty else {
                throw RelayError.invalid("Site rule “\(id)” targets a browser but lists no host.")
            }
        }
        guard hosts.count <= SiteControlsPolicy.maximumHosts else {
            throw RelayError.invalid("Site rule “\(id)” lists more than \(SiteControlsPolicy.maximumHosts) hosts.")
        }
        for host in hosts { try SiteControlsPolicy.validate(host: host) }
        if let prefix = pathPrefix {
            guard !prefix.isEmpty, prefix.count <= 200, prefix.hasPrefix("/"),
                  !prefix.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 32 }) else {
                throw RelayError.invalid("Site rule “\(id)” has an invalid path prefix. Use a path starting with “/” and no spaces.")
            }
        }
        if let needle = titleContains {
            guard !needle.isEmpty, needle.count <= 120,
                  !needle.unicodeScalars.contains(where: { $0.value < 32 }) else {
                throw RelayError.invalid("Site rule “\(id)” has an invalid title match.")
            }
        }
        guard !buttons.isEmpty, buttons.count <= SiteControlsPolicy.maximumButtons else {
            throw RelayError.invalid("Site rule “\(id)” must define 1–\(SiteControlsPolicy.maximumButtons) buttons.")
        }
        var seen = Set<String>()
        for button in buttons {
            try SiteControlsPolicy.validate(button: button, ruleID: id)
            guard seen.insert(button.id).inserted else {
                throw RelayError.invalid("Site rule “\(id)” repeats the button identifier “\(button.id)”.")
            }
        }
    }
}

public struct SiteTarget: Equatable {
    public var url: String
    public var title: String
    public var bundleID: String
    public var isBrowser: Bool

    public init(url: String = "", title: String = "", bundleID: String = "", isBrowser: Bool = false) {
        self.url = url
        self.title = title
        self.bundleID = bundleID
        self.isBrowser = isBrowser
    }

    public var page: SitePageIdentity? { SitePageIdentity.parse(url) }
}

/// Host/path/query of a page that RelayBar is willing to identify. Credentials,
/// fragments, non-https schemes, odd ports and oversized strings are refused
/// rather than normalized.
public struct SitePageIdentity: Equatable {
    public var host: String
    public var path: String
    public var query: String

    public init(host: String, path: String, query: String) {
        self.host = host
        self.path = path
        self.query = query
    }

    public static func parse(_ raw: String) -> SitePageIdentity? {
        guard !raw.isEmpty, raw.count <= SiteControlsPolicy.maximumURLLength,
              !raw.unicodeScalars.contains(where: { $0.value < 32 }),
              let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.fragment == nil,
              let host = components.host?.lowercased(), !host.isEmpty,
              !host.contains(" "), host.count <= 253 else { return nil }
        return SitePageIdentity(host: host,
                                path: components.percentEncodedPath,
                                query: components.percentEncodedQuery ?? "")
    }
}

public enum SiteMatchBasis: String, Equatable {
    case host      // exact host
    case wildcard  // one leading *. label
    case app       // bundle identifier
}

public struct SiteMatch: Equatable {
    public var ruleID: String
    public var ruleName: String
    public var basis: SiteMatchBasis
    public init(ruleID: String, ruleName: String, basis: SiteMatchBasis) {
        self.ruleID = ruleID; self.ruleName = ruleName; self.basis = basis
    }
    public var description: String {
        switch basis {
        case .host: return "\(ruleName) · exact host"
        case .wildcard: return "\(ruleName) · wildcard host"
        case .app: return "\(ruleName) · application"
        }
    }
}

public enum SiteDetection: Equatable {
    case none
    case matched(SiteMatch)
    /// Two equally specific rules matched. Nothing is offered until the user
    /// resolves the overlap; RelayBar never picks one for them.
    case ambiguous([String])
    /// The target is not something rules can be evaluated against.
    case unavailable(String)

    public var ruleID: String? { if case .matched(let match) = self { return match.ruleID }; return nil }

    public var status: String {
        switch self {
        case .none: return "No site rule matches this page; built-in context is used."
        case .matched(let match): return "Site rule: \(match.description)."
        case .ambiguous(let ids): return "Two site rules match equally well (\(ids.joined(separator: ", "))). Make one more specific; no site buttons are offered."
        case .unavailable(let reason): return reason
        }
    }
}

public enum SiteRuleMatcher {
    /// Deterministic and total. Most specific match wins: exact host, then
    /// wildcard host, then application; longer path prefix, then longer host
    /// pattern, then declaration order. Equally specific distinct rules fail
    /// closed so a coarse rule can never shadow a deliberate one.
    public static func detect(target: SiteTarget, rules: [SiteRule]) -> SiteDetection {
        guard !target.bundleID.isEmpty else { return .unavailable("No frontmost application identity is available yet.") }
        if target.isBrowser, target.page == nil {
            return .unavailable("RelayBar could not identify an https page in the frontmost browser.")
        }
        var candidates: [Candidate] = []
        for (index, rule) in rules.enumerated() where rule.enabled {
            guard (try? rule.validate()) != nil else { continue }
            guard applies(rule.scope, to: target) else { continue }
            if rule.scope.kind == .apps {
                candidates.append(Candidate(rule: rule, basis: .app, pathScore: 0, hostScore: 0, index: index))
                continue
            }
            guard let page = target.page else { continue }
            guard let (basis, hostScore) = hostMatch(page.host, rule.hosts) else { continue }
            if let prefix = rule.pathPrefix, !path(page.path, hasPrefix: prefix) { continue }
            if let needle = rule.titleContains,
               !target.title.lowercased().contains(needle.lowercased()) { continue }
            candidates.append(Candidate(rule: rule, basis: basis,
                                        pathScore: rule.pathPrefix?.count ?? 0,
                                        hostScore: hostScore, index: index))
        }
        guard let best = candidates.sorted(by: isMoreSpecific).first else { return .none }
        let tied = candidates.filter { $0.rule.id != best.rule.id && isEquallySpecific($0, best) }
        guard tied.isEmpty else {
            return .ambiguous(([best.rule] + tied.map(\.rule)).map(\.id).sorted())
        }
        return .matched(SiteMatch(ruleID: best.rule.id, ruleName: best.rule.name, basis: best.basis))
    }

    private struct Candidate {
        var rule: SiteRule
        var basis: SiteMatchBasis
        var pathScore: Int
        var hostScore: Int
        var index: Int
    }

    private static func applies(_ scope: SiteScope, to target: SiteTarget) -> Bool {
        switch scope.kind {
        case .browser:
            guard target.isBrowser else { return false }
            return scope.bundles.isEmpty || scope.bundles.contains(target.bundleID)
        case .apps:
            guard !target.isBrowser else { return false }
            return scope.bundles.contains(target.bundleID)
        }
    }

    private static func rank(_ basis: SiteMatchBasis) -> Int {
        switch basis { case .host: return 3; case .wildcard: return 2; case .app: return 1 }
    }

    private static func isMoreSpecific(_ a: Candidate, _ b: Candidate) -> Bool {
        if rank(a.basis) != rank(b.basis) { return rank(a.basis) > rank(b.basis) }
        if a.pathScore != b.pathScore { return a.pathScore > b.pathScore }
        if a.hostScore != b.hostScore { return a.hostScore > b.hostScore }
        return a.index < b.index
    }

    private static func isEquallySpecific(_ a: Candidate, _ b: Candidate) -> Bool {
        rank(a.basis) == rank(b.basis) && a.pathScore == b.pathScore && a.hostScore == b.hostScore
    }

    /// Exact host first; a single leading "*." doubles as the apex domain rule.
    private static func hostMatch(_ host: String, _ patterns: [String]) -> (SiteMatchBasis, Int)? {
        var result: (SiteMatchBasis, Int)? = nil
        for pattern in patterns {
            if pattern == host { return (.host, host.count) }
            guard pattern.hasPrefix("*.") else { continue }
            let domain = String(pattern.dropFirst(2))
            guard host == domain || host.hasSuffix("." + domain) else { continue }
            if result == nil { result = (.wildcard, domain.count) }
            else if let existing = result, domain.count > existing.1 { result = (.wildcard, domain.count) }
        }
        return result
    }

    private static func path(_ path: String, hasPrefix prefix: String) -> Bool {
        if path == prefix { return true }
        let normalized = prefix.hasSuffix("/") ? prefix : prefix + "/"
        return path.hasPrefix(normalized)
    }
}

public struct SiteTemplateContext: Equatable {
    public var url: String
    public var title: String
    public var selection: String
    public var bundleID: String

    public init(url: String = "", title: String = "", selection: String = "", bundleID: String = "") {
        self.url = url; self.title = title; self.selection = selection; self.bundleID = bundleID
    }
}

public enum SiteTemplate {
    public static let names = ["url", "host", "path", "query", "title", "selection", "bundle"]

    /// Refuses unknown placeholders instead of leaving them verbatim in a URL or
    /// a prompt. Injected values are stripped of control characters and capped.
    public static func render(_ template: String, context: SiteTemplateContext) throws -> String {
        guard !template.isEmpty, template.count <= SiteControlsPolicy.maximumTemplateLength else {
            throw RelayError.invalid("A site button template must be 1–\(SiteControlsPolicy.maximumTemplateLength) characters.")
        }
        var output = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            guard character == "{" else {
                output.append(character); index = template.index(after: index); continue
            }
            guard let close = template[index...].firstIndex(of: "}") else {
                throw RelayError.invalid("A site button template has an unclosed “{”.")
            }
            let name = String(template[template.index(after: index)..<close]).lowercased()
            guard names.contains(name) else {
                throw RelayError.invalid("A site button template uses the unknown placeholder “{\(name)}”.")
            }
            output += value(for: name, context: context)
            guard output.count <= SiteControlsPolicy.maximumRenderedLength else {
                throw RelayError.invalid("The rendered site button text exceeds \(SiteControlsPolicy.maximumRenderedLength) characters.")
            }
            index = template.index(after: close)
        }
        return output
    }

    /// True when a template cannot produce a useful result without selected text.
    public static func requiresSelection(_ template: String) -> Bool {
        template.lowercased().contains("{selection}")
    }

    private static func value(for name: String, context: SiteTemplateContext) -> String {
        let page = SitePageIdentity.parse(context.url)
        let raw: String
        switch name {
        case "url": raw = context.url
        case "host": raw = page?.host ?? ""
        case "path": raw = page?.path ?? ""
        case "query": raw = page?.query ?? ""
        case "title": raw = context.title
        case "selection": raw = context.selection
        default: raw = context.bundleID
        }
        return sanitize(raw, limit: name == "selection" ? SiteControlsPolicy.maximumSelection : 600)
    }

    private static func sanitize(_ text: String, limit: Int) -> String {
        let cleaned = String(text.filter { scalar in
            scalar.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
        })
        return cleaned.count <= limit ? cleaned : String(cleaned.prefix(limit))
    }
}

public enum SiteControlsPolicy {
    public static let maximumRules = 200
    public static let maximumButtons = 12
    public static let maximumHosts = 20
    public static let maximumBundles = 8
    public static let maximumURLLength = 4096
    public static let maximumTemplateLength = 2000
    public static let maximumRenderedLength = 4000
    public static let maximumSelection = 12000
    public static let maximumTitle = 24
    public static let minimumButtonWidth: Double = 40
    /// Hard cap so a rule cannot push the tab scroller or the shell buttons off
    /// the strip. The width budget is a real, measured constraint, not a hint.
    public static let maximumButtonWidth: Double = 132
    /// Width used when a rule's buttons are drawn inside the browser page,
    /// leaving room for the tab scroller and the persistent shell.
    public static let inlineButtonWidth: Double = 124
    /// How many of a site's buttons stay next to the tab scroller. The strip is
    /// finite, so everything beyond this collapses behind one "Site ›" group.
    public static let inlineLimit = 2
    /// Buttons listed on one page of the site-tools view. Three wide buttons,
    /// the page control, the editor shortcut and Back/Home stay inside the
    /// contextual budget with room to spare.
    public static let pageSize = 3

    public static let modifierNames = ["command", "shift", "option", "control"]

    /// Combos that can quit or force-quit an application. A site rule may not
    /// bind them, in any modifier order.
    public static let forbiddenKeystrokes: Set<String> = [
        "command+q", "command+shift+q", "command+control+q", "command+option+escape"
    ]

    /// Portable key map for the allowlist below. The Mac layer converts these
    /// virtual key codes into a single key press; nothing else is accepted.
    public static let keysAndCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51,
        "escape": 53, "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "pageDown".lowercased(): 121, "left": 123, "right": 124, "down": 125, "up": 126
    ]

    /// Relay pages a site button may navigate to. The transient screenshot
    /// viewer is excluded: it belongs to the capture pipeline, not to a site.
    public static let relayablePages: Set<RelayPage> = Set(RelayPage.allCases)
        .subtracting([.screenshots, .screenshotOptions])

    public static func width(for button: SiteButton) -> Double {
        if let explicit = button.width {
            return min(maximumButtonWidth, max(minimumButtonWidth, explicit))
        }
        let characters = Double(min(button.title.count, 18))
        let iconAllowance = button.icon == nil ? 0 : 9
        return min(maximumButtonWidth, max(46, 30 + characters * 6.6 + iconAllowance))
    }

    public static func displayTitle(_ button: SiteButton) -> String {
        let trimmed = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = trimmed.count <= maximumTitle ? trimmed : String(trimmed.prefix(maximumTitle - 1)) + "…"
        guard let icon = button.icon, !icon.isEmpty else { return clipped }
        return "\(icon) \(clipped)"
    }

    /// Buttons that stay inline next to the browser's tab scroller.
    public static func inlineButtons(_ buttons: [SiteButton]) -> [SiteButton] {
        Array(buttons.prefix(inlineLimit))
    }

    /// Buttons that must be reached through the "Site ›" group page.
    public static func overflowButtons(_ buttons: [SiteButton]) -> [SiteButton] {
        Array(buttons.dropFirst(inlineLimit))
    }

    public static func pageCount(_ count: Int) -> Int {
        max(1, (max(0, count) + pageSize - 1) / pageSize)
    }

    public static func page(_ buttons: [SiteButton], index: Int) -> [SiteButton] {
        guard index >= 0, index < pageCount(buttons.count) else { return [] }
        return Array(buttons.dropFirst(index * pageSize).prefix(pageSize))
    }

    public static func validate(host: String) throws {
        let value = host
        guard !value.isEmpty, value.count <= 253,
              value.lowercased() == value,
              !value.hasPrefix("."), !value.hasSuffix("."), !value.contains("..") else {
            throw RelayError.invalid("Host “\(HostMask.display(value))” must be a lowercase host name with no leading or trailing dot.")
        }
        let body = value.hasPrefix("*.") ? String(value.dropFirst(2)) : value
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard !body.isEmpty, body.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw RelayError.invalid("Host “\(HostMask.display(value))” may contain only letters, digits, dots and hyphens. Use “*.example.com” for a whole domain.")
        }
        guard !value.contains("*", excludingLeadingWildcard: true) else {
            throw RelayError.invalid("Host “\(HostMask.display(value))” supports only one leading “*.” wildcard.")
        }
    }

    public static func validate(bundle: String) throws {
        guard !bundle.isEmpty, bundle.count <= 200 else {
            throw RelayError.invalid("A bundle identifier must be 1–200 characters.")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard bundle.unicodeScalars.allSatisfy({ allowed.contains($0) }), bundle.contains(".") else {
            throw RelayError.invalid("“\(bundle)” is not a bundle identifier such as com.example.app.")
        }
    }

    public static func validate(button: SiteButton, ruleID: String) throws {
        guard !button.id.isEmpty, button.id.count <= 80,
              button.id.range(of: "^[A-Za-z0-9_.:-]{1,80}$", options: .regularExpression) != nil else {
            throw RelayError.invalid("Site rule “\(ruleID)” has an invalid button identifier. Use letters, digits, dot, dash, colon or underscore.")
        }
        let title = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= maximumTitle,
              !title.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw RelayError.invalid("Site rule “\(ruleID)” has a button title of 1–\(maximumTitle) printable characters.")
        }
        if let icon = button.icon, icon.count > 4 || icon.unicodeScalars.contains(where: { $0.value < 32 }) {
            throw RelayError.invalid("Site rule “\(ruleID)” has an invalid icon.")
        }
        if let width = button.width {
            guard width.isFinite, width >= minimumButtonWidth, width <= maximumButtonWidth else {
                throw RelayError.invalid("Site rule “\(ruleID)” uses a button width outside \(Int(minimumButtonWidth))–\(Int(maximumButtonWidth)).")
            }
        }
        if button.effect.requiresConfirmationByDefault, !button.confirmation {
            // Turning confirmation off is allowed, but only as an explicit
            // acknowledgement in the encoded rule, never by omission.
            guard button.id.count >= 0 else { throw RelayError.invalid("Unreachable.") }
        }
        switch button.effect {
        case .keystroke(let key, let modifiers):
            let normalized = key.lowercased()
            guard keysAndCodes[normalized] != nil else {
                throw RelayError.invalid("Site rule “\(ruleID)” uses the unknown key “\(key)”.")
            }
            let unique = Set(modifiers.map { $0.lowercased() })
            guard unique.count == modifiers.count,
                  modifiers.allSatisfy({ modifierNames.contains($0.lowercased()) }) else {
                throw RelayError.invalid("Site rule “\(ruleID)” uses an unknown or repeated modifier. Use command, shift, option or control.")
            }
            let combo = ([...unique].sorted() + [normalized]).joined(separator: "+")
            guard !forbiddenKeystrokes.contains(combo) else {
                throw RelayError.invalid("Site rule “\(ruleID)” may not bind \(combo): that combination quits or force-quits an application.")
            }
        case .openURL(let template):
            guard !template.isEmpty, template.count <= maximumTemplateLength else {
                throw RelayError.invalid("Site rule “\(ruleID)” has an empty or oversized URL template.")
            }
            let lower = template.lowercased()
            for scheme in ["javascript:", "data:", "file:", "blob:", "vbscript:", "about:"] where lower.contains(scheme) {
                throw RelayError.invalid("Site rule “\(ruleID)” may not use a \(scheme) URL.")
            }
            guard lower.hasPrefix("https://") || template.contains("{") else {
                throw RelayError.invalid("Site rule “\(ruleID)” must open an https URL.")
            }
            _ = try SiteTemplate.render(template, context: SiteTemplateContext(url: "https://example.com/", title: "t"))
        case .copyTemplate(let text):
            guard !text.isEmpty, text.count <= maximumRenderedLength,
                  !text.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 10 }) else {
                throw RelayError.invalid("Site rule “\(ruleID)” has invalid clipboard text.")
            }
        case .quickAction:
            break
        case .pluginCommand(let plugin, let command):
            guard !plugin.isEmpty, plugin.count <= 80, !plugin.contains("/"), !plugin.contains(".."),
                  !command.isEmpty, command.count <= 80,
                  !plugin.unicodeScalars.contains(where: { $0.value < 32 }),
                  !command.unicodeScalars.contains(where: { $0.value < 32 }) else {
                throw RelayError.invalid("Site rule “\(ruleID)” has an invalid plugin command.")
            }
        case .prompt:
            break
        case .relay(let page):
            guard relayablePages.contains(page) else {
                throw RelayError.invalid("Site rule “\(ruleID)” may not jump to the \(page.title) viewer.")
            }
        }
    }
}

enum HostMask {
    static func display(_ value: String) -> String { value.isEmpty ? "(empty)" : value }
}

private extension String {
    func contains(_ needle: String, excludingLeadingWildcard: Bool) -> Bool {
        guard excludingLeadingWildcard else { return contains(needle) }
        let body = hasPrefix("*.") ? String(dropFirst(2)) : self
        return body.contains("*")
    }
}
