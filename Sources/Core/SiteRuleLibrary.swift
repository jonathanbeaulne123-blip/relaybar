import Foundation

// The starter rules shipped with RelayBar. They are ordinary editable rules, not
// a privileged layer: removing one fully removes the behavior.
//
// Deliberate choices:
// - No Google Docs or Sheets starter. Those keep their existing dedicated
//   contexts (docs buttons, and the native Sheets menu path).
// - No bare-letter keystrokes. Only modifier-based shortcuts are shipped, so a
//   starter button cannot type a stray character into a focused text field.

public extension SiteRule {
    static let starters: [SiteRule] = [
        gmail, googleDrive, googleCalendar, googleMeet, github, stackOverflow, mdn, appleDeveloper,
        claudeDesktop, chatgptDesktop
    ]

    static let gmail = SiteRule(
        id: "gmail", name: "Gmail",
        scope: SiteScope(kind: .browser),
        hosts: ["mail.google.com"],
        buttons: [
            SiteButton(id: "gmail.inbox", title: "Inbox", icon: "📥",
                       effect: .openURL(template: "https://mail.google.com/mail/u/0/#inbox")),
            SiteButton(id: "gmail.compose", title: "Compose", icon: "✉️",
                       effect: .openURL(template: "https://mail.google.com/mail/u/0/?view=cm&fs=1&tf=1")),
            SiteButton(id: "gmail.calendar", title: "Calendar", icon: "📅",
                       effect: .openURL(template: "https://calendar.google.com/calendar/r/week")),
            SiteButton(id: "gmail.ask", title: "Ask", icon: "💬",
                       effect: .prompt(.explain))
        ])

    static let googleDrive = SiteRule(
        id: "gdrive", name: "Google Drive",
        scope: SiteScope(kind: .browser),
        hosts: ["drive.google.com"],
        buttons: [
            SiteButton(id: "drive.my", title: "My Drive",
                       effect: .openURL(template: "https://drive.google.com/drive/my-drive")),
            SiteButton(id: "drive.recent", title: "Recent",
                       effect: .openURL(template: "https://drive.google.com/drive/recent")),
            SiteButton(id: "drive.shared", title: "Shared",
                       effect: .openURL(template: "https://drive.google.com/drive/shared-with-me")),
            SiteButton(id: "drive.ask", title: "Ask", icon: "💬", effect: .prompt(.explain))
        ])

    static let googleCalendar = SiteRule(
        id: "gcal", name: "Google Calendar",
        scope: SiteScope(kind: .browser),
        hosts: ["calendar.google.com"],
        buttons: [
            SiteButton(id: "gcal.today", title: "Today",
                       effect: .openURL(template: "https://calendar.google.com/calendar/r/day")),
            SiteButton(id: "gcal.event", title: "New event", icon: "➕",
                       effect: .openURL(template: "https://calendar.google.com/calendar/r/eventedit")),
            SiteButton(id: "gcal.meet", title: "Meet", icon: "🎥",
                       effect: .openURL(template: "https://meet.google.com/")),
            SiteButton(id: "gcal.ask", title: "Ask", icon: "💬", effect: .prompt(.explain))
        ])

    static let googleMeet = SiteRule(
        id: "gmeet", name: "Google Meet",
        scope: SiteScope(kind: .browser),
        hosts: ["meet.google.com"],
        buttons: [
            SiteButton(id: "meet.new", title: "New meeting", icon: "🎥",
                       effect: .openURL(template: "https://meet.google.com/new")),
            SiteButton(id: "meet.schedule", title: "Schedule", icon: "📅",
                       effect: .openURL(template: "https://calendar.google.com/calendar/r/eventedit?add=meet")),
            SiteButton(id: "meet.ask", title: "Ask", icon: "💬", effect: .prompt(.explain))
        ])

