import XCTest
@testable import RelayCore

/// Rehearsal exists so an uncommitted working tree is never the experiment.
/// These tests cover the guards; they deliberately never create a worktree, so
/// no developer checkout is touched.
final class RehearsalWorktreeTests: XCTestCase {

    func testBranchNamesDerivedFromTheLedgerAreValid() {
        let ledgerID = UUID()
        let branch = RehearsalWorktree.branchName(ledgerID: ledgerID)
        XCTAssertTrue(branch.hasPrefix("relaybar/verify-"))
        XCTAssertTrue(GitWorktree.isValidBranchName(branch))
    }

    func testBranchValidationRejectsGitPunctuation() {
        for invalid in ["", "-x", "x/", ".", "..", "a..b", "a b", "a^b", "a~b", "a:b", "a?b", "a[b]"] {
            XCTAssertFalse(GitWorktree.isValidBranchName(invalid), "\(invalid) must be refused")
        }
        XCTAssertTrue(GitWorktree.isValidBranchName("relaybar/verify-ab12cd34"))
        XCTAssertTrue(GitWorktree.isValidBranchName("reality/try-1"))
    }

    func testDestinationIsAlwaysOutsideTheSourceCheckout() {
        let destination = RehearsalWorktree.destinationRoot(gitRoot: "/tmp/work/project", ledgerID: UUID())
        XCTAssertEqual(URL(fileURLWithPath: destination).deletingLastPathComponent().path, "/tmp/work")
        XCTAssertTrue(URL(fileURLWithPath: destination).lastPathComponent.hasPrefix("relaybar-rehearsal-"))
    }

    func testPlanRefusesADestinationInsideTheCheckout() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let inside = sandbox.appendingPathComponent("rehearsal").path
        XCTAssertThrowsError(try RehearsalWorktree().plan(sourceRoot: sandbox.path, baseCommit: "abc123",
                                                         ledgerID: UUID(), destinationRoot: inside)) { error in
            XCTAssertEqual(error as? RehearsalError, .destinationInsideSource)
        }
    }

    func testPlanRefusesAnExistingDestination() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let taken = sandbox.deletingLastPathComponent().appendingPathComponent("taken-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: taken) }
        XCTAssertThrowsError(try RehearsalWorktree().plan(sourceRoot: sandbox.path, baseCommit: "abc123",
                                                         ledgerID: UUID(), destinationRoot: taken.path)) { error in
            XCTAssertEqual(error as? RehearsalError, .destinationExists)
        }
    }

    func testPlanRefusesWithoutACommitOrARealCheckout() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        XCTAssertThrowsError(try RehearsalWorktree().plan(sourceRoot: sandbox.path, baseCommit: "",
                                                         ledgerID: UUID())) { error in
            XCTAssertEqual(error as? RehearsalError, .missingRepository)
        }
        let missing = sandbox.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try RehearsalWorktree().plan(sourceRoot: missing.path, baseCommit: "abc123",
                                                         ledgerID: UUID())) { error in
            XCTAssertEqual(error as? RehearsalError, .missingRepository)
        }
    }

    func testPlanProducesAUsablePlan() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let ledgerID = UUID()
        let plan = try RehearsalWorktree().plan(sourceRoot: sandbox.path, baseCommit: "abc123", ledgerID: ledgerID)
        XCTAssertEqual(plan.sourceRoot, sandbox.standardizedFileURL.path)
        XCTAssertEqual(plan.baseCommit, "abc123")
        XCTAssertEqual(plan.branchName, RehearsalWorktree.branchName(ledgerID: ledgerID))
        XCTAssertFalse(GitWorktree.isInside(URL(fileURLWithPath: plan.destinationRoot),
                                           source: URL(fileURLWithPath: plan.sourceRoot)))
    }

    /// The Fork Reality path and the rehearsal path must agree on what a safe
    /// branch name and an unsafe destination are, which is why both now use
    /// `GitWorktree` instead of duplicate private copies.
    func testRealityForkerKeepsRefusingUnsafeRequests() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }
        let project = ProjectBrief.starters[1]
        let draft = try PromptEngine.compose(action: .nextSlice, project: project, capture: .empty, task: "t", target: .chatgpt)
        let snapshot = RealitySnapshot(
            name: "Moment", project: project,
            checkpoint: Checkpoint(project: project, capture: .empty, task: "t", draft: draft),
            gitRoot: sandbox.path,
            gitSnapshot: GitSnapshotRecord(branch: "main", commit: "abc123", isDirty: false, modifiedCount: 0, stagedCount: 0, untrackedCount: 0)
        )
        XCTAssertThrowsError(try RealityForker().plan(snapshot: snapshot, destinationRoot: sandbox.path + "-fork",
                                                     branchName: "../destroy")) { error in
            XCTAssertEqual(error as? RealityForkError, .invalidBranch)
        }
        XCTAssertThrowsError(try RealityForker().plan(snapshot: snapshot,
                                                     destinationRoot: sandbox.appendingPathComponent("inner").path,
                                                     branchName: "reality/try")) { error in
            XCTAssertEqual(error as? RealityForkError, .destinationInsideSource)
        }
    }

    private func makeSandbox() throws -> URL {
        let sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        return sandbox
    }
}
