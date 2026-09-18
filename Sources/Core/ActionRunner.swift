import Foundation

public struct ActionResult: Equatable {
    public let actionID: UUID
    public let output: String
    public let exitCode: Int32
    public let startedAt: Date
    public let finishedAt: Date
    public let command: String
    
    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
    public var succeeded: Bool { exitCode == 0 }
    
    public var summary: String {
        let status = succeeded ? "✓" : "✗ (\(exitCode))"
        let time = String(format: "%.1fs", duration)
        return "\(status) \(command) — \(time)"
    }
}

public final class ActionRunner {
    public static let maxOutputBytes = 1_000_000 // 1MB output cap
    public static let defaultTimeout: TimeInterval = 300 // 5 minutes
    
    public private(set) var isRunning = false
    public private(set) var currentProcess: Process?
    public private(set) var lastResult: ActionResult?
    public var onOutput: ((String) -> Void)?  // streaming output callback
    public var onComplete: ((ActionResult) -> Void)?
    
    public init() {}
    
    // Run a QuickAction asynchronously
    public func run(_ action: QuickAction, projectRoot: String?, timeout: TimeInterval = defaultTimeout) {
        guard !isRunning else { return }
        isRunning = true
        
        let workDir = action.workingDirectory.resolve(projectRoot: projectRoot)
        let startedAt = Date()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", action.command]
        process.currentDirectoryURL = URL(fileURLWithPath: workDir)
        
        // Set up environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        process.environment = env
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        self.currentProcess = process
        
        let queue = DispatchQueue(label: "com.relaybar.actionrunner", qos: .userInitiated)
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var outputData = Data()
            let outputLock = NSLock()
            
            let appendData: (Data) -> Void = { data in
                outputLock.lock()
                defer { outputLock.unlock() }
                
                if outputData.count < Self.maxOutputBytes {
                    let allowedCount = min(data.count, Self.maxOutputBytes - outputData.count)
                    outputData.append(data.prefix(upTo: allowedCount))
                }
                
                if let str = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.onOutput?(str)
                    }
                }
            }
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                appendData(data)
            }
            
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                appendData(data)
            }
            
            var didTimeout = false
            let timeoutItem = DispatchWorkItem { [weak process] in
                didTimeout = true
                process?.terminate()
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // If it fails to run, it will drop through here and use the initial terminationStatus which might be 0, so we should set an exit code manually.
            }
            
            timeoutItem.cancel()
            
            pipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            
            outputLock.lock()
            let finalData = outputData
            outputLock.unlock()
            
            let outputString = String(data: finalData, encoding: .utf8) ?? ""
            let exitCode = didTimeout ? -1 : (process.isRunning ? -1 : process.terminationStatus)
            
            let result = ActionResult(
                actionID: action.id,
                output: outputString,
                exitCode: exitCode,
                startedAt: startedAt,
                finishedAt: Date(),
                command: action.command
            )
            
            DispatchQueue.main.async {
                self.lastResult = result
                self.isRunning = false
                self.currentProcess = nil
                self.onComplete?(result)
            }
        }
    }
    
    public func cancel() {
        currentProcess?.terminate()
        isRunning = false
    }
}
