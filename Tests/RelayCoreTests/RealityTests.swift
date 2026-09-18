import XCTest
@testable import RelayCore

final class RealityTests: XCTestCase {
    private let project = ProjectBrief.starters[1]

    private func checkpoint() throws -> Checkpoint {
        let draft = try PromptEngine.compose(action: .nextSlice, project: project, capture: .empty, task: "Try the alternate layout", target: .chatgpt)
        return Checkpoint(project: project, capture: .empty, task: "Try the alternate layout", draft: draft)
    }

    private func snapshot(root: String, dirty: Bool = false) throws -> RealitySnapshot {
        RealitySnapshot(
            name: "Before navigation experiment",
            project: project,
            checkpoint: try checkpoint(),
            gitRoot: root,
            gitSnapshot: GitSnapshotRecord(branch: "main", commit: "0123456789abcdef", isDirty: dirty, modifiedCount: dirty ? 1 : 0, stagedCount: 0, untrackedCount: 0),
            contextClipCount: 2,
            screenshotCount: 1,
            activeAppBundle: "com.google.Chrome"
        )
    }

    func testRealitySnapshotRoundTrip() throws {
        let original = try snapshot(root: "/tmp/hearth")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(RealitySnapshot.self, from: data)
        XCTAssertEqual(restored, original)
    }

