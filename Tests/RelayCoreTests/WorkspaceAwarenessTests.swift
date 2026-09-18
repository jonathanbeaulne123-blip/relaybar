import XCTest
@testable import RelayCore

final class WorkspaceAwarenessTests: XCTestCase {
    func testProjectDetectorMarkerRecognition() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let packageSwift = tempDir.appendingPathComponent("Package.swift")
        try? "name: \"TestProject\"".write(to: packageSwift, atomically: true, encoding: .utf8)
        
        let detected = ProjectDetector.detect(from: tempDir.path)
        XCTAssertEqual(detected.type, .swift)
        XCTAssertEqual(detected.markerFile, "Package.swift")
    }
    
    func testGitSnapshotDefaults() {
        let empty = GitSnapshot.empty
        XCTAssertFalse(empty.isDirty)
        XCTAssertEqual(empty.branch, "")
        XCTAssertEqual(empty.modifiedCount, 0)
        XCTAssertEqual(empty.statusIndicator, "○")
    }
    
    func testWorkspaceStateDefaults() {
        let state = CommandCenterState()
        XCTAssertEqual(state.workspaceMode, .idle)
        XCTAssertEqual(state.detectedProject, .none)
        XCTAssertEqual(state.gitSnapshot, .empty)
    }
}
