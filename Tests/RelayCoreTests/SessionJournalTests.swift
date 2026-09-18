import XCTest
@testable import RelayCore

final class SessionJournalTests: XCTestCase {
    
    // MARK: - SessionJournal basics
    
    func testStartSession() {
        let journal = SessionJournal()
        XCTAssertFalse(journal.isRecording)
        
        journal.startSession()
        XCTAssertTrue(journal.isRecording)
        XCTAssertNotNil(journal.sessionStartedAt)
        XCTAssertEqual(journal.entries.count, 1)
        XCTAssertEqual(journal.entries.first?.kind, .sessionStart)
    }
    
    func testEndSession() {
        let journal = SessionJournal()
        journal.startSession()
        XCTAssertTrue(journal.isRecording)
        
        journal.endSession()
        XCTAssertFalse(journal.isRecording)
        XCTAssertNil(journal.sessionStartedAt)
        XCTAssertEqual(journal.entries.count, 2)
        XCTAssertEqual(journal.entries.last?.kind, .sessionEnd)
    }
    
    func testRecordWhileRecording() {
        let journal = SessionJournal()
        journal.startSession() // adds 1 entry
        journal.record(.note(text: "Test note"), app: "App")
        
        XCTAssertEqual(journal.entries.count, 2)
        XCTAssertEqual(journal.entries.last?.kind, .note(text: "Test note"))
    }
    
    func testRecordWhileNotRecording() {
        let journal = SessionJournal()
        journal.record(.note(text: "Test note"), app: "App")
        
        XCTAssertEqual(journal.entries.count, 0)
    }
    
    func testMaxEntries() {
        let journal = SessionJournal()
        journal.startSession()
        
        for i in 0..<510 {
            journal.record(.note(text: "Note \(i)"), app: "App")
        }
        
        XCTAssertEqual(journal.entries.count, SessionJournalPolicy.maxEntries)
        XCTAssertEqual(journal.entries.last?.kind, .note(text: "Note 509"))
    }
    
    func testDeduplication() {
        let journal = SessionJournal()
        journal.startSession()
        
        let kind = JournalEntryKind.note(text: "Same")
        journal.record(kind, app: "App")
        let countAfterFirst = journal.entries.count
        
        // Record identical right away
        journal.record(kind, app: "App")
        XCTAssertEqual(journal.entries.count, countAfterFirst)
        
        // Record different
        journal.record(.note(text: "Different"), app: "App")
        XCTAssertEqual(journal.entries.count, countAfterFirst + 1)
    }
    
    func testAddNote() throws {
        let journal = SessionJournal()
        journal.startSession()
        
        try journal.addNote("Hello world")
        XCTAssertEqual(journal.entries.last?.kind, .note(text: "Hello world"))
        
        // Trims spaces
        try journal.addNote("  Trim me  ")
        XCTAssertEqual(journal.entries.last?.kind, .note(text: "Trim me"))
        
        XCTAssertThrowsError(try journal.addNote("   "))
    }
    
    func testAddNoteTooLong() throws {
        let journal = SessionJournal()
        journal.startSession()
        
        let longNote = String(repeating: "A", count: 1001)
        XCTAssertThrowsError(try journal.addNote(longNote))
    }
    
    func testClear() {
        let journal = SessionJournal()
        journal.startSession()
        journal.record(.note(text: "Test"), app: "App")
        
        XCTAssertEqual(journal.entries.count, 2)
        XCTAssertTrue(journal.isRecording)
        
        journal.clear()
        
        XCTAssertEqual(journal.entries.count, 0)
        XCTAssertFalse(journal.isRecording)
        XCTAssertNil(journal.sessionStartedAt)
    }
    
    func testOnChangeCallback() {
        let journal = SessionJournal()
        var fireCount = 0
        journal.onChange = { fireCount += 1 }
        
        journal.startSession() // +1
        journal.record(.note(text: "1"), app: "App") // +1
        journal.endSession() // +1
        journal.clear() // +1
        
        XCTAssertEqual(fireCount, 4)
    }
    
    // MARK: - JournalEntry
    
