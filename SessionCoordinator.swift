import Cocoa

@MainActor
public final class SessionCoordinator {
    public private(set) var capture = Capture.empty
    public private(set) var draft: PromptDraft?
    public var currentAction: PromptAction = .nextSlice
    public var currentTask: String = ""
    public var onChange: (() -> Void)?
    
    private let store: LocalStore?
    
    public init(store: LocalStore?) {
        self.store = store
    }
    
    public func applyCapture(text: String, origin: String) throws {
        let candidate = Capture(text: text, origin: origin)
        try Limits.validate(capture: candidate, task: currentTask)
        self.capture = candidate
        self.draft = nil
        onChange?()
    }
    
    public func clearSession() {
        capture = .empty
        draft = nil
        currentTask = ""
        onChange?()
    }
    
    public func compose(project: ProjectBrief, target: AssistantTarget) throws -> PromptDraft {
        let composed = try PromptEngine.compose(
            action: currentAction,
            project: project,
            capture: capture,
            task: currentTask,
            target: target
        )
        self.draft = composed
        onChange?()
        return composed
    }
    
    public func updateDraftText(_ text: String) {
        draft?.text = text
    }
    
    public func saveCheckpoint(project: ProjectBrief) throws -> URL {
        guard let store = store else { throw RelayError.invalid("Local storage is unavailable.") }
        guard let draft = draft else { throw RelayError.invalid("No draft to save in checkpoint.") }
        let checkpoint = Checkpoint(project: project, capture: capture, task: currentTask, draft: draft)
        return try store.saveCheckpoint(checkpoint)
    }
    
    public func loadCheckpoint(_ checkpoint: Checkpoint) {
        self.capture = checkpoint.capture
        self.draft = checkpoint.draft
        self.currentAction = checkpoint.draft.action
        self.currentTask = checkpoint.task
        onChange?()
    }

    public func makeRealitySnapshot(
        name: String,
        project: ProjectBrief,
        gitRoot: String,
        gitSnapshot: GitSnapshotRecord,
        parentID: UUID? = nil,
        contextClipCount: Int = 0,
        screenshotCount: Int = 0,
        activeAppBundle: String = "",
        browserTabs: [RealityBrowserTab] = []
    ) throws -> RealitySnapshot {
        guard let draft = draft else { throw RelayError.invalid("Compose a draft before saving a reality.") }
        let checkpoint = Checkpoint(project: project, capture: capture, task: currentTask, draft: draft)
        return RealitySnapshot(name: name, project: project, checkpoint: checkpoint, gitRoot: gitRoot,
                               gitSnapshot: gitSnapshot, parentID: parentID,
                               contextClipCount: contextClipCount, screenshotCount: screenshotCount,
                               activeAppBundle: activeAppBundle, browserTabs: browserTabs)
    }

    public func loadReality(_ reality: RealitySnapshot) throws {
        try reality.validate()
        loadCheckpoint(reality.checkpoint)
    }
}
