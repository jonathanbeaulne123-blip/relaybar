import Cocoa

@MainActor
public final class HotkeyController {
    private let bridge: RBBridge
    public var onHotkeyTriggered: (() -> Void)?
    public private(set) var isRegistered = false
    
    public init(bridge: RBBridge) {
        self.bridge = bridge
        self.bridge.launcherHandler = { [weak self] in
            self?.onHotkeyTriggered?()
        }
    }
    
    @discardableResult
    public func register() -> Bool {
        isRegistered = bridge.registerLauncherHotKey()
        return isRegistered
    }
    
    public func unregister() {
        bridge.unregisterLauncherHotKey()
        isRegistered = false
    }
}
