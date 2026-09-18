import Foundation

public enum StepCondition: String, Codable, Equatable {
    case always           // Run regardless of previous step
    case previousSucceeded // Run only if previous step exited 0
    case previousFailed    // Run only if previous step exited non-zero
}

public struct WorkflowStep: Codable, Identifiable, Equatable {
    public let id: UUID
    public var actionID: UUID    // References a QuickAction
    public var delayAfter: TimeInterval
    public var condition: StepCondition
    
    public init(id: UUID = UUID(), actionID: UUID, delayAfter: TimeInterval = 0, condition: StepCondition = .previousSucceeded) {
        self.id = id
        self.actionID = actionID
        self.delayAfter = delayAfter
        self.condition = condition
    }
}

public struct Workflow: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var steps: [WorkflowStep]
    public var stopOnFailure: Bool
    
    public init(id: UUID = UUID(), name: String, icon: String = "🔗", steps: [WorkflowStep] = [], stopOnFailure: Bool = true) {
        self.id = id
        self.name = name
        self.icon = icon
        self.steps = steps
        self.stopOnFailure = stopOnFailure
    }
    
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayError.invalid("Workflow name cannot be empty.")
        }
        guard name.count <= 80 else {
            throw RelayError.invalid("Workflow name must be 80 characters or fewer.")
        }
        guard !steps.isEmpty else {
            throw RelayError.invalid("Workflow must have at least one step.")
        }
        guard steps.count <= 20 else {
            throw RelayError.invalid("Workflow is limited to 20 steps.")
        }
    }
    
    // Resolve step actions from a QuickAction list
    public func resolvedSteps(actions: [QuickAction]) -> [(step: WorkflowStep, action: QuickAction?)] {
        steps.map { step in (step: step, action: actions.first(where: { $0.id == step.actionID })) }
    }
}

public final class WorkflowRunner {
    public private(set) var isRunning = false
    public private(set) var currentStepIndex = 0
    public private(set) var results: [ActionResult] = []
    public var onStepComplete: ((Int, ActionResult) -> Void)?
    public var onWorkflowComplete: (([ActionResult]) -> Void)?
    
    private let actionRunner = ActionRunner()
    private var workflow: Workflow?
    private var resolvedSteps: [(step: WorkflowStep, action: QuickAction?)] = []
    private var projectRoot: String?
    private var cancelled = false
    
    public init() {}
    
    // Run a workflow by executing steps sequentially
    public func run(_ workflow: Workflow, actions: [QuickAction], projectRoot: String?) {
        guard !isRunning else { return }
        self.workflow = workflow
        self.resolvedSteps = workflow.resolvedSteps(actions: actions)
        self.projectRoot = projectRoot
        self.results = []
        self.currentStepIndex = 0
        self.isRunning = true
        self.cancelled = false
        executeNextStep(previousResult: nil)
    }
    
    public func cancel() {
        cancelled = true
        actionRunner.cancel()
        isRunning = false
    }
    
    private func executeNextStep(previousResult: ActionResult?) {
        guard !cancelled, currentStepIndex < resolvedSteps.count else {
            isRunning = false
            onWorkflowComplete?(results)
            return
        }
        
        let (step, action) = resolvedSteps[currentStepIndex]
        
        // Check condition
        if let prev = previousResult {
            switch step.condition {
            case .always: break
            case .previousSucceeded:
                guard prev.succeeded else {
                    if workflow?.stopOnFailure == true {
                        isRunning = false
                        onWorkflowComplete?(results)
                        return
                    }
                    currentStepIndex += 1
                    executeNextStep(previousResult: prev)
                    return
                }
            case .previousFailed:
                guard !prev.succeeded else {
                    currentStepIndex += 1
                    executeNextStep(previousResult: prev)
                    return
                }
            }
        }
        
        guard let action = action else {
            // Action was deleted; skip
            currentStepIndex += 1
            executeNextStep(previousResult: previousResult)
            return
        }
        
        let stepIndex = currentStepIndex
        actionRunner.onComplete = { [weak self] result in
            guard let self = self else { return }
            self.results.append(result)
            self.onStepComplete?(stepIndex, result)
            
            // Apply delay then continue
            let delay = step.delayAfter
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.currentStepIndex += 1
                    self.executeNextStep(previousResult: result)
                }
            } else {
                self.currentStepIndex += 1
                self.executeNextStep(previousResult: result)
            }
        }
        
        actionRunner.run(action, projectRoot: projectRoot)
    }
}