    static let github = SiteRule(
        id: "github", name: "GitHub",
        scope: SiteScope(kind: .browser),
        hosts: ["github.com"],
        buttons: [
            SiteButton(id: "github.prs", title: "PRs", icon: "🐙",
                       effect: .openURL(template: "https://github.com/pulls")),
            SiteButton(id: "github.issues", title: "Issues", icon: "📋",
                       effect: .openURL(template: "https://github.com/issues")),
            SiteButton(id: "github.ask", title: "Ask", icon: "💬", effect: .prompt(.explain)),
            SiteButton(id: "github.copy", title: "Copy link", effect: .copyTemplate(text: "{title}\n{url}"))
        ])

    static let stackOverflow = SiteRule(
        id: "stackoverflow", name: "Stack Overflow",
        scope: SiteScope(kind: .browser),
        hosts: ["stackoverflow.com", "*.stackexchange.com", "superuser.com", "serverfault.com"],
        buttons: [
            SiteButton(id: "so.search", title: "Search sel", icon: "🔎",
                       effect: .openURL(template: "https://stackoverflow.com/search?q={selection}")),
            SiteButton(id: "so.ask", title: "Ask", icon: "💬", effect: .prompt(.explain)),
            SiteButton(id: "so.copy", title: "Copy link", effect: .copyTemplate(text: "{title}\n{url}"))
        ])

    static let mdn = SiteRule(
        id: "mdn", name: "MDN",
        scope: SiteScope(kind: .browser),
        hosts: ["developer.mozilla.org"],
        buttons: [
            SiteButton(id: "mdn.search", title: "Search sel", icon: "🔎",
                       effect: .openURL(template: "https://developer.mozilla.org/en-US/search?q={selection}")),
            SiteButton(id: "mdn.ask", title: "Ask", icon: "💬", effect: .prompt(.explain)),
            SiteButton(id: "mdn.copy", title: "Copy link", effect: .copyTemplate(text: "{title}\n{url}"))
        ])

    static let appleDeveloper = SiteRule(
        id: "apple-docs", name: "Apple Developer",
        scope: SiteScope(kind: .browser),
        hosts: ["developer.apple.com"],
        buttons: [
            SiteButton(id: "apple.search", title: "Search sel", icon: "🔎",
                       effect: .openURL(template: "https://developer.apple.com/search/?q={selection}")),
            SiteButton(id: "apple.ask", title: "Ask", icon: "💬", effect: .prompt(.explain)),
            SiteButton(id: "apple.copy", title: "Copy link", effect: .copyTemplate(text: "{title}\n{url}"))
        ])

    /// Desktop assistants are matched by bundle identifier, not by URL. These
    /// rules use RelayBar's own local tools and never drive the other app.
    static let claudeDesktop = SiteRule(
        id: "claude-desktop", name: "Claude desktop",
        scope: SiteScope(kind: .apps, bundles: ["com.anthropic.claudefordesktop"]),
        buttons: [
            SiteButton(id: "claude.ask", title: "Ask", icon: "💬", effect: .prompt(.explain)),
            SiteButton(id: "claude.capture", title: "Capture ›", effect: .relay(page: .capture)),
            SiteButton(id: "claude.draft", title: "Draft ›", effect: .relay(page: .draft)),
            SiteButton(id: "claude.pins", title: "Pins ›", effect: .relay(page: .pins))
        ])

    static let chatgptDesktop = SiteRule(
        id: "chatgpt-desktop", name: "ChatGPT desktop",
        scope: SiteScope(bundles: ["com.openai.chat"]).withKind(.apps),
        buttons: [
            SiteButton(id: "chatgpt.ask", title: "Ask", icon: "💬", effect: .prompt(.explain)),
            SiteButton(id: "chatgpt.capture", title: "Capture ›", effect: .relay(page: .capture)),
            SiteButton(id: "chatgpt.draft", title: "Draft ›", effect: .relay(page: .draft)),
            SiteButton(id: "chatgpt.pins", title: "Pins ›", effect: .relay(page: .pins))
        ])
}

private extension SiteScope {
    func withKind(_ kind: SiteScopeKind) -> SiteScope { SiteScope(kind: kind, bundles: bundles) }
}
