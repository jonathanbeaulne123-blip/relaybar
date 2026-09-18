import XCTest
@testable import RelayCore

final class NativeScanBudgetTests: XCTestCase {
    func testReadPolicyKeepsTimeQueryNodeAndDepthBounds() {
        XCTAssertEqual(NativeReadBudget.seconds,0.85)
        XCTAssertEqual(NativeReadBudget.maximumQueries,5000)
        XCTAssertEqual(NativeMenuPolicy.maximumNodes,900)
        XCTAssertEqual(NativeMenuPolicy.maximumMenuNodes,1600)
        XCTAssertEqual(NativeMenuPolicy.maximumDepth,24)
    }
    func testPagesRemainSmallAndTotalChildListBounded() {
        XCTAssertEqual(NativeReadBudget.childPageSize,64)
        XCTAssertEqual(NativeReadBudget.maximumChildren,4096)
    }
    func testExactly5000QueriesAllowedThenStop() {
        var b=NativeReadBudget(now:0)
        for _ in 0..<5000 { XCTAssertTrue(b.take(now:0.1,cancelled:false)) }
        XCTAssertFalse(b.take(now:0.1,cancelled:false)); XCTAssertEqual(b.failure,.queries)
        XCTAssertEqual(b.queries,5000)
    }
    func testDeadlineFailsBeforeAnAdditionalIPC() {
        var b=NativeReadBudget(now:0)
        XCTAssertFalse(b.take(now:0.851,cancelled:false)); XCTAssertEqual(b.failure,.deadline)
        XCTAssertEqual(b.queries,0)
    }
    func testExactDeadlineBoundaryAllowed() {
        var b=NativeReadBudget(now:0); XCTAssertTrue(b.take(now:0.85,cancelled:false))
    }
    func testCancellationDoesNotConsumeAQuery() {
        var b=NativeReadBudget(now:0); XCTAssertFalse(b.take(now:0.1,cancelled:true))
        XCTAssertEqual(b.queries,0); XCTAssertEqual(b.failure,.cancelled)
    }
    func testClockRegressionAndNonFiniteClockFailClosed() {
        for time in [-1.0,Double.nan,Double.infinity] {
            var b=NativeReadBudget(now:0); XCTAssertFalse(b.take(now:time,cancelled:false))
            XCTAssertEqual(b.failure,.deadline)
        }
    }
    func testInvalidStartFailsClosed() {
        var b=NativeReadBudget(now:.nan); XCTAssertFalse(b.take(now:0,cancelled:false))
    }
    func testFirstFailureIsPreserved() {
        var b=NativeReadBudget(now:0); b.fail(.children); b.fail(.readFailed)
        XCTAssertEqual(b.currentFailure(now:0.1,cancelled:false),.children)
    }
    func testCancellationOverridesOlderFailureInCurrentReport() {
        var b=NativeReadBudget(now:0); b.fail(.queries)
        XCTAssertEqual(b.currentFailure(now:0.1,cancelled:true),.cancelled)
    }
    func testNewReadResetsFailuresAndCounts() {
        var b=NativeReadBudget(now:0); _=b.take(now:0.1,cancelled:false);b.fail(.children)
        b=NativeReadBudget(now:2); XCTAssertEqual(b.queries,0);XCTAssertEqual(b.failure,.none)
        XCTAssertTrue(b.take(now:2.1,cancelled:false))
    }
    func testAllFailureDescriptionsAreDistinct() {
        let cases:[NativeScanFailure]=[.none,.deadline,.queries,.children,.depth,.nodes,.readFailed,.cancelled]
        XCTAssertEqual(Set(cases.map(\.explanation)).count,cases.count)
    }
}
