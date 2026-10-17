import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class ThoughtEngineTests: XCTestCase {
    func testCaptureReturnsStoredIDAndRepeatedTextCreatesDistinctThoughts() throws {
        var state = AppSnapshot()
        let now = Date()
        let origin = UUID()
        let context = ThoughtCaptureContext(projectID: nil, originSessionID: origin)
        let first = try ThoughtEngine.capture(&state, context: context, text: "  Remember  ", now: now)
        let second = try ThoughtEngine.capture(&state, context: context, text: "Remember", now: now)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(state.thoughts.map(\.id), [first, second])
        XCTAssertEqual(state.thoughts.map(\.text), ["Remember", "Remember"])
        XCTAssertEqual(state.thoughts.map(\.originSessionID), [origin, origin])
        XCTAssertEqual(state.thoughts.map(\.createdAt), [now, now])
    }

    func testThoughtSurvivesDiscardDeletionMergeAndBackupWithCompletion() throws {
        let now = Date()
        var state = AppSnapshot(projects: [Project(name: "First"), Project(name: "Destination")])
        let source = state.projects[0].id, destination = state.projects[1].id
        try TimerEngine.startFocus(&state, projectID: source, minutes: 10, now: now)
        let timer = try XCTUnwrap(state.activeTimer)
        let context = ThoughtCaptureContext(projectID: source, originSessionID: timer.id)
        TimerEngine.discardFocus(&state, timerID: timer.id)
        try ThoughtEngine.capture(&state, context: context, text: "  Check this later  ", now: now)
        let id = state.thoughts[0].id
        try ThoughtEngine.setCompleted(&state, id: id, completed: true, now: now.addingTimeInterval(1))
        try ThoughtEngine.setCompleted(&state, id: id, completed: true, now: now.addingTimeInterval(2))
        XCTAssertEqual(state.thoughts[0].completedAt, now.addingTimeInterval(1))
        TimerEngine.deleteSession(&state, sessionID: timer.id)
        try TimerEngine.merge(&state, source: source, destination: destination)
        XCTAssertEqual(state.thoughts[0].projectID, destination)
        XCTAssertEqual(state.thoughts[0].originSessionID, timer.id)
        XCTAssertEqual(state.thoughts[0].text, "Check this later")
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state)), state)
        try ThoughtEngine.setCompleted(&state, id: id, completed: false, now: now)
        XCTAssertNil(state.thoughts[0].completedAt)
        try ThoughtEngine.setCompleted(&state, id: id, completed: true, now: now.addingTimeInterval(3))
        XCTAssertEqual(state.thoughts[0].completedAt, now.addingTimeInterval(3))
        XCTAssertThrowsError(try ThoughtEngine.capture(&state, context: context, text: "Missing project", now: now))
    }
    func testStandaloneThoughtAndOptionalProjectRoundTrip() throws {
        var state = AppSnapshot()
        try ThoughtEngine.capture(&state, context: ThoughtCaptureContext(projectID: nil, originSessionID: nil),
                                  text: "  Remember this  ", now: Date())
        XCTAssertNil(state.thoughts[0].projectID)
        XCTAssertNil(state.thoughts[0].originSessionID)
        XCTAssertEqual(state.thoughts[0].text, "Remember this")
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state)), state)
        XCTAssertTrue(ThoughtProjectFilter.unassigned.includes(nil))
        XCTAssertFalse(ThoughtProjectFilter.project(UUID()).includes(nil))
        state.thoughts[0].projectID = UUID()
        XCTAssertThrowsError(try BackupService.encode(state))
    }

    func testV7ThoughtMigrationPreservesAssignmentAndRejectsMissingLegacyProject() throws {
        let project = Project(name: "Research")
        let thought = CapturedThought(projectID: project.id, originSessionID: UUID(), createdAt: Date(), text: "Source")
        let state = AppSnapshot(projects: [project], thoughts: [thought])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupService.encode(state)) as? [String: Any])
        json["schemaVersion"] = 7
        let migrated = try BackupService.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated, state)
        var legacyThoughts = try XCTUnwrap(json["thoughts"] as? [[String: Any]])
        legacyThoughts[0].removeValue(forKey: "projectID")
        json["thoughts"] = legacyThoughts
        XCTAssertThrowsError(try BackupService.decode(JSONSerialization.data(withJSONObject: json)))
    }

}
