import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class ThoughtEngineTests: XCTestCase {
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
}
