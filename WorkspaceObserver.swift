import Cocoa

@MainActor
public final class WorkspaceObserver {
    private var observer: NSObjectProtocol?
    public var onApplicationActivated: ((NSRunningApplication) -> Void)?
    
    public init() {}
    
    public func startObserving() {
        stopObserving()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.onApplicationActivated?(app)
        }
    }
    
    public func stopObserving() {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            observer = nil
        }
    }
    
    deinit {
        if let obs = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}