    func testEntrySummary() {
        XCTAssertEqual(JournalEntry(kind: .projectSwitch(name: "A", type: "B"), appContext: "").summary, "Switched to project 'A' (B)")
        XCTAssertEqual(JournalEntry(kind: .branchChange(from: "main", to: "dev"), appContext: "").summary, "Changed branch from 'main' to 'dev'")
        XCTAssertEqual(JournalEntry(kind: .commandRun(name: "build", command: "make", exitCode: 0, durationSeconds: 1.5), appContext: "").summary, "Ran 'build' (make) — succeeded in 1.5s")
        XCTAssertEqual(JournalEntry(kind: .commandRun(name: "build", command: "make", exitCode: 1, durationSeconds: 1.5), appContext: "").summary, "Ran 'build' (make) — failed (code 1) in 1.5s")
        XCTAssertEqual(JournalEntry(kind: .contextClipAdded(preview: "clip"), appContext: "").summary, "Added context clip: \"clip\"")
        XCTAssertEqual(JournalEntry(kind: .screenshotTaken(index: 1), appContext: "").summary, "Captured screenshot #1")
        XCTAssertEqual(JournalEntry(kind: .workflowCompleted(name: "Deploy", stepCount: 5, successCount: 5), appContext: "").summary, "Completed workflow 'Deploy' (5/5 steps successful)")
        XCTAssertEqual(JournalEntry(kind: .note(text: "Hello"), appContext: "").summary, "Hello")
        XCTAssertEqual(JournalEntry(kind: .sessionStart, appContext: "").summary, "Session started")
        XCTAssertEqual(JournalEntry(kind: .sessionEnd, appContext: "").summary, "Session ended")
    }
    
    func testEntryCodable() throws {
        let entry = JournalEntry(kind: .note(text: "Test"), appContext: "App")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(JournalEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }
    
    // MARK: - SessionJournalExporter
    
    func testExportMarkdown() {
        let journal = SessionJournal()
        journal.startSession()
        journal.record(.note(text: "Hello"), app: "App")
        
        let md = SessionJournalExporter.exportMarkdown(journal: journal, projectName: "RelayBar")
        XCTAssertTrue(md.contains("# Session Journal: RelayBar"))
        XCTAssertTrue(md.contains("Session Duration:"))
        XCTAssertTrue(md.contains("Hello"))
        XCTAssertTrue(md.contains(SessionJournalPolicy.icon(for: .note(text: "Hello"))))
    }
    
    func testExportHandoffPacket() {
        let journal = SessionJournal()
        journal.startSession()
        journal.record(.commandRun(name: "test", command: "swift test", exitCode: 0, durationSeconds: 1.0), app: "App")
        journal.record(.branchChange(from: "main", to: "feature"), app: "App")
        journal.record(.contextClipAdded(preview: "code"), app: "App")
        
        let gitSnapshot = GitSnapshot(branch: "feature", isDirty: true, untrackedCount: 1, modifiedCount: 2, stagedCount: 0, aheadBy: 0, behindBy: 0, recentCommits: [], fetchedAt: Date())
        
        let packet = SessionJournalExporter.exportHandoffPacket(journal: journal, projectName: "RelayBar", gitSnapshot: gitSnapshot)
        
        XCTAssertTrue(packet.contains("## Handoff Packet: RelayBar"))
        XCTAssertTrue(packet.contains("- **Commands Run:** 1 (100% success)"))
        XCTAssertTrue(packet.contains("- **Branches Touched:** 2")) // main and feature
        XCTAssertTrue(packet.contains("- **Clips Collected:** 1"))
        XCTAssertTrue(packet.contains("- **Branch:** feature"))
        XCTAssertTrue(packet.contains("- **Status:** \(gitSnapshot.statusSummary)"))
        XCTAssertTrue(packet.contains("swift test"))
    }
    
    func testExportEmptyJournal() {
        let journal = SessionJournal() // empty, not started
        
        let md = SessionJournalExporter.exportMarkdown(journal: journal, projectName: "Empty")
        XCTAssertTrue(md.contains("# Session Journal: Empty"))
        
        let packet = SessionJournalExporter.exportHandoffPacket(journal: journal, projectName: "Empty", gitSnapshot: .empty)
        XCTAssertTrue(packet.contains("## Handoff Packet: Empty"))
        XCTAssertTrue(packet.contains("- **Branch:** None"))
    }
}