    func testDirtyRealityCanBePlannedWhenPayloadIsBounded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var reality = try snapshot(root: root.path, dirty: true)
        reality = RealitySnapshot(id: reality.id, savedAt: reality.savedAt, name: reality.name, project: reality.project,
                                  checkpoint: reality.checkpoint, gitRoot: reality.gitRoot, gitSnapshot: reality.gitSnapshot,
                                  dirtyWorkingTree: RealityDirtyWorkingTree(trackedPatch: Data("patch".utf8), untrackedFiles: [RealityUntrackedFile(relativePath: "notes.txt", contents: Data("notes".utf8))]))
        XCTAssertNoThrow(try RealityForker().plan(snapshot: reality, destinationRoot: root.path + "-fork", branchName: "reality/try"))
    }

    func testForkPlanRejectsDestinationInsideSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reality = try snapshot(root: root.path)
        XCTAssertThrowsError(try RealityForker().plan(snapshot: reality, destinationRoot: root.appendingPathComponent("fork").path, branchName: "reality/try")) { error in
            XCTAssertEqual(error as? RealityForkError, .destinationInsideSource)
        }
    }

    func testForkPlanRejectsUnsafeBranchName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let reality = try snapshot(root: root.path)
        XCTAssertThrowsError(try RealityForker().plan(snapshot: reality, destinationRoot: root.path + "-fork", branchName: "../destroy")) { error in
            XCTAssertEqual(error as? RealityForkError, .invalidBranch)
        }
    }

    func testRealityPersistenceIsPrivateAndListedNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("relaybar-reality-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LocalStore(directory: root)
        var older = try snapshot(root: "/tmp/older")
        older.name = "Older"
        let newer = try snapshot(root: "/tmp/newer")
        _ = try store.saveReality(older)
        _ = try store.saveReality(newer)
        let realities = try store.listRealities()
        XCTAssertEqual(realities.count, 2)
        XCTAssertEqual(realities.first?.name, newer.name)
        let mode = try FileManager.default.attributesOfItem(atPath: store.realitiesURL.path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(mode.intValue & 0o777, 0o700)
    }

    func testWhatChangedReportsSemanticAndGitDifferences() throws {
        let first = try snapshot(root: "/tmp/project")
        let secondCheckpoint = Checkpoint(project: project, capture: Capture(text: "new reference", origin: "Manual"), task: "New task", draft: try PromptEngine.compose(action: .challenge, project: project, capture: Capture(text: "new reference", origin: "Manual"), task: "New task", target: .claude))
        let second = RealitySnapshot(name: "After experiment", project: project, checkpoint: secondCheckpoint, gitRoot: "/tmp/project", gitSnapshot: GitSnapshotRecord(branch: "experiment", commit: "fedcba987654", isDirty: true, modifiedCount: 3, stagedCount: 1, untrackedCount: 2), contextClipCount: 4, screenshotCount: 3)
        let report = RealityDiff.compare(first, second)
        XCTAssertTrue(report.text.contains("Git branch: main → experiment"))
        XCTAssertTrue(report.text.contains("Modified files: 0 → 3 (+3)"))
        XCTAssertTrue(report.text.contains("Reference capture changed"))
        XCTAssertTrue(report.text.contains("Prompt draft changed"))
        XCTAssertTrue(report.text.contains("Context clips: 2 → 4 (+2)"))
    }

    func testWhatChangedReportsNoChanges() throws {
        let first = try snapshot(root: "/tmp/project")
        let report = RealityDiff.compare(first, first)
        XCTAssertEqual(report.lines, [])
        XCTAssertTrue(report.text.contains("No recorded changes."))
    }

    func testFileChangesExtractTrackedAndUntrackedFiles() throws {
        let patch = """
diff --git a/Sources/New.swift b/Sources/New.swift
new file mode 100644
--- /dev/null
+++ b/Sources/New.swift
@@ -0,0 +1 @@
+let value = 1
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1 +1 @@
-old
+new
"""
        let base = try snapshot(root: "/tmp/project")
        let reality = RealitySnapshot(name: base.name, project: base.project, checkpoint: base.checkpoint, gitRoot: base.gitRoot,
                                      gitSnapshot: base.gitSnapshot,
                                      dirtyWorkingTree: RealityDirtyWorkingTree(trackedPatch: Data(patch.utf8), untrackedFiles: [RealityUntrackedFile(relativePath: "notes.txt", contents: Data("notes".utf8))]))
        let files = RealityDiff.files(in: reality)
        XCTAssertEqual(files.map(\.path), ["README.md", "Sources/New.swift", "notes.txt"])
        XCTAssertEqual(files.first(where: { $0.path == "Sources/New.swift" })?.kind, .added)
        XCTAssertEqual(files.first(where: { $0.path == "README.md" })?.kind, .modified)
        XCTAssertEqual(files.first(where: { $0.path == "notes.txt" })?.detail, "untracked")
    }

    func testSelectedPatchContainsOnlyRequestedFiles() throws {
        let patch = """
diff --git a/one.txt b/one.txt
--- a/one.txt
+++ b/one.txt
@@ -1 +1 @@
-a
+b
diff --git a/two.txt b/two.txt
--- a/two.txt
+++ b/two.txt
@@ -1 +1 @@
-c
+d
"""
        let base = try snapshot(root: "/tmp/project")
        let reality = RealitySnapshot(name: base.name, project: base.project, checkpoint: base.checkpoint, gitRoot: base.gitRoot,
                                      gitSnapshot: base.gitSnapshot,
                                      dirtyWorkingTree: RealityDirtyWorkingTree(trackedPatch: Data(patch.utf8), untrackedFiles: []))
        let selected = RealityDiff.trackedPatch(for: ["two.txt"], in: reality)
        let text = String(decoding: selected, as: UTF8.self)
        XCTAssertTrue(text.contains("two.txt"))
        XCTAssertFalse(text.contains("one.txt"))
    }

    func testHunksCanBeSelectedIndividually() throws {
        let patch = """
diff --git a/one.txt b/one.txt
--- a/one.txt
+++ b/one.txt
@@ -1 +1 @@
-a
+b
@@ -4 +4 @@
-c
+d
"""
        let base = try snapshot(root: "/tmp/project")
        let reality = RealitySnapshot(name: base.name, project: base.project, checkpoint: base.checkpoint, gitRoot: base.gitRoot,
                                      gitSnapshot: base.gitSnapshot,
                                      dirtyWorkingTree: RealityDirtyWorkingTree(trackedPatch: Data(patch.utf8), untrackedFiles: []))
        let hunks = RealityDiff.hunks(in: reality)
        XCTAssertEqual(hunks.count, 2)
        let selected = RealityDiff.selectedHunkPatch([hunks[1].id], in: reality)
        let selectedText = String(decoding: selected, as: UTF8.self)
        XCTAssertTrue(selectedText.contains("@@ -4 +4 @@"))
        XCTAssertFalse(selectedText.contains("@@ -1 +1 @@"))
    }

    func testGitSnapshotRecordValidation() {
        XCTAssertNoThrow(try GitSnapshotRecord(branch: "main", commit: "abc", isDirty: false, modifiedCount: 0, stagedCount: 0, untrackedCount: 0).validate())
        XCTAssertThrowsError(try GitSnapshotRecord(branch: "main", commit: "abc", isDirty: false, modifiedCount: -1, stagedCount: 0, untrackedCount: 0).validate())
    }
}
