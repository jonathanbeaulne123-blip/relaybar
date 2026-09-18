import Foundation

public enum ProjectType: String, Codable, CaseIterable {
    case swift, node, rust, python, cMake, xcode, go, ruby, unknown
    
    public var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .node: return "Node.js"
        case .rust: return "Rust"
        case .python: return "Python"
        case .cMake: return "CMake"
        case .xcode: return "Xcode"
        case .go: return "Go"
        case .ruby: return "Ruby"
        case .unknown: return "Unknown"
        }
    }
    
    public var icon: String {
        switch self {
        case .swift: return "🦅"
        case .node: return "📦"
        case .rust: return "🦀"
        case .python: return "🐍"
        case .cMake: return "🛠"
        case .xcode: return "🔨"
        case .go: return "🐹"
        case .ruby: return "💎"
        case .unknown: return "📁"
        }
    }
}

public struct DetectedProject: Equatable, Codable {
    public let name: String
    public let root: String
    public let type: ProjectType
    public let markerFile: String
    
    public static let none = DetectedProject(name: "", root: "", type: .unknown, markerFile: "")
}

public enum ProjectDetector {
    public static func detect(from path: String) -> DetectedProject {
        let fm = FileManager.default
        let current = URL(fileURLWithPath: path)
        var gitRoot: URL? = nil
        
        // Find Git root first
        var scan = current
        while scan.path != "/" {
            let gitPath = scan.appendingPathComponent(".git").path
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: gitPath, isDirectory: &isDir) {
                gitRoot = scan
                break
            }
            scan = scan.deletingLastPathComponent()
        }
        
        let boundary = gitRoot?.path ?? "/"
        scan = current
        
        while scan.path != "/" {
            for marker in markers {
                let markerPath = scan.appendingPathComponent(marker.file).path
                if fm.fileExists(atPath: markerPath) {
                    let type = marker.type
                    let name = projectName(in: scan.path, type: type)
                    return DetectedProject(name: name, root: scan.path, type: type, markerFile: marker.file)
                }
            }
            
            let contents = try? fm.contentsOfDirectory(atPath: scan.path)
            if let xcodeProj = contents?.first(where: { $0.hasSuffix(".xcodeproj") }) {
                return DetectedProject(name: URL(fileURLWithPath: xcodeProj).deletingPathExtension().lastPathComponent, root: scan.path, type: .xcode, markerFile: xcodeProj)
            }
            
            if scan.path == boundary {
                break
            }
            scan = scan.deletingLastPathComponent()
        }
        
        if let git = gitRoot {
            return DetectedProject(name: git.lastPathComponent, root: git.path, type: .unknown, markerFile: ".git")
        }
        
        return .none
    }
    
    public static func detectType(in root: String) -> ProjectType {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: root)
        for marker in markers {
            if fm.fileExists(atPath: url.appendingPathComponent(marker.file).path) {
                return marker.type
            }
        }
        
        let contents = try? fm.contentsOfDirectory(atPath: root)
        if contents?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true {
            return .xcode
        }
        
        return .unknown
    }
    
    public static func projectName(in root: String, type: ProjectType) -> String {
        let url = URL(fileURLWithPath: root)
        let defaultName = url.lastPathComponent
        
        switch type {
        case .node:
            let packageJson = url.appendingPathComponent("package.json")
            if let content = try? String(contentsOf: packageJson, encoding: .utf8) {
                if let range = content.range(of: "\"name\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    let match = String(content[range])
                    let comps = match.components(separatedBy: "\"")
                    if comps.count >= 4 {
                        return comps[3]
                    }
                }
            }
        case .swift:
            let packageSwift = url.appendingPathComponent("Package.swift")
            if let content = try? String(contentsOf: packageSwift, encoding: .utf8) {
                if let range = content.range(of: "name:\\s*\"([^\"]+)\"", options: .regularExpression) {
                    let match = String(content[range])
                    let comps = match.components(separatedBy: "\"")
                    if comps.count >= 2 {
                        return comps[1]
                    }
                }
            }
        default:
            break
        }
        
        return defaultName
    }
    
    private static let markers: [(file: String, type: ProjectType)] = [
        ("Package.swift", .swift), ("package.json", .node), ("Cargo.toml", .rust),
        ("pyproject.toml", .python), ("setup.py", .python), ("go.mod", .go),
        ("Gemfile", .ruby), ("CMakeLists.txt", .cMake), ("Makefile", .cMake)
    ]
}
