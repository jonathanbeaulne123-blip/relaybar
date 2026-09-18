import XCTest
@testable import RelayCore

final class QuickActionTests: XCTestCase {
    func testQuickActionValidation() {
        var action = QuickAction(name: "", command: "ls")
        XCTAssertThrowsError(try action.validate())
        
        action.name = "Valid Action"
        XCTAssertNoThrow(try action.validate())
        
        action.command = ""
        XCTAssertThrowsError(try action.validate())
    }
    
    func testWorkflowValidation() {
        var workflow = Workflow(name: "Test Flow", steps: [])
        XCTAssertThrowsError(try workflow.validate(), "Empty steps must throw")
        
        workflow.steps.append(WorkflowStep(actionID: UUID()))
        XCTAssertNoThrow(try workflow.validate())
    }
    
    func testCommandIndexSearch() {
        let index = CommandIndex()
        index.registerBuiltinCommands()
        
        let results = index.search("status")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.id == "git-status" }))
        
        let emptyQueryResults = index.search("")
        XCTAssertFalse(emptyQueryResults.isEmpty)
    }
}
