import Cocoa

/// A menu command with its own stable closure, matching ActionButton's ownership.
/// Building a family menu is passive; the closure only runs after an explicit click.
@MainActor
final class FamilyMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, help: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: nil, keyEquivalent: "")
        target = self; action = #selector(run)
        toolTip = help
    }
    required init(coder: NSCoder) { fatalError("Programmatic UI only") }
    @objc private func run() { handler() }
}
