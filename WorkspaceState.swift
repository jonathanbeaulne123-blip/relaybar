import Foundation

public enum WorkspaceMode: String, Codable {
    case idle
    case project
    case assistant
}

public struct CommandCenterState: Equatable {
    public var workspaceMode: WorkspaceMode = .idle
    public var detectedProject: DetectedProject = .none
    public var gitSnapshot: GitSnapshot = .empty
    public var activeAppName: String = ""
    public var activeAppBundle: String = ""
    public var quickActionCount: Int = 0
    public var workflowCount: Int = 0
    public var pluginCount: Int = 0
    
    public init() {}
    
    public var menuBarTitle: String {
        if detectedProject == .none {
            return "RB"
        }
        if gitSnapshot.branch.isEmpty {
            return "RB · \(detectedProject.name)"
        }
        return "RB · \(detectedProject.name) (\(gitSnapshot.branch))"
    }
    
    public var menuBarTooltip: String {
        if detectedProject == .none {
            return "RelayBar: Idle"
        }
        var parts = ["Project: \(detectedProject.name) (\(detectedProject.type.displayName))"]
        if !gitSnapshot.branch.isEmpty {
            parts.append("Git: \(gitSnapshot.statusSummary)")
        }
        return parts.joined(separator: "\n")
    }
}

public final class WorkspaceStateController {
    public private(set) var state = CommandCenterState()
    public var onChange: (() -> Void)?
    
    private let gitMonitor = GitMonitor()
    private let fm = FileManager.default
    
    public init() {
        gitMonitor.onChange = { [weak self] in
            guard let self = self else { return }
            self.state.gitSnapshot = self.gitMonitor.snapshot
            self.onChange?()
        }
    }
    
    public func activeAppChanged(name: String, bundle: String, pid: pid_t) {
        state.activeAppName = name
        state.activeAppBundle = bundle
        
        if let workingDir = inferWorkingDirectory(bundle: bundle, pid: pid) {
            let project = ProjectDetector.detect(from: workingDir)
            if project != state.detectedProject {
                state.detectedProject = project
                if !project.root.isEmpty {
                    state.workspaceMode = .project
                    gitMonitor.refresh(at: project.root)
                } else {
                    state.workspaceMode = .idle
                    state.gitSnapshot = .empty
                }
            } else if !project.root.isEmpty {
                gitMonitor.refresh(at: project.root)
            }
        }
        onChange?()
    }
    
    public func refreshGit() {
        guard !state.detectedProject.root.isEmpty else { return }
        gitMonitor.refresh(at: state.detectedProject.root)
    }
    
    private func inferWorkingDirectory(bundle: String, pid: pid_t) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-d", "cwd", "-p", "\(pid)", "-Fn"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.hasPrefix("n") {
                            return String(line.dropFirst())
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        
        return fm.homeDirectoryForCurrentUser.path
    }
}
