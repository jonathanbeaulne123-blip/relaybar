import Foundation

/// UI-independent auto-open rules. This never captures an image, changes focus,
/// enables cross-app mode, or touches a clipboard. AppKit executes the actions.
public struct ScreenshotPresentationState {
    public enum Page: Equatable { case tools, screenshots }
    public enum OverlayAction: Equatable { case dismiss, present, reopen }

    /// A bounded recovery window, not a timer that continuously takes over the bar.
    public static let recoveryDelays: [TimeInterval] = [0.35, 1.0, 2.0]
    public private(set) var page: Page = .screenshots
    public private(set) var autoOpenEnabled: Bool
    public private(set) var needsOverlayReopen = false
    public private(set) var recoveryTicket: UUID?

    public init(autoOpenEnabled: Bool = true) {
        self.autoOpenEnabled = autoOpenEnabled
    }

    /// Call only after a new, complete image has been committed to the shelf.
    /// Routine watcher updates and copy feedback must NOT call this method.
    @discardableResult
    public mutating func screenshotAdded() -> UUID? {
        guard autoOpenEnabled else { return nil }
        page = .screenshots
        needsOverlayReopen = true
        let ticket = UUID()
        recoveryTicket = ticket
        return ticket
    }

    public mutating func showScreenshots() {
        cancelRecovery(); page = .screenshots; needsOverlayReopen = true
    }
    public mutating func showTools() {
        cancelRecovery(); page = .tools; needsOverlayReopen = true
    }
    public mutating func setAutoOpenEnabled(_ enabled: Bool) {
        autoOpenEnabled = enabled
        if !enabled { cancelRecovery() }
    }
    public mutating func cancelRecovery() { recoveryTicket = nil }
    public mutating func overlayDisabled() {
        cancelRecovery(); needsOverlayReopen = false
    }
    public mutating func layoutChanged() { needsOverlayReopen = true }

    /// A superseded capture or explicit user action invalidates older callbacks.
    @discardableResult
    public mutating func requestRecovery(ticket: UUID) -> Bool {
        guard autoOpenEnabled, page == .screenshots, recoveryTicket == ticket else { return false }
        needsOverlayReopen = true
        return true
    }

    /// `eligibleApp` is determined from the CURRENT frontmost app by the adapter.
    /// It is false for RelayBar itself, Screenshot, and apps outside the allowlist.
    /// Keep the pending reopen across a temporary ineligible app; don't steal focus.
    public func overlayAction(overlayEnabled: Bool, eligibleApp: Bool) -> OverlayAction {
        guard overlayEnabled, eligibleApp else { return .dismiss }
        return needsOverlayReopen ? .reopen : .present
    }
    public mutating func overlayPresented() { needsOverlayReopen = false }
}
